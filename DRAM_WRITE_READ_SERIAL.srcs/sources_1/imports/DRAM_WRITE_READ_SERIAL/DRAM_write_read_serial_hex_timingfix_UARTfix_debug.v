`timescale 1ns / 1ps

module dram_simple (
    // System
    input  wire         CLK100MHZ,
    input  wire [3:0]   sw,
    output wire [3:0]   LED,
    
    // UART
    output wire         uart_txd_in,
    
    // DDR3 interface
    output wire [13:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,
    output wire         ddr3_cas_n,
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_ck_p,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_cs_n,
    output wire [1:0]   ddr3_dm,
    inout  wire [15:0]  ddr3_dq,
    inout  wire [1:0]   ddr3_dqs_n,
    inout  wire [1:0]   ddr3_dqs_p,
    output wire [0:0]   ddr3_odt,
    output wire         ddr3_ras_n,
    output wire         ddr3_reset_n,
    output wire         ddr3_we_n
);

    // State machine
    localparam RESET     = 0;
    localparam INIT_NOP  = 1;
    localparam INIT_MRS2 = 2;
    localparam INIT_MRS3 = 3;
    localparam INIT_MRS1 = 4;
    localparam INIT_MRS0 = 5;
    localparam INIT_ZQCL = 6;
    localparam IDLE      = 7;
    localparam ACTIVATE  = 8;
    localparam WRITE     = 9;
    localparam READ      = 10;
    localparam PRECHARGE = 11;
    
    reg [3:0] state = RESET;
    reg [19:0] delay_cnt = 0;
    
    // DDR3 clock generation (200MHz from 100MHz)
    reg clk_ddr = 0;
    always @(posedge CLK100MHZ) clk_ddr <= ~clk_ddr;
    
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) ddr_ck_p_inst (
        .Q(ddr3_ck_p), .C(clk_ddr), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) ddr_ck_n_inst (
        .Q(ddr3_ck_n), .C(clk_ddr), .CE(1'b1), .D1(1'b0), .D2(1'b1), .R(1'b0), .S(1'b0));
    
    // Control signals
    reg         reset_n = 0;
    reg         cke = 0;
    reg         cs_n = 1;
    reg         ras_n = 1;
    reg         cas_n = 1;
    reg         we_n = 1;
    reg [13:0]  addr = 0;
    reg [2:0]   ba = 0;
    reg         odt = 0;
    
    // Data signals
    reg [15:0]  dq_out = 0;
    reg         dq_oe = 0;
    reg [1:0]   dqs_out = 0;
    reg         dqs_oe = 0;
    reg [1:0]   dm = 0;
    
    // Simple read/write interface
    reg         cmd_valid = 0;
    reg         cmd_write = 0;
    reg [26:0]  cmd_addr = 0;
    reg [15:0]  cmd_data = 0;
    wire [15:0] read_data = ddr3_dq;
    reg [15:0]  captured_read_data = 16'hDEAD;
    reg [15:0]  last_write_data = 16'hBEEF;
    
    // Operation tracking - only driven from DDR clock domain
    reg write_started_ddr = 0;
    reg read_started_ddr = 0;
    reg write_done_ddr = 0;
    reg read_done_ddr = 0;
    
    // Synchronized versions for 100MHz domain
    reg write_started = 0;
    reg read_started = 0;
    reg write_done = 0;
    reg read_done = 0;
    reg [1:0] write_started_sync = 0;
    reg [1:0] read_started_sync = 0;
    reg [1:0] write_done_sync = 0;
    reg [1:0] read_done_sync = 0;
    
    // UART signals
    reg         uart_send = 0;
    reg [7:0]   uart_data = 0;
    wire        uart_busy;
    wire        uart_done;
    
    // Debug message queue
    reg [7:0]   debug_char = 0;
    reg         send_debug_char = 0;
    
    // Switch handling with synchronization
    reg [3:0] sw_sync = 0;
    reg [3:0] sw_prev = 0;
    
    always @(posedge CLK100MHZ) begin
        sw_sync <= sw;
        sw_prev <= sw_sync;
    end
    
    wire sw0_pressed = sw_sync[0] && !sw_prev[0];
    wire sw1_pressed = sw_sync[1] && !sw_prev[1];
    wire sw2_pressed = sw_sync[2] && !sw_prev[2];
    wire sw3_pressed = sw_sync[3] && !sw_prev[3];
    
    // Test pattern counter
    reg [3:0] pattern_cnt = 0;
    
    // Clock domain crossing - DDR to 100MHz
    always @(posedge CLK100MHZ) begin
        // Two-stage synchronizers
        write_started_sync <= {write_started_sync[0], write_started_ddr};
        read_started_sync <= {read_started_sync[0], read_started_ddr};
        write_done_sync <= {write_done_sync[0], write_done_ddr};
        read_done_sync <= {read_done_sync[0], read_done_ddr};
        
        // Edge detection
        write_started <= write_started_sync[0] && !write_started_sync[1];
        read_started <= read_started_sync[0] && !read_started_sync[1];
        write_done <= write_done_sync[0] && !write_done_sync[1];
        read_done <= read_done_sync[0] && !read_done_sync[1];
    end
    
    // UART state machine - simplified single character sender
    reg [2:0] uart_state = 0;
    reg [26:0] timeout_cnt = 0;
    
    always @(posedge CLK100MHZ) begin
        timeout_cnt <= timeout_cnt + 1;
        
        case (uart_state)
            0: begin  // Idle
                uart_send <= 0;
                
                // Priority order for messages
                if (sw3_pressed || (timeout_cnt == 27'd100000000)) begin  // Heartbeat
                    debug_char <= 8'h48;  // 'H'
                    uart_state <= 1;
                    timeout_cnt <= 0;
                end
                else if (sw2_pressed) begin  // State debug
                    debug_char <= 8'h30 + state;  // '0' + state
                    uart_state <= 1;
                end
                else if (write_started) begin
                    debug_char <= 8'h77;  // 'w' lowercase = started
                    uart_state <= 1;
                end
                else if (write_done) begin
                    debug_char <= 8'h57;  // 'W' uppercase = done
                    uart_state <= 1;
                end
                else if (read_started) begin
                    debug_char <= 8'h72;  // 'r' lowercase = started
                    uart_state <= 1;
                end
                else if (read_done) begin
                    debug_char <= 8'h52;  // 'R' uppercase = done
                    uart_state <= 1;
                end
            end
            
            1: begin  // Send character
                if (!uart_busy) begin
                    uart_data <= debug_char;
                    uart_send <= 1;
                    uart_state <= 2;
                end
            end
            
            2: begin  // Wait for send
                uart_send <= 0;
                if (!uart_busy) begin
                    uart_state <= 3;
                end
            end
            
            3: begin  // Send newline
                if (!uart_busy) begin
                    uart_data <= 8'h0A;  // LF only for simplicity
                    uart_send <= 1;
                    uart_state <= 4;
                end
            end
            
            4: begin  // Final wait
                uart_send <= 0;
                if (!uart_busy) begin
                    uart_state <= 0;
                end
            end
            
            default: uart_state <= 0;
        endcase
    end
    
    // Output assignments
    assign ddr3_reset_n = reset_n;
    assign ddr3_cke = cke;
    assign ddr3_cs_n = cs_n;
    assign ddr3_ras_n = ras_n;
    assign ddr3_cas_n = cas_n;
    assign ddr3_we_n = we_n;
    assign ddr3_addr = addr;
    assign ddr3_ba = ba;
    assign ddr3_odt = odt;
    assign ddr3_dm = dm;
    
    // Bidirectional data
    assign ddr3_dq = dq_oe ? dq_out : 16'bz;
    assign ddr3_dqs_p = dqs_oe ? {2{dqs_out[0]}} : 2'bz;
    assign ddr3_dqs_n = dqs_oe ? {2{~dqs_out[0]}} : 2'bz;
    
    // UART instance
    uart_tx #(.CLKS_PER_BIT(868)) uart_tx_inst (
        .clk(CLK100MHZ),
        .rst(1'b0),
        .tx_start(uart_send),
        .tx_data(uart_data),
        .tx_serial(uart_txd_in),
        .tx_busy(uart_busy),
        .tx_done(uart_done)
    );
    
    // DDR3 commands
    task nop;
        begin
            cs_n <= 0;
            ras_n <= 1;
            cas_n <= 1;
            we_n <= 1;
        end
    endtask
    
    task deselect;
        begin
            cs_n <= 1;
            ras_n <= 1;
            cas_n <= 1;
            we_n <= 1;
        end
    endtask
    
    task precharge_all;
        begin
            cs_n <= 0;
            ras_n <= 0;
            cas_n <= 1;
            we_n <= 0;
            addr[10] <= 1;
        end
    endtask
    
    task load_mode(input [2:0] mr, input [13:0] value);
        begin
            cs_n <= 0;
            ras_n <= 0;
            cas_n <= 0;
            we_n <= 0;
            ba <= mr;
            addr <= value;
        end
    endtask
    
    task activate(input [2:0] bank, input [13:0] row);
        begin
            cs_n <= 0;
            ras_n <= 0;
            cas_n <= 1;
            we_n <= 1;
            ba <= bank;
            addr <= row;
        end
    endtask
    
    task write_cmd(input [2:0] bank, input [9:0] col);
        begin
            cs_n <= 0;
            ras_n <= 1;
            cas_n <= 0;
            we_n <= 0;
            ba <= bank;
            addr[9:0] <= col;
            addr[10] <= 0;
        end
    endtask
    
    task read_cmd(input [2:0] bank, input [9:0] col);
        begin
            cs_n <= 0;
            ras_n <= 1;
            cas_n <= 0;
            we_n <= 1;
            ba <= bank;
            addr[9:0] <= col;
            addr[10] <= 0;
        end
    endtask
    
    // Main DDR3 state machine - run at DDR clock
    always @(posedge clk_ddr) begin
        delay_cnt <= delay_cnt + 1;
        
        // Clear pulse signals
        if (write_started_ddr) write_started_ddr <= 0;
        if (read_started_ddr) read_started_ddr <= 0;
        if (write_done_ddr) write_done_ddr <= 0;
        if (read_done_ddr) read_done_ddr <= 0;
        
        case (state)
            RESET: begin
                reset_n <= 0;
                cke <= 0;
                deselect();
                if (delay_cnt > 20'd100000) begin
                    reset_n <= 1;
                    state <= INIT_NOP;
                    delay_cnt <= 0;
                end
            end
            
            INIT_NOP: begin
                cke <= 1;
                deselect();
                if (delay_cnt > 20'd80000) begin
                    state <= INIT_MRS2;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS2: begin
                if (delay_cnt == 0) begin
                    load_mode(3'd2, 14'b00000000001000);  // CWL=6
                end
                else if (delay_cnt > 4) begin
                    state <= INIT_MRS3;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS3: begin
                if (delay_cnt == 0) begin
                    load_mode(3'd3, 14'b0);
                end
                else if (delay_cnt > 4) begin
                    state <= INIT_MRS1;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS1: begin
                if (delay_cnt == 0) begin
                    load_mode(3'd1, 14'b00000001000000);  // ODT=RZQ/6
                end
                else if (delay_cnt > 4) begin
                    state <= INIT_MRS0;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS0: begin
                if (delay_cnt == 0) begin
                    load_mode(3'd0, 14'b00010100110000);  // CL=9, BL=8
                end
                else if (delay_cnt > 4) begin
                    state <= INIT_ZQCL;
                    delay_cnt <= 0;
                end
            end
            
            INIT_ZQCL: begin
                if (delay_cnt == 0) begin
                    // ZQCL command
                    cs_n <= 0;
                    ras_n <= 1;
                    cas_n <= 1;
                    we_n <= 0;
                    addr[10] <= 1;
                end
                else if (delay_cnt > 512) begin
                    state <= IDLE;
                    delay_cnt <= 0;
                end
            end
            
            IDLE: begin
                deselect();
                odt <= 0;
                dq_oe <= 0;
                dqs_oe <= 0;
                cmd_valid <= 0;
                
                // Check for new commands - synchronized switch signals
                if (sw_sync[0] && !cmd_valid) begin
                    cmd_valid <= 1;
                    cmd_write <= 1;
                    cmd_addr <= 27'h0000100;
                    cmd_data <= 16'hA5A5 + {12'h0, pattern_cnt};
                    last_write_data <= 16'hA5A5 + {12'h0, pattern_cnt};
                    pattern_cnt <= pattern_cnt + 1;
                    state <= ACTIVATE;
                    delay_cnt <= 0;
                end
                else if (sw_sync[1] && !cmd_valid) begin
                    cmd_valid <= 1;
                    cmd_write <= 0;
                    cmd_addr <= 27'h0000100;
                    state <= ACTIVATE;
                    delay_cnt <= 0;
                end
            end
            
            ACTIVATE: begin
                if (delay_cnt == 0) begin
                    activate(cmd_addr[26:24], cmd_addr[23:10]);
                end
                else if (delay_cnt > 3) begin  // tRCD minimum
                    state <= cmd_write ? WRITE : READ;
                    delay_cnt <= 0;
                end
            end
            
            WRITE: begin
                if (delay_cnt == 0) begin
                    write_cmd(cmd_addr[26:24], cmd_addr[9:0]);
                    dq_out <= cmd_data;
                    dq_oe <= 1;
                    dqs_oe <= 1;
                    dm <= 2'b00;
                    write_started_ddr <= 1;  // Pulse
                end
                else if (delay_cnt > 8) begin
                    dq_oe <= 0;
                    dqs_oe <= 0;
                    write_done_ddr <= 1;  // Pulse
                    state <= PRECHARGE;
                    delay_cnt <= 0;
                end
            end
            
            READ: begin
                if (delay_cnt == 0) begin
                    read_cmd(cmd_addr[26:24], cmd_addr[9:0]);
                    odt <= 1;
                    read_started_ddr <= 1;  // Pulse
                end
                else if (delay_cnt == 18) begin  // CL=9
                    captured_read_data <= read_data;
                end
                else if (delay_cnt > 25) begin
                    odt <= 0;
                    read_done_ddr <= 1;  // Pulse
                    state <= PRECHARGE;
                    delay_cnt <= 0;
                end
            end
            
            PRECHARGE: begin
                if (delay_cnt == 0) begin
                    precharge_all();
                end
                else if (delay_cnt > 3) begin  // tRP minimum
                    state <= IDLE;
                    delay_cnt <= 0;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
    
    // LED indicators
    reg [25:0] led_cnt = 0;
    always @(posedge CLK100MHZ) led_cnt <= led_cnt + 1;
    
    assign LED[0] = led_cnt[25];                              // Heartbeat
    assign LED[1] = (state == IDLE);                          // In IDLE
    assign LED[2] = (write_done || read_done);                // Operation complete
    assign LED[3] = (state > INIT_ZQCL);                      // Initialized
    
    // ILA for debugging - monitor key signals
    ila_0 ila_inst (
        .clk(CLK100MHZ),           // 100MHz sampling
        .probe0(state),            // 4 bits - current state
        .probe1(sw_sync),          // 4 bits - switch states
        .probe2(cmd_valid),        // 1 bit  - command valid
        .probe3(cmd_write),        // 1 bit  - write/read
        .probe4(write_done),       // 1 bit  - write complete
        .probe5(read_done),        // 1 bit  - read complete
        .probe6(captured_read_data), // 16 bits - read data
        .probe7(last_write_data),    // 16 bits - write data
        .probe8(delay_cnt[7:0]),     // 8 bits - delay counter LSBs
        .probe9({ddr3_cas_n, ddr3_ras_n, ddr3_we_n, ddr3_cs_n}), // 4 bits - DDR3 commands
        .probe10(dq_oe),           // 1 bit  - data output enable
        .probe11(uart_state)       // 3 bits - UART state
    );

endmodule
