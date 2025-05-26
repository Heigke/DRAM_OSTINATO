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
    
    // UART signals
    reg         uart_send = 0;
    reg [7:0]   uart_data = 0;
    wire        uart_busy;
    wire        uart_done;
    
    // Debug message queue
    reg [7:0]   debug_msg = 0;  // Simple debug byte to send
    reg         send_debug = 0;
    
    // Heartbeat counter - send periodic message to verify UART works
    reg [26:0]  heartbeat_cnt = 0;
    
    // Switch handling
    reg [3:0] sw_sync = 0;
    reg [3:0] sw_prev = 0;
    
    always @(posedge CLK100MHZ) begin
        sw_sync <= sw;
        sw_prev <= sw_sync;
    end
    
    wire sw0_pressed = sw_sync[0] && !sw_prev[0];
    wire sw1_pressed = sw_sync[1] && !sw_prev[1];
    wire sw2_pressed = sw_sync[2] && !sw_prev[2];  // Debug switch
    wire sw3_pressed = sw_sync[3] && !sw_prev[3];  // Force UART test
    
    // Test pattern counter
    reg [3:0] pattern_cnt = 0;
    
    // Simple UART sender state machine
    reg [2:0] uart_state = 0;
    
    always @(posedge CLK100MHZ) begin
        heartbeat_cnt <= heartbeat_cnt + 1;
        
        case (uart_state)
            0: begin  // Idle
                uart_send <= 0;
                
                // Priority system for what to send
                if (sw3_pressed || (heartbeat_cnt == 27'd100000000)) begin  // 1 second heartbeat or SW3
                    debug_msg <= 8'h48;  // 'H' for heartbeat
                    send_debug <= 1;
                    uart_state <= 1;
                    heartbeat_cnt <= 0;
                end
                else if (sw2_pressed) begin  // Send current state
                    debug_msg <= 8'h30 + state;  // '0' + state number
                    send_debug <= 1;
                    uart_state <= 1;
                end
                else if (sw0_pressed && state == IDLE) begin
                    debug_msg <= 8'h57;  // 'W' for write
                    send_debug <= 1;
                    uart_state <= 1;
                end
                else if (sw1_pressed && state == IDLE) begin
                    debug_msg <= 8'h52;  // 'R' for read
                    send_debug <= 1;
                    uart_state <= 1;
                end
                else if (state == IDLE && heartbeat_cnt[26:24] == 3'b111) begin  // Reached idle
                    debug_msg <= 8'h49;  // 'I' for idle
                    send_debug <= 1;
                    uart_state <= 1;
                    heartbeat_cnt <= 0;
                end
            end
            
            1: begin  // Send byte
                if (!uart_busy) begin
                    uart_data <= debug_msg;
                    uart_send <= 1;
                    uart_state <= 2;
                    send_debug <= 0;
                end
            end
            
            2: begin  // Wait for send
                uart_send <= 0;
                if (!uart_busy) begin
                    uart_state <= 3;
                end
            end
            
            3: begin  // Send CR
                if (!uart_busy) begin
                    uart_data <= 8'h0D;
                    uart_send <= 1;
                    uart_state <= 4;
                end
            end
            
            4: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) begin
                    uart_state <= 5;
                end
            end
            
            5: begin  // Send LF
                if (!uart_busy) begin
                    uart_data <= 8'h0A;
                    uart_send <= 1;
                    uart_state <= 6;
                end
            end
            
            6: begin  // Final wait
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
    
    // Main DDR3 state machine - simplified timing
    always @(posedge clk_ddr) begin
        delay_cnt <= delay_cnt + 1;
        
        case (state)
            RESET: begin
                reset_n <= 0;
                cke <= 0;
                nop();
                if (delay_cnt > 20'd50000) begin  // 250us at 200MHz
                    reset_n <= 1;
                    state <= INIT_NOP;
                    delay_cnt <= 0;
                end
            end
            
            INIT_NOP: begin
                cke <= 1;
                nop();
                if (delay_cnt > 20'd50000) begin  // 250us
                    state <= IDLE;  // Skip MRS for now to test basic functionality
                    delay_cnt <= 0;
                end
            end
            
            IDLE: begin
                nop();
                odt <= 0;
                dq_oe <= 0;
                dqs_oe <= 0;
                
                // Simple test - just try to read/write without full init
                if (sw0_pressed && !cmd_valid) begin
                    cmd_valid <= 1;
                    cmd_write <= 1;
                    cmd_data <= 16'hA5A5;
                    last_write_data <= 16'hA5A5;
                    state <= WRITE;  // Skip activate for now
                    delay_cnt <= 0;
                end
                else if (sw1_pressed && !cmd_valid) begin
                    cmd_valid <= 1;
                    cmd_write <= 0;
                    state <= READ;  // Skip activate for now
                    delay_cnt <= 0;
                end
            end
            
            WRITE: begin
                if (delay_cnt == 1) begin
                    write_cmd(3'b000, 10'h100);
                    dq_out <= cmd_data;
                    dq_oe <= 1;
                    dm <= 2'b00;
                end
                else if (delay_cnt > 10) begin
                    dq_oe <= 0;
                    cmd_valid <= 0;
                    state <= IDLE;
                    delay_cnt <= 0;
                end
            end
            
            READ: begin
                if (delay_cnt == 1) begin
                    read_cmd(3'b000, 10'h100);
                end
                else if (delay_cnt == 15) begin
                    captured_read_data <= read_data;
                end
                else if (delay_cnt > 20) begin
                    cmd_valid <= 0;
                    state <= IDLE;
                    delay_cnt <= 0;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
    
    // LED indicators - show state and activity
    assign LED[0] = heartbeat_cnt[25];           // Heartbeat blink
    assign LED[1] = (state == IDLE);             // IDLE indicator
    assign LED[2] = uart_busy;                   // UART activity
    assign LED[3] = (state > INIT_NOP);          // Past init

endmodule
