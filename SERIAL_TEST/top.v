// ────────────────────────────────────────────────────────────────
//   Arty-A7 100T  –  USB-UART-Echo Self-Test
//   115 200 baud, 8-N-1
//   FTDI pins:  A9 = RX  (PC → FPGA)
//               D10 = TX (FPGA → PC)
// ────────────────────────────────────────────────────────────────
`timescale 1ns/1ps

// ▒▒ UART transmitter ▒▒
module uart_tx #(parameter CLK_HZ = 100_000_000,
                 parameter BAUD   = 115_200)(
    input  wire clk, rst, stb,
    input  wire [7:0] data,
    output reg  tx,
    output wire busy);
    localparam DIV = CLK_HZ/BAUD;
    reg [3:0]  bit_cnt;
    reg [15:0] clk_cnt;
    reg [9:0]  shift;
    assign busy = (bit_cnt!=0);
    always @(posedge clk)
    if (rst) begin tx<=1; bit_cnt<=0; clk_cnt<=0; end
    else begin
        if (!busy && stb) begin
            shift   <= {1'b1,data,1'b0};   // stop,data,start
            bit_cnt <= 10;
            clk_cnt <= DIV-1;
        end else if (busy) begin
            if (clk_cnt==0) begin
                tx      <= shift[0];
                shift   <= {1'b1,shift[9:1]};
                clk_cnt <= DIV-1;
                bit_cnt <= bit_cnt-1;
            end else clk_cnt <= clk_cnt-1;
        end
    end
endmodule

// ▒▒ UART receiver ▒▒ (oversample ×16)
module uart_rx #(parameter CLK_HZ = 100_000_000,
                 parameter BAUD   = 115_200)(
    input  wire clk, rst, rx,
    output reg  stb,
    output reg [7:0] data);
    localparam OV = 16;
    localparam DIV = CLK_HZ/(BAUD*OV);
    reg [3:0]  os_cnt;
    reg [15:0] clk_cnt;
    reg [3:0]  bit_cnt;
    reg [8:0]  shift;
    reg rx1, rx2;
    always @(posedge clk) begin rx1<=rx; rx2<=rx1; end
    always @(posedge clk)
    if (rst) begin stb<=0; bit_cnt<=0; end
    else begin
        stb<=0;
        if (bit_cnt==0) begin
            if (!rx2) begin           // start bit edge
                bit_cnt<=10;
                clk_cnt<=DIV/2;
                os_cnt<=0;
            end
        end else if (clk_cnt==0) begin
            clk_cnt<=DIV-1;
            if (os_cnt==OV-1) begin
                os_cnt  <=0;
                shift   <={rx2,shift[8:1]};
                bit_cnt <=bit_cnt-1;
                if (bit_cnt==1) begin data<=shift[7:0]; stb<=1; end
            end else os_cnt<=os_cnt+1;
        end else clk_cnt<=clk_cnt-1;
    end
endmodule

// ▒▒ Top – pure echo ▒▒
module top (
    input  wire clk100mhz,
    input  wire uart_rx_i,   // A9
    output wire uart_tx_o    // D10
);
    // ── 100 MHz in, no PLL needed for UART
    wire clk = clk100mhz;
    reg  rst_q = 1'b1;       // power-on reset few cycles
    always @(posedge clk) rst_q <= 0;

    // UART blocks
    wire rx_stb;   wire [7:0] rx_data;
    reg  tx_stb;   reg  [7:0] tx_data;
    wire tx_busy;

    uart_rx #(.CLK_HZ(100_000_000)) U_RX
        (.clk(clk), .rst(rst_q), .rx(uart_rx_i),
         .stb(rx_stb), .data(rx_data));

    uart_tx #(.CLK_HZ(100_000_000)) U_TX
        (.clk(clk), .rst(rst_q), .stb(tx_stb),
         .data(tx_data), .tx(uart_tx_o), .busy(tx_busy));

    // Echo every received byte
    always @(posedge clk) begin
        tx_stb  <= 0;
        if (rx_stb && !tx_busy) begin
            tx_data <= rx_data;
            tx_stb  <= 1;
        end
    end
endmodule

