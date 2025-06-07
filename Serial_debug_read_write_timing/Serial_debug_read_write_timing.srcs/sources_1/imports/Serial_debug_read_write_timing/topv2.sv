/* =========================================================================
   UART Debug Project - Version 2 with cleaner TX state machine
   ========================================================================= */
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
//  UART Transmitter
// ---------------------------------------------------------------------------
module uart_tx #(
    parameter int CLK_HZ   = 100_000_000,
    parameter int BAUDRATE = 115200
)(
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       stb_i,
    input  wire [7:0] data_i,
    output reg        tx_o,
    output wire       busy_o
);
    localparam int CLKS_PER_BIT = CLK_HZ / BAUDRATE;
    reg  [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    reg  [3:0]  bit_cnt;
    reg  [9:0]  shift;
    assign busy_o = |bit_cnt;

    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_o <= 1'b1; bit_cnt <= 0; clk_cnt <= 0; shift <= 10'h3FF;
        end else begin
            if (!busy_o && stb_i) begin
                shift <= {1'b1, data_i, 1'b0}; bit_cnt <= 10; clk_cnt <= 0;
            end else if (busy_o) begin
                if (clk_cnt == CLKS_PER_BIT-1) begin
                    clk_cnt <= 0; tx_o <= shift[0];
                    shift <= {1'b1, shift[9:1]}; bit_cnt <= bit_cnt-1;
                end else clk_cnt <= clk_cnt+1;
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
//  UART Receiver
// ---------------------------------------------------------------------------
module uart_rx #(
    parameter int CLK_HZ   = 100_000_000,
    parameter int BAUDRATE = 115200
)(
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       rx_i,
    output reg        stb_o,
    output reg  [7:0] data_o
);
    localparam int CLKS_PER_BIT = CLK_HZ / BAUDRATE;
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg  [1:0] state;
    reg  [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    reg  [2:0] bit_idx;
    reg  [7:0] rx_shift;

    reg rx_d1, rx_d2;
    always @(posedge clk_i) begin rx_d1<=rx_i; rx_d2<=rx_d1; end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state<=IDLE; stb_o<=0; clk_cnt<=0; bit_idx<=0;
        end else begin
            stb_o <= 0;
            case (state)
                IDLE : if (!rx_d2) state<=START;
                START: if (clk_cnt==(CLKS_PER_BIT-1)/2) begin
                           clk_cnt<=0; 
                           if (!rx_d2) state<=DATA;
                           else state<=IDLE;
                       end else clk_cnt<=clk_cnt+1;
                DATA : if (clk_cnt==CLKS_PER_BIT-1) begin
                           clk_cnt<=0; rx_shift[bit_idx]<=rx_d2; bit_idx<=bit_idx+1;
                           if (bit_idx==3'd7) begin bit_idx<=0; state<=STOP; end
                       end else clk_cnt<=clk_cnt+1;
                STOP : if (clk_cnt==CLKS_PER_BIT-1) begin
                           clk_cnt<=0; stb_o<=1; data_o<=rx_shift; state<=IDLE;
                       end else clk_cnt<=clk_cnt+1;
            endcase
        end
    end
endmodule

// ---------------------------------------------------------------------------
//  UART Debug Command Processor - V2
// ---------------------------------------------------------------------------
module uart_debug #(
    parameter int CLK_HZ   = 100_000_000,
    parameter int BAUDRATE = 115200
)(
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rx_i,
    output wire        tx_o,
    output reg  [3:0]  debug_leds_o
);

// ---- RX/TX instances
wire rx_stb; 
wire [7:0] rx_data; 
reg tx_stb; 
reg [7:0] tx_data; 
wire tx_busy;

uart_rx #(.CLK_HZ(CLK_HZ), .BAUDRATE(BAUDRATE)) U_RX (
    .clk_i(clk_i), .rst_i(rst_i), .rx_i(rx_i),
    .stb_o(rx_stb), .data_o(rx_data)
);

uart_tx #(.CLK_HZ(CLK_HZ), .BAUDRATE(BAUDRATE)) U_TX (
    .clk_i(clk_i), .rst_i(rst_i), .stb_i(tx_stb),
    .data_i(tx_data), .tx_o(tx_o), .busy_o(tx_busy)
);

// ---- helpers
function [3:0] hex2n(input [7:0] c);
    hex2n = (c>="0"&&c<="9") ? c-"0" :
            (c>="a"&&c<="f") ? c-"a"+4'd10 :
            (c>="A"&&c<="F") ? c-"A"+4'd10 : 4'd0;
endfunction

function [7:0] n2h(input [3:0] n); 
    n2h = (n<10) ? (n+"0") : (n-10+"a"); 
endfunction

wire is_hex = (rx_data>="0"&&rx_data<="9")||(rx_data>="a"&&rx_data<="f")||
              (rx_data>="A"&&rx_data<="F");

