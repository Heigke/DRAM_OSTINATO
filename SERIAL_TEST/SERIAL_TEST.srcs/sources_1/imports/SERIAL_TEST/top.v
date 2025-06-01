// ────────────────────────────────────────────────────────────────
//   Arty-A7 100T  -  USB-UART-Echo with Debug LEDs
//   115200 baud, 8-N-1
//   FTDI pins:  A9 = RX  (PC → FPGA)
//               D10 = TX (FPGA → PC)
//   LEDs for debug:
//     LED[0] = RX activity
//     LED[1] = TX activity  
//     LED[2] = Heartbeat
//     LED[3] = Error indicator
// ────────────────────────────────────────────────────────────────
`timescale 1ns/1ps

// Simple UART TX - back to basics
module uart_tx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       stb,
    input  wire [7:0] data,
    output reg        tx,
    output wire       busy
);
    localparam CLKS_PER_BIT = CLK_HZ / BAUD;
    
    reg [3:0]  bit_cnt;
    reg [15:0] clk_cnt;
    reg [9:0]  shift;
    
    assign busy = (bit_cnt != 0);
    
    always @(posedge clk) begin
        if (rst) begin
            tx      <= 1'b1;
            bit_cnt <= 0;
            clk_cnt <= 0;
            shift   <= 10'h3FF;
        end else begin
            if (!busy && stb) begin
                shift   <= {1'b1, data, 1'b0};
                bit_cnt <= 10;
                clk_cnt <= 0;
            end else if (busy) begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    tx      <= shift[0];
                    shift   <= {1'b1, shift[9:1]};
                    clk_cnt <= 0;
                    bit_cnt <= bit_cnt - 1;
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end
        end
    end
endmodule

// Simple UART RX - back to basics
module uart_rx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg        stb,
    output reg  [7:0] data
);
    localparam CLKS_PER_BIT = CLK_HZ / BAUD;
    
    // States
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;
    
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_byte;
    
    // Synchronize RX
    reg rx_d1, rx_d2;
    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end
    
    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            stb     <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            case (state)
                IDLE: begin
                    stb     <= 0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    
                    if (rx_d2 == 0) begin  // Start bit
                        state <= START;
                    end
                end
                
                START: begin
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        if (rx_d2 == 0) begin
                            clk_cnt <= 0;
                            state   <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                
                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        rx_byte[bit_idx] <= rx_d2;
                        
                        if (bit_idx == 7) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                
                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        stb   <= 1;
                        data  <= rx_byte;
                        state <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// Top module with debug features
module top (
    input  wire clk100mhz,
    input  wire uart_rx_i,   // A9
    output wire uart_tx_o,   // D10
    output reg [3:0] led     // Debug LEDs
);
    wire clk = clk100mhz;
    
    // Reset generation
    reg [23:0] reset_cnt = 24'hFFFFFF;
    wire rst = (reset_cnt != 0);
    
    always @(posedge clk) begin
        if (reset_cnt != 0)
            reset_cnt <= reset_cnt - 1;
    end
    
    // Heartbeat counter for LED[2]
    reg [24:0] heartbeat;
    always @(posedge clk) begin
        heartbeat <= heartbeat + 1;
    end
    
    // UART signals
    wire       rx_stb;
    wire [7:0] rx_data;
    reg        tx_stb;
    reg  [7:0] tx_data;
    wire       tx_busy;
    
    // Activity counters for LEDs
    reg [22:0] rx_activity;
    reg [22:0] tx_activity;
    
    // UART instances
    uart_rx #(
        .CLK_HZ(100_000_000),
        .BAUD(115200)
    ) u_rx (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx_i),
        .stb(rx_stb),
        .data(rx_data)
    );
    
    uart_tx #(
        .CLK_HZ(100_000_000),
        .BAUD(115200)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .stb(tx_stb),
        .data(tx_data),
        .tx(uart_tx_o),
        .busy(tx_busy)
    );
    
    // Echo logic
    always @(posedge clk) begin
        if (rst) begin
            tx_stb  <= 0;
            tx_data <= 0;
            rx_activity <= 0;
            tx_activity <= 0;
        end else begin
            tx_stb <= 0;
            
            // Count down activity timers
            if (rx_activity != 0) rx_activity <= rx_activity - 1;
            if (tx_activity != 0) tx_activity <= tx_activity - 1;
            
            // Echo received data
            if (rx_stb && !tx_busy) begin
                tx_data <= rx_data;
                tx_stb  <= 1;
                rx_activity <= 23'h7FFFFF;  // Light LED for ~84ms
                tx_activity <= 23'h7FFFFF;
            end
        end
    end
    
    // LED assignments
    always @(posedge clk) begin
        led[0] <= (rx_activity != 0);      // RX activity
        led[1] <= (tx_activity != 0);      // TX activity
        led[2] <= heartbeat[24];           // Heartbeat
        led[3] <= 0;                       // Error (unused for now)
    end
    
endmodule