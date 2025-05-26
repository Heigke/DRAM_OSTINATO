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
    reg [26:0]  cmd_addr = 0;  // {bank[2:0], row[13:0], col[9:0]}
    reg [15:0]  cmd_data = 0;
    wire [15:0] read_data = ddr3_dq;
    reg [15:0]  captured_read_data = 0;
    
    // UART signals
    reg         uart_send = 0;
    reg [7:0]   uart_data = 0;
    wire        uart_busy;
    wire        uart_done;
    
    // Simple message system - just send single characters for debugging
    reg [25:0] uart_timer = 0;
    reg startup_msg_sent = 0;
    
    // Switch handling - use simple level detection first
    reg [3:0] sw_sync = 0;
    reg [3:0] sw_prev = 0;
    
    always @(posedge CLK100MHZ) begin
        sw_sync <= sw;
        sw_prev <= sw_sync;
    end
    
    wire sw0_pressed = sw_sync[0] && !sw_prev[0];
    wire sw1_pressed = sw_sync[1] && !sw_prev[1];
    
    // Debug counter for LED blinking
    reg [25:0] debug_cnt = 0;
    always @(posedge CLK100MHZ) begin
        debug_cnt <= debug_cnt + 1;
        uart_timer <= uart_timer + 1;
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
    
    // Simple UART message sender
    reg [2:0] uart_state = 0;
    reg [7:0] msg_to_send = 0;
    reg send_request = 0;
    
    always @(posedge CLK100MHZ) begin
        case (uart_state)
            0: begin  // Idle
                uart_send <= 0;
                if (send_request) begin
                    uart_data <= msg_to_send;
                    uart_send <= 1;
                    uart_state <= 1;
                    send_request <= 0;
                end
            end
            1: begin  // Sending
                uart_send <= 0;
                if (uart_done) begin
                    uart_state <= 0;
                end
            end
        endcase
        
        // Send startup message
        if (!startup_msg_sent && uart_timer > 26'd50000000) begin  // 0.5 seconds after startup
            msg_to_send <= 8'h52;  // 'R' for Ready
            send_request <= 1;
            startup_msg_sent <= 1;
        end
        
        // Send debug messages for switch presses
        if (sw0_pressed && uart_state == 0) begin
            msg_to_send <= 8'h57;  // 'W' for Write
            send_request <= 1;
        end
        
        if (sw1_pressed && uart_state == 0) begin
            msg_to_send <= 8'h52;  // 'R' for Read  
            send_request <= 1;
        end
    end
    
    // DDR3 commands
    task nop;
        begin
            cs_n <= 0;
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
            addr[10] <= 1;  // All banks
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
            addr[10] <= 0;  // No auto-precharge
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
            addr[10] <= 0;  // No auto-precharge
        end
    endtask
    
    // Main state machine - simplified timing
    always @(posedge clk_ddr) begin
        delay_cnt <= delay_cnt + 1;
        
        case (state)
            RESET: begin
                reset_n <= 0;
                cke <= 0;
                nop();
                if (delay_cnt > 20'd50000) begin  // Shorter reset time for debugging
                    reset_n <= 1;
                    state <= INIT_NOP;
                    delay_cnt <= 0;
                end
            end
            
            INIT_NOP: begin
                cke <= 1;
                nop();
                if (delay_cnt > 20'd50000) begin  // Shorter init time
                    state <= INIT_MRS2;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS2: begin
                load_mode(3'd2, 14'b00000000001000);  // CWL=6
                state <= INIT_MRS3;
                delay_cnt <= 0;
            end
            
            INIT_MRS3: begin
                if (delay_cnt > 10) begin
                    load_mode(3'd3, 14'b0);
                    state <= INIT_MRS1;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS1: begin
                if (delay_cnt > 10) begin
                    load_mode(3'd1, 14'b00000001000000);  // ODT=RZQ/6
                    state <= INIT_MRS0;
                    delay_cnt <= 0;
                end
            end
            
            INIT_MRS0: begin
                if (delay_cnt > 10) begin
                    load_mode(3'd0, 14'b00010111010000);  // CL=9, BL=8
                    state <= INIT_ZQCL;
                    delay_cnt <= 0;
                end
            end
            
            INIT_ZQCL: begin
                if (delay_cnt > 200) begin
                    state <= IDLE;
                    delay_cnt <= 0;
                end
            end
            
            IDLE: begin
                nop();
                odt <= 0;
                dq_oe <= 0;
                dqs_oe <= 0;
                
                // Check for switch presses
                if (sw0_pressed && !cmd_valid) begin
                    cmd_valid <= 1;
                    cmd_write <= 1;
                    cmd_addr <= 27'h0000100;  // Bank 0, Row 0, Col 256
                    cmd_data <= 16'hA5A5;
                    state <= ACTIVATE;
                    delay_cnt <= 0;
                end
                else if (sw1_pressed && !cmd_valid) begin
                    cmd_valid <= 1;
                    cmd_write <= 0;
                    cmd_addr <= 27'h0000100;  // Same address
                    state <= ACTIVATE;
                    delay_cnt <= 0;
                end
            end
            
            ACTIVATE: begin
                activate(cmd_addr[26:24], cmd_addr[23:10]);
                if (delay_cnt > 0) begin  // Immediate transition for debugging
                    state <= cmd_write ? WRITE : READ;
                    delay_cnt <= 0;
                end
            end
            
            WRITE: begin
                if (delay_cnt == 4) begin  // tRCD
                    write_cmd(cmd_addr[26:24], cmd_addr[9:0]);
                    dq_out <= cmd_data;
                    dq_oe <= 1;
                    dqs_out <= 0;
                    dqs_oe <= 1;
                    dm <= 2'b00;
                end
                else if (delay_cnt > 10) begin
                    dq_oe <= 0;
                    dqs_oe <= 0;
                    state <= PRECHARGE;
                    delay_cnt <= 0;
                end
            end
            
            READ: begin
                if (delay_cnt == 4) begin  // tRCD
                    read_cmd(cmd_addr[26:24], cmd_addr[9:0]);
                    odt <= 1;
                end
                else if (delay_cnt == 15) begin  // Capture read data
                    captured_read_data <= read_data;
                end
                else if (delay_cnt > 20) begin  // CL + margin
                    odt <= 0;
                    state <= PRECHARGE;
                    delay_cnt <= 0;
                end
            end
            
            PRECHARGE: begin
                precharge_all();
                if (delay_cnt > 10) begin
                    cmd_valid <= 0;
                    state <= IDLE;
                    delay_cnt <= 0;
                end
            end
        endcase
    end
    
    // LED indicators - detailed debugging
    assign LED[0] = (state == IDLE) ? debug_cnt[24] : 1'b0;  // Blink when idle
    assign LED[1] = (state == WRITE) || (state == READ);     // On during operations  
    assign LED[2] = sw_sync[0] || sw_sync[1];                // Mirror switch state
    assign LED[3] = reset_n;                                 // DDR3 reset released

endmodule