// ---- Command Parser FSM
localparam P_IDLE=2'd0, P_ADR=2'd1, P_DAT=2'd2, P_TIM=2'd3;
reg [1:0] p_state; 
reg [63:0] shift; 
reg [3:0] nib_cnt;
reg [31:0] timing_cfg = 32'h01020304;
reg [31:0] cmd_addr = 32'h00000000;
reg [31:0] cmd_data = 32'h00000000;
reg cmd_is_write = 0;

// Command ready flags (single cycle pulses)
reg cmd_status_rdy = 0;
reg cmd_read_rdy = 0;
reg cmd_write_rdy = 0;
reg cmd_time_rdy = 0;
reg cmd_get_time_rdy = 0;

always @(posedge clk_i) begin
    if (rst_i) begin
        p_state <= P_IDLE; 
        shift <= 0; 
        nib_cnt <= 0;
        cmd_status_rdy <= 0;
        cmd_read_rdy <= 0;
        cmd_write_rdy <= 0;
        cmd_time_rdy <= 0;
        cmd_get_time_rdy <= 0;
        cmd_is_write <= 0;
    end else begin
        // Clear single-cycle flags
        cmd_status_rdy <= 0;
        cmd_read_rdy <= 0;
        cmd_write_rdy <= 0;
        cmd_time_rdy <= 0;
        cmd_get_time_rdy <= 0;
        
        if (rx_stb) begin
            case (p_state)
                P_IDLE: begin
                    shift <= 0; 
                    nib_cnt <= 0;
                    if (rx_data == "?") cmd_status_rdy <= 1;
                    else if (rx_data == "t") cmd_get_time_rdy <= 1;
                    else if (rx_data == "W" || rx_data == "w") begin
                        p_state <= P_ADR;
                        cmd_is_write <= 1;
                    end
                    else if (rx_data == "R" || rx_data == "r") begin
                        p_state <= P_ADR;
                        cmd_is_write <= 0;
                    end
                    else if (rx_data == "T") p_state <= P_TIM;
                end
                
                P_ADR: begin
                    if (is_hex) begin 
                        shift <= {shift[59:0], hex2n(rx_data)}; 
                        nib_cnt <= nib_cnt + 1; 
                    end
                    else if (rx_data == " " && nib_cnt != 0 && cmd_is_write) begin 
                        cmd_addr <= shift[31:0];
                        shift <= 0; 
                        nib_cnt <= 0; 
                        p_state <= P_DAT; 
                    end
                    else if (rx_data == 8'h0d || rx_data == 8'h0a) begin
                        if (nib_cnt != 0) begin
                            cmd_addr <= shift[31:0];
                            if (!cmd_is_write) cmd_read_rdy <= 1;
                        end
                        p_state <= P_IDLE;
                    end
                end
                
                P_DAT: begin
                    if (is_hex) begin 
                        shift <= {shift[59:0], hex2n(rx_data)}; 
                        nib_cnt <= nib_cnt + 1; 
                    end
                    else if (rx_data == 8'h0d || rx_data == 8'h0a) begin 
                        if (nib_cnt != 0) begin
                            cmd_data <= shift[31:0];
                            cmd_write_rdy <= 1;
                        end
                        p_state <= P_IDLE; 
                    end
                end
                
                P_TIM: begin
                    if (is_hex) begin 
                        shift <= {shift[59:0], hex2n(rx_data)}; 
                        nib_cnt <= nib_cnt + 1; 
                    end
                    else if (rx_data == 8'h0d || rx_data == 8'h0a) begin
                        if (nib_cnt >= 8) begin
                            timing_cfg <= shift[31:0];
                        end
                        cmd_time_rdy <= 1;
                        p_state <= P_IDLE;
                    end
                end
            endcase
        end
    end
end

// ---- TX Response FSM
localparam TX_IDLE = 3'd0, TX_STATUS = 3'd1, TX_READ = 3'd2, 
           TX_WRITE = 3'd3, TX_TIME = 3'd4;
reg [2:0] tx_state = TX_IDLE;
reg [4:0] tx_cnt = 0;
reg tx_busy_d = 0;

