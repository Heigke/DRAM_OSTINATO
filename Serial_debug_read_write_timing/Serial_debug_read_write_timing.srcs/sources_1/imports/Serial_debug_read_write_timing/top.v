//==========================================================================
//  UART Debug Project - FULL, FIXED EDITION
//  • All commands now return their complete strings
//  • send_* flags stay high until the final byte's stop bit has shifted out
//  Baud-rate: 115 200, 8-N-1
//  RX  pin  A9  (PC → FPGA)
//  TX  pin  D10 (FPGA → PC)
//==========================================================================

`timescale 1ns/1ps

//==========================================================================
//  UART Transmitter
//==========================================================================
module uart_tx #(
    parameter int CLK_HZ   = 100_000_000,
    parameter int BAUDRATE = 115_200
)(
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       stb_i,
    input  wire [7:0] data_i,
    output reg        tx_o,
    output wire       busy_o
);
    localparam int CLKS_PER_BIT = CLK_HZ / BAUDRATE;  // 100 MHz / 115 200 ≈ 868

    reg  [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    reg  [3:0]  bit_cnt;
    reg  [9:0]  shift;

    assign busy_o = |bit_cnt;

    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_o    <= 1'b1;                     // idle
            bit_cnt <= 0;
            clk_cnt <= 0;
            shift   <= 10'h3FF;
        end else begin
            //----------------------------------
            //  kick off a new byte
            //----------------------------------
            if (!busy_o && stb_i) begin
                shift   <= {1'b1 /*stop*/, data_i, 1'b0 /*start*/};
                bit_cnt <= 10;
                clk_cnt <= 0;
            //----------------------------------
            //  shift while busy
            //----------------------------------
            end else if (busy_o) begin
                if (clk_cnt == CLKS_PER_BIT-1) begin
                    clk_cnt <= 0;
                    tx_o    <= shift[0];
                    shift   <= {1'b1, shift[9:1]};
                    bit_cnt <= bit_cnt - 1;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end
        end
    end
endmodule

//==========================================================================
//  UART Receiver
//==========================================================================
module uart_rx #(
    parameter int CLK_HZ   = 100_000_000,
    parameter int BAUDRATE = 115_200
)(
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       rx_i,
    output reg        stb_o,
    output reg  [7:0] data_o
);
    localparam int CLKS_PER_BIT = CLK_HZ / BAUDRATE;

    // FSM states
    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg  [1:0] state;
    reg  [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    reg  [2:0] bit_idx;
    reg  [7:0] rx_shift;

    // double-sync external RX
    reg rx_d1, rx_d2;
    always @(posedge clk_i) begin
        rx_d1 <= rx_i;
        rx_d2 <= rx_d1;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state   <= IDLE;
            stb_o   <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            stb_o <= 0;                    // default
            case (state)
                //----------------------------------------------------------
                IDLE:  if (!rx_d2)  state <= START;
                //----------------------------------------------------------
                START: begin
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin // mid-start
                        clk_cnt <= 0;
                        state   <= DATA;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                //----------------------------------------------------------
                DATA:  begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt               <= 0;
                        rx_shift[bit_idx]     <= rx_d2;
                        bit_idx               <= bit_idx + 1;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                //----------------------------------------------------------
                STOP:  begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        stb_o  <= 1;
                        data_o <= rx_shift;
                        clk_cnt<= 0;
                        state  <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule

//==========================================================================
//  UART Debug Command Processor
//==========================================================================
module uart_debug #(
    parameter int CLK_HZ   = 100_000_000,
    parameter int BAUDRATE = 115_200
)(
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rx_i,
    output wire        tx_o,
    output reg  [3:0]  debug_leds_o
);
//--------------------------------------------------
//  Instantiate RX/TX
//--------------------------------------------------
wire rx_stb;
wire [7:0] rx_data;
reg  tx_stb;
reg  [7:0] tx_data;
wire tx_busy;

uart_rx #(.CLK_HZ(CLK_HZ), .BAUDRATE(BAUDRATE)) U_RX
(
    .clk_i(clk_i), .rst_i(rst_i),
    .rx_i(rx_i),   .stb_o(rx_stb), .data_o(rx_data)
);

uart_tx #(.CLK_HZ(CLK_HZ), .BAUDRATE(BAUDRATE)) U_TX
(
    .clk_i(clk_i), .rst_i(rst_i),
    .stb_i(tx_stb), .data_i(tx_data),
    .tx_o(tx_o),  .busy_o(tx_busy)
);

//--------------------------------------------------
//  Helpers
//--------------------------------------------------
function [3:0] hex2n (input [7:0] c);
    hex2n = (c>="0"&&c<="9") ? c-"0" :
            (c>="a"&&c<="f") ? c-"a"+4'd10 :
            (c>="A"&&c<="F") ? c-"A"+4'd10 : 4'd0;
endfunction

function [7:0] n2h (input [3:0] n);
    n2h = (n<10) ? (n+"0") : (n-10+"a");
endfunction

wire is_hex = (rx_data>="0"&&rx_data<="9")||
              (rx_data>="a"&&rx_data<="f")||
              (rx_data>="A"&&rx_data<="F");

//--------------------------------------------------
//  Parser FSM
//--------------------------------------------------
localparam P_IDLE   = 3'd0,
           P_GETADR = 3'd1,
           P_GETDAT = 3'd2,
           P_GETTIM = 3'd3;

reg  [2:0]  p_state;
reg  [63:0] shift;
reg  [3:0]  nib_cnt;
reg         cmd_is_write, cmd_is_timing;
reg  [31:0] last_write_addr, last_write_data, last_read_addr;
reg  [31:0] timing_config;

// response-request flags
reg send_status, send_read, send_write, send_time;

always @(posedge clk_i) begin
    if (rst_i) begin
        p_state            <= P_IDLE;
        shift              <= 0;
        nib_cnt            <= 0;
        cmd_is_write       <= 0;
        cmd_is_timing      <= 0;
        last_write_addr    <= 0;
        last_write_data    <= 0;
        last_read_addr     <= 0;
        timing_config      <= 32'h0102_0304;
        send_status <= 0; send_read <= 0; send_write <= 0; send_time <= 0;
    end else if (rx_stb) begin
        //----------------------------------------------------------
        //  state P_IDLE  - recognise command letters
        //----------------------------------------------------------
        case (p_state)
            P_IDLE: begin
                shift  <= 0;
                nib_cnt<= 0;
                if (rx_data=="?")              send_status <= 1;
                else if (rx_data=="t")         send_time   <= 1;          // query
                else if (rx_data=="W"||rx_data=="w") begin
                    cmd_is_write <= 1; p_state <= P_GETADR;
                end else if (rx_data=="R"||rx_data=="r") begin
                    cmd_is_write <= 0; p_state <= P_GETADR;
                end else if (rx_data=="T") begin
                    cmd_is_timing<= 1; p_state <= P_GETTIM;
                end
            end
        //----------------------------------------------------------
            P_GETADR: begin
                if (is_hex) begin
                    shift   <= {shift[59:0], hex2n(rx_data)};
                    nib_cnt <= nib_cnt + 1;
                end else if (rx_data==" " && cmd_is_write && nib_cnt!=0) begin
                    last_write_addr <= shift[31:0];
                    shift   <= 0; nib_cnt <= 0; p_state <= P_GETDAT;
                end else if ((rx_data==8'h0d)||(rx_data==8'h0a)) begin
                    if (!cmd_is_write) begin
                        last_read_addr <= shift[31:0];
                        send_read <= 1;
                    end
                    p_state <= P_IDLE;
                end
            end
        //----------------------------------------------------------
            P_GETDAT: begin
                if (is_hex) begin
                    shift   <= {shift[59:0], hex2n(rx_data)};
                    nib_cnt <= nib_cnt + 1;
                end else if ((rx_data==8'h0d)||(rx_data==8'h0a)) begin
                    last_write_data <= shift[31:0];
                    send_write <= 1;
                    p_state <= P_IDLE;
                end
            end
        //----------------------------------------------------------
            P_GETTIM: begin
                if (is_hex) begin
                    shift   <= {shift[59:0], hex2n(rx_data)};
                    nib_cnt <= nib_cnt + 1;
                end else if ((rx_data==8'h0d)||(rx_data==8'h0a)) begin
                    if (nib_cnt>=8) timing_config <= shift[31:0];
                    send_time <= 1;
                    p_state <= P_IDLE;
                end
            end
        endcase
    end
end

//======================================================================
//  Transmit-response generator
//  • issues bytes sequentially
//  • clears flag only after final byte completed
//======================================================================
reg [4:0] tx_cnt;        // enough for longest string (11 bytes)
reg       tx_busy_d;     // delayed busy

// last-byte detection: tx_busy_d==1 & tx_busy==0 & tx_cnt==0
wire tx_done_byte =  tx_busy_d & ~tx_busy;
wire tx_done_msg  =  tx_done_byte & (tx_cnt==0);

always @(posedge clk_i) begin
    if (rst_i) begin
        tx_stb <= 0;
        tx_data<= 8'h00;
        tx_cnt <= 0;
        tx_busy_d <= 0;
    end else begin
        tx_busy_d <= tx_busy;
        tx_stb    <= 0;              // default

        //------------------------------------------------------------------
        //  kick out first byte of required response (only when TX idle)
        //------------------------------------------------------------------
        if (!tx_busy) begin
            //-------------------------------- Status  "R\n"
            if (send_status) begin
                case (tx_cnt)
                    0: begin tx_data<="R"; tx_stb<=1; tx_cnt<=1; end
                    1: begin tx_data<=8'h0A; tx_stb<=1; tx_cnt<=0; end
                endcase
            //-------------------------------- Read   "12345678\n"
            end else if (send_read) begin
                case (tx_cnt)
                    0: begin tx_data<="1"; tx_stb<=1; tx_cnt<=1; end
                    1: begin tx_data<="2"; tx_stb<=1; tx_cnt<=2; end
                    2: begin tx_data<="3"; tx_stb<=1; tx_cnt<=3; end
                    3: begin tx_data<="4"; tx_stb<=1; tx_cnt<=4; end
                    4: begin tx_data<="5"; tx_stb<=1; tx_cnt<=5; end
                    5: begin tx_data<="6"; tx_stb<=1; tx_cnt<=6; end
                    6: begin tx_data<="7"; tx_stb<=1; tx_cnt<=7; end
                    7: begin tx_data<="8"; tx_stb<=1; tx_cnt<=8; end
                    8: begin tx_data<=8'h0A; tx_stb<=1; tx_cnt<=0; end
                endcase
            //-------------------------------- Write  "OK\n"
            end else if (send_write) begin
                case (tx_cnt)
                    0: begin tx_data<="O"; tx_stb<=1; tx_cnt<=1; end
                    1: begin tx_data<="K"; tx_stb<=1; tx_cnt<=2; end
                    2: begin tx_data<=8'h0A; tx_stb<=1; tx_cnt<=0; end
                endcase
            //-------------------------------- Timing "T:xxxxxxxx\n"
            end else if (send_time) begin
                case (tx_cnt)
                    0 : begin tx_data<="T"; tx_stb<=1; tx_cnt<=1; end
                    1 : begin tx_data<=":"; tx_stb<=1; tx_cnt<=2; end
                    2 : begin tx_data<=n2h(timing_config[31:28]); tx_stb<=1; tx_cnt<=3; end
                    3 : begin tx_data<=n2h(timing_config[27:24]); tx_stb<=1; tx_cnt<=4; end
                    4 : begin tx_data<=n2h(timing_config[23:20]); tx_stb<=1; tx_cnt<=5; end
                    5 : begin tx_data<=n2h(timing_config[19:16]); tx_stb<=1; tx_cnt<=6; end
                    6 : begin tx_data<=n2h(timing_config[15:12]); tx_stb<=1; tx_cnt<=7; end
                    7 : begin tx_data<=n2h(timing_config[11:8]);  tx_stb<=1; tx_cnt<=8; end
                    8 : begin tx_data<=n2h(timing_config[7:4]);   tx_stb<=1; tx_cnt<=9; end
                    9 : begin tx_data<=n2h(timing_config[3:0]);   tx_stb<=1; tx_cnt<=10;end
                    10: begin tx_data<=8'h0A; tx_stb<=1; tx_cnt<=0; end
                endcase
            end
        end
        //------------------------------------------------------------------
        //  After last byte's stop-bit → clear the active flag
        //------------------------------------------------------------------
        if (tx_done_msg) begin
            if (send_status) send_status <= 0;
            if (send_read )  send_read   <= 0;
            if (send_write)  send_write  <= 0;
            if (send_time )  send_time   <= 0;
        end
    end
end

//======================================================================
//  Debug LEDs (activity, heartbeat, parser busy)
//======================================================================
reg [22:0] rx_act, tx_act;
reg [24:0] hb;

always @(posedge clk_i) begin
    if (rst_i) begin
        rx_act<=0; tx_act<=0; hb<=0;
    end else begin
        hb <= hb + 1;
        rx_act <= rx_stb ? 23'h7FFFFF : (rx_act ? rx_act-1 : 0);
        tx_act <= tx_stb ? 23'h7FFFFF : (tx_act ? tx_act-1 : 0);

        debug_leds_o[0] <= |rx_act;          // RX activity
        debug_leds_o[1] <= |tx_act;          // TX activity
        debug_leds_o[2] <= hb[24];           // heartbeat
        debug_leds_o[3] <= (p_state!=P_IDLE);// parser busy
    end
end
endmodule

//==========================================================================
//  Simple Reset Generator (power-on reset for a few clk cycles)
//==========================================================================
module reset_gen
(
    input  wire clk_i,
    output reg  rst_o
);
    reg [7:0] cnt = 0;
    always @(posedge clk_i) begin
        if (cnt!=8'hFF) begin cnt <= cnt + 1; rst_o <= 1; end
        else               rst_o <= 0;
    end
endmodule

//==========================================================================
//  Top-level wrapper (connect UART pins & LEDs)
//==========================================================================
module top
(
    input  wire        clk100mhz,   // 100 MHz oscillator
    input  wire        uart_rx_i,   // A9  - PC→FPGA
    output wire        uart_tx_o,   // D10 - FPGA→PC
    output wire [3:0]  led          // debug LEDs
);

wire rst_n;
reset_gen u_res (.clk_i(clk100mhz), .rst_o(rst_n));

uart_debug #(
    .CLK_HZ(100_000_000),
    .BAUDRATE(115_200)
) u_dbg (
    .clk_i(clk100mhz),
    .rst_i(rst_n),
    .rx_i (uart_rx_i),
    .tx_o (uart_tx_o),
    .debug_leds_o(led)
);
endmodule
