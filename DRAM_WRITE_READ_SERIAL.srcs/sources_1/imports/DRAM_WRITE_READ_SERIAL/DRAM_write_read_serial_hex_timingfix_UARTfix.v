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
    
    // Operation complete flags
    reg write_done = 0;
    reg read_done = 0;
    
    // UART signals
    reg         uart_send = 0;
    reg [7:0]   uart_data = 0;
    wire        uart_busy;
    wire        uart_done;
    
    // Switch handling
    reg [3:0] sw_sync = 0;
    reg [3:0] sw_prev = 0;
    
    always @(posedge CLK100MHZ) begin
        sw_sync <= sw;
        sw_prev <= sw_sync;
    end
    
    wire sw0_pressed = sw_sync[0] && !sw_prev[0];
    wire sw1_pressed = sw_sync[1] && !sw_prev[1];
    wire sw2_pressed = sw_sync[2] && !sw_prev[2];
    
    // Test pattern counter
    reg [3:0] pattern_cnt = 0;
    
    // UART hex output state machine
    reg [3:0] hex_state = 0;
    reg [15:0] hex_value = 0;
    reg hex_is_write = 0;
    
    // Function to convert 4-bit hex to ASCII
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 10)
                hex_to_ascii = 8'h30 + hex;  // '0'-'9'
            else
                hex_to_ascii = 8'h41 + (hex - 10);  // 'A'-'F'
        end
    endfunction
    
    // UART output handler
    always @(posedge CLK100MHZ) begin
        case (hex_state)
            0: begin  // Idle, check for data to send
                uart_send <= 0;
                write_done <= 0;
                read_done <= 0;
                
                if (sw2_pressed) begin  // Debug state
                    hex_value <= {12'h000, state};
                    hex_is_write <= 0;
                    hex_state <= 1;
                end
                else if (write_done) begin
                    hex_value <= last_write_data;
                    hex_is_write <= 1;
                    hex_state <= 1;
                end
                else if (read_done) begin
                    hex_value <= captured_read_data;
                    hex_is_write <= 0;
                    hex_state <= 1;
                end
            end
            
            1: begin  // Send 'W' or 'R'
                if (!uart_busy) begin
                    uart_data <= hex_is_write ? 8'h57 : 8'h52;  // 'W' or 'R'
                    uart_send <= 1;
                    hex_state <= 2;
                end
            end
            
            2: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 3;
            end
            
            3: begin  // Send ':'
                if (!uart_busy) begin
                    uart_data <= 8'h3A;  // ':'
                    uart_send <= 1;
                    hex_state <= 4;
                end
            end
            
            4: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 5;
            end
            
            5: begin  // Send hex[15:12]
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value[15:12]);
                    uart_send <= 1;
                    hex_state <= 6;
                end
            end
            
            6: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 7;
            end
            
            7: begin  // Send hex[11:8]
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value[11:8]);
                    uart_send <= 1;
                    hex_state <= 8;
                end
            end
            
            8: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 9;
            end
            
            9: begin  // Send hex[7:4]
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value[7:4]);
                    uart_send <= 1;
                    hex_state <= 10;
                end
            end
            
            10: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 11;
            end
            
            11: begin  // Send hex[3:0]
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value[3:0]);
                    uart_send <= 1;
                    hex_state <= 12;
                end
            end
            
            12: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 13;
            end
            
            13: begin  // Send CR
                if (!uart_busy) begin
                    uart_data <= 8'h0D;
                    uart_send <= 1;
                    hex_state <= 14;
                end
            end
            
            14: begin  // Wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 15;
            end
            
            15: begin  // Send LF
                if (!uart_busy) begin
                    uart_data <= 8'h0A;
                    uart_send <= 1;
                    hex_state <= 16;
                end
            end
            
            16: begin  // Final wait
                uart_send <= 0;
                if (!uart_busy) hex_state <= 0;
            end
            
            default: hex_state <= 0;
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
    
    // Main DDR3 state machine
    always @(posedge clk_ddr) begin
        delay_cnt <= delay_cnt + 1;
        
        case (state)
            RESET: begin
                reset_n <= 0;
                cke <= 0;
                deselect();
                if (delay_cnt > 20'd100000) begin  // 500us
                    reset_n <= 1;
                    state <= INIT_NOP;
                    delay_cnt <= 0;
                end
            end
            
            INIT_NOP: begin
                cke <= 1;
                deselect();
                if (delay_cnt > 20'd80000) begin  // 400us
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
                if (delay_cnt == 4) begin
                    load_mode(3'd3, 14'b0);  // Normal operation
                end
                else if (delay_cnt > 8) begin
                    state <= INIT_MRS1;
                    delay_cnt <= 0;
                end
                else begin
                    deselect();
                end
            end
            
            INIT_MRS1: begin
                if (delay_cnt == 4) begin
                    load_mode(3'd1, 14'b00000001000000);  // ODT=RZQ/6
                end
                else if (delay_cnt > 8) begin
                    state <= INIT_MRS0;
                    delay_cnt <= 0;
                end
                else begin
                    deselect();
                end
            end
            
            INIT_MRS0: begin
                if (delay_cnt == 4) begin
                    load_mode(3'd0, 14'b00010100110000);  // CL=9, BL=8
                end
                else if (delay_cnt > 8) begin
                    state <= INIT_ZQCL;
                    delay_cnt <= 0;
                end
                else begin
                    deselect();
                end
            end
            
            INIT_ZQCL: begin
                if (delay_cnt == 4) begin
                    // ZQCL command
                    cs_n <= 0;
                    ras_n <= 1;
                    cas_n <= 1;
                    we_n <= 0;
                    addr[10] <= 1;
                end
                else if (delay_cnt > 512) begin  // tZQinit
                    state <= IDLE;
                    delay_cnt <= 0;
                end
                else begin
                    nop();
                end
            end
            
            IDLE: begin
                deselect();
                odt <= 0;
                dq_oe <= 0;
                dqs_oe <= 0;
                
                // Process commands only when UART is idle
                if (hex_state == 0) begin
                    if (sw0_pressed && !cmd_valid) begin
                        cmd_valid <= 1;
                        cmd_write <= 1;
                        cmd_addr <= 27'h0000100;  // Bank 0, Row 0, Col 256
                        // Different test patterns
                        case (pattern_cnt)
                            0: cmd_data <= 16'hA5A5;
                            1: cmd_data <= 16'h5A5A;
                            2: cmd_data <= 16'hFFFF;
                            3: cmd_data <= 16'h0000;
                            4: cmd_data <= 16'h1234;
                            5: cmd_data <= 16'hABCD;
                            6: cmd_data <= 16'h5555;
                            7: cmd_data <= 16'hAAAA;
                            default: cmd_data <= 16'hDEAD;
                        endcase
                        last_write_data <= cmd_data;
                        pattern_cnt <= pattern_cnt + 1;
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
            end
            
            ACTIVATE: begin
                if (delay_cnt == 0) begin
                    activate(cmd_addr[26:24], cmd_addr[23:10]);
                end
                else if (delay_cnt > 13) begin  // tRCD=13.75ns @ 200MHz = ~3 cycles
                    state <= cmd_write ? WRITE : READ;
                    delay_cnt <= 0;
                end
                else begin
                    nop();
                end
            end
            
            WRITE: begin
                if (delay_cnt == 0) begin
                    write_cmd(cmd_addr[26:24], cmd_addr[9:0]);
                    dq_out <= cmd_data;
                    dq_oe <= 1;
                    dqs_out <= 2'b01;  // DQS transitions
                    dqs_oe <= 1;
                    dm <= 2'b00;
                end
                else if (delay_cnt == 1) begin
                    dqs_out <= 2'b10;  // DQS toggle
                end
                else if (delay_cnt == 2) begin
                    dqs_out <= 2'b01;  // DQS toggle
                end
                else if (delay_cnt == 3) begin
                    dqs_out <= 2'b10;  // DQS toggle
                end
                else if (delay_cnt > 8) begin
                    dq_oe <= 0;
                    dqs_oe <= 0;
                    write_done <= 1;  // Signal write complete
                    state <= PRECHARGE;
                    delay_cnt <= 0;
                end
                else begin
                    nop();
                end
            end
            
            READ: begin
                if (delay_cnt == 0) begin
                    read_cmd(cmd_addr[26:24], cmd_addr[9:0]);
                    odt <= 1;
                end
                else if (delay_cnt == 18) begin  // CL=9 @ 200MHz
                    captured_read_data <= read_data;
                end
                else if (delay_cnt > 25) begin
                    odt <= 0;
                    read_done <= 1;  // Signal read complete
                    state <= PRECHARGE;
                    delay_cnt <= 0;
                end
                else begin
                    nop();
                end
            end
            
            PRECHARGE: begin
                if (delay_cnt == 0) begin
                    precharge_all();
                end
                else if (delay_cnt > 13) begin  // tRP
                    cmd_valid <= 0;
                    state <= IDLE;
                    delay_cnt <= 0;
                end
                else begin
                    nop();
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
    assign LED[2] = (captured_read_data == last_write_data);  // Data match
    assign LED[3] = (state > INIT_ZQCL);                      // Initialized

endmodule