always @(posedge clk_i) begin
    if (rst_i) begin 
        tx_state <= TX_IDLE;
        tx_stb <= 0; 
        tx_data <= 0; 
        tx_cnt <= 0;
        tx_busy_d <= 0;
    end else begin
        tx_busy_d <= tx_busy;
        tx_stb <= 0;
        
        case (tx_state)
            TX_IDLE: begin
                tx_cnt <= 0;
                if (cmd_status_rdy) tx_state <= TX_STATUS;
                else if (cmd_read_rdy) tx_state <= TX_READ;
                else if (cmd_write_rdy) tx_state <= TX_WRITE;
                else if (cmd_time_rdy || cmd_get_time_rdy) tx_state <= TX_TIME;
            end
            
            TX_STATUS: begin
                if (!tx_busy && !tx_stb) begin
                    case (tx_cnt)
                        0: begin tx_data <= "R"; tx_stb <= 1; tx_cnt <= 1; end
                        1: begin tx_data <= 8'h0A; tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_READ: begin
                if (!tx_busy && !tx_stb) begin
                    case (tx_cnt)
                        0: begin tx_data <= n2h(cmd_addr[31:28]); tx_stb <= 1; tx_cnt <= 1; end
                        1: begin tx_data <= n2h(cmd_addr[27:24]); tx_stb <= 1; tx_cnt <= 2; end
                        2: begin tx_data <= n2h(cmd_addr[23:20]); tx_stb <= 1; tx_cnt <= 3; end
                        3: begin tx_data <= n2h(cmd_addr[19:16]); tx_stb <= 1; tx_cnt <= 4; end
                        4: begin tx_data <= n2h(cmd_addr[15:12]); tx_stb <= 1; tx_cnt <= 5; end
                        5: begin tx_data <= n2h(cmd_addr[11:8]);  tx_stb <= 1; tx_cnt <= 6; end
                        6: begin tx_data <= n2h(cmd_addr[7:4]);   tx_stb <= 1; tx_cnt <= 7; end
                        7: begin tx_data <= n2h(cmd_addr[3:0]);   tx_stb <= 1; tx_cnt <= 8; end
                        8: begin tx_data <= 8'h0A; tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_WRITE: begin
                if (!tx_busy && !tx_stb) begin
                    case (tx_cnt)
                        0: begin tx_data <= "O"; tx_stb <= 1; tx_cnt <= 1; end
                        1: begin tx_data <= "K"; tx_stb <= 1; tx_cnt <= 2; end
                        2: begin tx_data <= 8'h0A; tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_TIME: begin
                if (!tx_busy && !tx_stb) begin
                    case (tx_cnt)
                        0: begin tx_data <= "T"; tx_stb <= 1; tx_cnt <= 1; end
                        1: begin tx_data <= ":"; tx_stb <= 1; tx_cnt <= 2; end
                        2: begin tx_data <= n2h(timing_cfg[31:28]); tx_stb <= 1; tx_cnt <= 3; end
                        3: begin tx_data <= n2h(timing_cfg[27:24]); tx_stb <= 1; tx_cnt <= 4; end
                        4: begin tx_data <= n2h(timing_cfg[23:20]); tx_stb <= 1; tx_cnt <= 5; end
                        5: begin tx_data <= n2h(timing_cfg[19:16]); tx_stb <= 1; tx_cnt <= 6; end
                        6: begin tx_data <= n2h(timing_cfg[15:12]); tx_stb <= 1; tx_cnt <= 7; end
                        7: begin tx_data <= n2h(timing_cfg[11:8]);  tx_stb <= 1; tx_cnt <= 8; end
                        8: begin tx_data <= n2h(timing_cfg[7:4]);   tx_stb <= 1; tx_cnt <= 9; end
                        9: begin tx_data <= n2h(timing_cfg[3:0]);   tx_stb <= 1; tx_cnt <= 10; end
                        10: begin tx_data <= 8'h0A; tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            default: tx_state <= TX_IDLE;
        endcase
    end
end

// ---- Activity LEDs
reg [22:0] rx_act, tx_act; 
reg [24:0] hb;

always @(posedge clk_i) begin
    if (rst_i) begin 
        rx_act <= 0; 
        tx_act <= 0; 
        hb <= 0; 
    end else begin
        hb <= hb + 1;
        rx_act <= rx_stb ? 23'h7FFFFF : (rx_act ? rx_act-1 : 0);
        tx_act <= tx_stb ? 23'h7FFFFF : (tx_act ? tx_act-1 : 0);
        debug_leds_o <= {p_state != P_IDLE, hb[24], |tx_act, |rx_act};
    end
end

endmodule

// ---------------------------------------------------------------------------
//  Reset generator
// ---------------------------------------------------------------------------
module reset_gen(input wire clk_i, output reg rst_o);
    reg [7:0] cnt=0;
    always @(posedge clk_i) begin
        if (cnt!=8'hFF) begin cnt<=cnt+1; rst_o<=1; end else rst_o<=0;
    end
endmodule

// ---------------------------------------------------------------------------
//  Board top
// ---------------------------------------------------------------------------
module top(
    input  wire clk100mhz,
    input  wire uart_rx_i,
    output wire uart_tx_o,
    output wire [3:0] led
);
    wire rst;
    reset_gen u_rst(.clk_i(clk100mhz), .rst_o(rst));
    uart_debug #(.CLK_HZ(100_000_000), .BAUDRATE(115200)) u_dbg(
        .clk_i(clk100mhz), .rst_i(rst),
        .rx_i(uart_rx_i), .tx_o(uart_tx_o), .debug_leds_o(led)
    );
endmodule