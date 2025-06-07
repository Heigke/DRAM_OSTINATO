//=================================================================
//
//            UART Command Processor - Debug Top
//
//  * File: uart_debug_top.v
//  * Author: Gemini
//  * Date: 2024-05-18
//
//  * Description:
//    This is a simplified, self-contained project for debugging
//    the UART command interface in isolation. It removes all
//    AXI and DDR3 logic to focus solely on the parser and
//    response state machines.
//
//  * New Command Protocol:
//    All commands MUST be terminated with a carriage return 
//    (Enter key) to be processed.
//
//    - T0A0B04FF<CR> : Set timing registers
//    - t<CR>         : Read timing registers
//    - ?<CR>         : Check status
//    - R12345678<CR> : Read from dummy address
//    - W12345678 DEADBEEF<CR> : Write to dummy address
//
//=================================================================
`timescale 1ns/1ps

//=================================================================
//  Module: uart_tx (Standard, from previous version)
//=================================================================
module uart_tx #(
    parameter CLK_HZ   = 100_000_000,
    parameter BAUDRATE = 115200
)(
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        stb_i,
    input  wire [7:0]  data_i,
    output reg         tx_o,
    output wire        busy_o
);
    localparam CLKS_PER_BIT = CLK_HZ / BAUDRATE;
    
    reg [3:0]  bit_cnt;
    reg [15:0] clk_cnt;
    reg [9:0]  shift;
    
    assign busy_o = (bit_cnt != 0);
    
    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_o    <= 1'b1;
            bit_cnt <= 0;
            clk_cnt <= 0;
            shift   <= 10'h3FF;
        end else begin
            if (!busy_o && stb_i) begin
                shift   <= {1'b1, data_i, 1'b0};
                bit_cnt <= 10;
                clk_cnt <= 0;
            end else if (busy_o) begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    tx_o    <= shift[0];
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

//=================================================================
//  Module: uart_rx (Standard, from previous version)
//=================================================================
module uart_rx #(
    parameter CLK_HZ   = 100_000_000,
    parameter BAUDRATE = 115200
)(
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rx_i,
    output reg         stb_o,
    output reg  [7:0]  data_o
);
    localparam CLKS_PER_BIT = CLK_HZ / BAUDRATE;
    
    localparam IDLE  = 2'b00, START = 2'b01, DATA  = 2'b10, STOP  = 2'b11;
    
    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_byte;
    
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
            stb_o <= 0; // Default value
            case (state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_d2 == 0) state <= START;
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
                        stb_o  <= 1;
                        data_o <= rx_byte;
                        state  <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


//=================================================================
//  Module: command_processor
//  Handles parsing and responding to all UART commands.
//=================================================================
module command_processor (
    input  wire       clk_i,
    input  wire       rst_i,
    // UART Interface
    input  wire       rx_stb_i,
    input  wire [7:0] rx_data_i,
    output reg        tx_stb_o,
    output reg [7:0]  tx_data_o,
    input  wire       tx_busy_i
);

// --- Internal State ---
reg [7:0] timing_twr;
reg [7:0] timing_tras;
reg [7:0] timing_burst;
reg [7:0] timing_custom;

// --- Parser Logic ---
reg  [7:0] cmd_buffer [0:31]; // Buffer for incoming command
reg  [4:0] buffer_idx;
reg        cmd_ready;         // Flag to indicate a full command is received

always @(posedge clk_i) begin
    if (rst_i) begin
        buffer_idx <= 0;
        cmd_ready  <= 0;
    end else begin
        cmd_ready <= 0; // Pulse for one cycle

        if (rx_stb_i) begin
            // On carriage return or newline, command is ready
            if (rx_data_i == 8'h0D || rx_data_i == 8'h0A) begin
                if (buffer_idx > 0) begin
                    cmd_ready <= 1;
                end
                // Reset for next command regardless
                buffer_idx <= 0;
            end else begin
                // Buffer the character
                if (buffer_idx < 32) begin
                    cmd_buffer[buffer_idx] <= rx_data_i;
                    buffer_idx <= buffer_idx + 1;
                end
            end
        end
    end
end

// --- Helper function for hex to nibble conversion ---
function [3:0] hex2n;
    input [7:0] c;
    begin
        if (c >= 8'h30 && c <= 8'h39)      // '0' to '9'
            hex2n = c - 8'h30;
        else if (c >= 8'h41 && c <= 8'h46) // 'A' to 'F'
            hex2n = c - 8'h41 + 4'h0A;
        else if (c >= 8'h61 && c <= 8'h66) // 'a' to 'f'
            hex2n = c - 8'h61 + 4'h0A;
        else
            hex2n = 4'h0;
    end
endfunction

// --- Helper function for nibble to hex conversion ---
function [7:0] n2h;
    input [3:0] n;
    begin
        if (n < 4'hA)
            n2h = n + 8'h30;      // '0' to '9'
        else
            n2h = n - 4'hA + 8'h61; // 'a' to 'f'
    end
endfunction

// --- Response Logic ---
localparam TX_IDLE      = 3'd0,
           TX_ECHO      = 3'd1, // For Write command
           TX_STATUS    = 3'd2, // For '?'
           TX_TIMING    = 3'd3, // For 't'
           TX_DUMMY_READ= 3'd4; // For 'R'

reg [2:0]  tx_state;
reg [3:0]  tx_cnt;
reg [31:0] p_data; // Temporary register for parsing hex values

always @(posedge clk_i) begin
    if (rst_i) begin
        tx_state      <= TX_IDLE;
        tx_stb_o      <= 0;
        tx_cnt        <= 0;
        timing_twr    <= 0;
        timing_tras   <= 0;
        timing_burst  <= 0;
        timing_custom <= 0;
    end else begin
        tx_stb_o <= 0; // Default

        case (tx_state)
            TX_IDLE: begin
                if (cmd_ready) begin
                    tx_cnt <= 0;
                    case (cmd_buffer[0])
                        8'h3F: tx_state <= TX_STATUS;    // '?'
                        8'h74: tx_state <= TX_TIMING;    // 't'
                        8'h52: tx_state <= TX_DUMMY_READ; // 'R'
                        8'h57: tx_state <= TX_ECHO;      // 'W'
                        8'h54: begin                     // 'T'
                            // Parse and set timing registers immediately
                            p_data = {hex2n(cmd_buffer[1]), hex2n(cmd_buffer[2]), hex2n(cmd_buffer[3]), hex2n(cmd_buffer[4]),
                                      hex2n(cmd_buffer[5]), hex2n(cmd_buffer[6]), hex2n(cmd_buffer[7]), hex2n(cmd_buffer[8])};
                            timing_twr    <= p_data[31:24];
                            timing_tras   <= p_data[23:16];
                            timing_burst  <= p_data[15:8];
                            timing_custom <= p_data[7:0];
                            tx_state <= TX_ECHO; // Also just respond with "OK"
                        end
                        default: begin
                           // Do nothing for unknown commands, just stay in IDLE
                           tx_state <= TX_IDLE;
                        end
                    endcase
                end
            end

            TX_ECHO: begin
                if (!tx_busy_i) begin
                    case(tx_cnt)
                        0: begin tx_data_o <= 8'h4F; tx_stb_o <= 1; tx_cnt <= 1; end // 'O'
                        1: begin tx_data_o <= 8'h4B; tx_stb_o <= 1; tx_cnt <= 2; end // 'K'
                        2: begin tx_data_o <= 8'h0A; tx_stb_o <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_STATUS: begin
                if (!tx_busy_i) begin
                    case(tx_cnt)
                        0: begin tx_data_o <= 8'h52; tx_stb_o <= 1; tx_cnt <= 1; end // 'R'
                        1: begin tx_data_o <= 8'h0A; tx_stb_o <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end

            TX_DUMMY_READ: begin
                if (!tx_busy_i) begin
                    case (tx_cnt)
                        0:  begin tx_data_o <= 8'h44; tx_stb_o <= 1; tx_cnt <= 1; end // 'D'
                        1:  begin tx_data_o <= 8'h45; tx_stb_o <= 1; tx_cnt <= 2; end // 'E'
                        2:  begin tx_data_o <= 8'h41; tx_stb_o <= 1; tx_cnt <= 3; end // 'A'
                        3:  begin tx_data_o <= 8'h44; tx_stb_o <= 1; tx_cnt <= 4; end // 'D'
                        4:  begin tx_data_o <= 8'h42; tx_stb_o <= 1; tx_cnt <= 5; end // 'B'
                        5:  begin tx_data_o <= 8'h45; tx_stb_o <= 1; tx_cnt <= 6; end // 'E'
                        6:  begin tx_data_o <= 8'h45; tx_stb_o <= 1; tx_cnt <= 7; end // 'E'
                        7:  begin tx_data_o <= 8'h46; tx_stb_o <= 1; tx_cnt <= 8; end // 'F'
                        8:  begin tx_data_o <= 8'h0A; tx_stb_o <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_TIMING: begin
                if (!tx_busy_i) begin
                    case (tx_cnt)
                        0:  begin tx_data_o <= 8'h54;                    tx_stb_o <= 1; tx_cnt <= 1; end // 'T'
                        1:  begin tx_data_o <= 8'h3A;                    tx_stb_o <= 1; tx_cnt <= 2; end // ':'
                        2:  begin tx_data_o <= n2h(timing_twr[7:4]);     tx_stb_o <= 1; tx_cnt <= 3; end
                        3:  begin tx_data_o <= n2h(timing_twr[3:0]);     tx_stb_o <= 1; tx_cnt <= 4; end
                        4:  begin tx_data_o <= n2h(timing_tras[7:4]);    tx_stb_o <= 1; tx_cnt <= 5; end
                        5:  begin tx_data_o <= n2h(timing_tras[3:0]);    tx_stb_o <= 1; tx_cnt <= 6; end
                        6:  begin tx_data_o <= n2h(timing_burst[7:4]);   tx_stb_o <= 1; tx_cnt <= 7; end
                        7:  begin tx_data_o <= n2h(timing_burst[3:0]);   tx_stb_o <= 1; tx_cnt <= 8; end
                        8:  begin tx_data_o <= n2h(timing_custom[7:4]);  tx_stb_o <= 1; tx_cnt <= 9; end
                        9:  begin tx_data_o <= n2h(timing_custom[3:0]);  tx_stb_o <= 1; tx_cnt <= 10; end
                        10: begin tx_data_o <= 8'h0A;                    tx_stb_o <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
        endcase
    end
end

endmodule

//=================================================================
//  Module: uart_debug_top
//  Top-level module for UART debug project.
//=================================================================
module uart_debug_top (
    input  wire       clk100mhz,
    // UART
    input  wire       uart_rx_i,
    output wire       uart_tx_o
);

// --- Clock and Reset ---
wire clk_w;
wire rst_w;

// Use a simple power-on reset generator
reg  [15:0] reset_counter = 0;
assign rst_w = ~(&reset_counter); // Reset is active until counter fills up
always @(posedge clk100mhz) begin
    if (!rst_w)
        reset_counter <= reset_counter + 1;
end

// --- Command Processor Instance ---
wire       rx_stb;
wire [7:0] rx_data;
wire       tx_stb;
wire [7:0] tx_data;
wire       tx_busy;

command_processor u_cmd_proc (
    .clk_i      (clk100mhz),
    .rst_i      (rst_w),
    .rx_stb_i   (rx_stb),
    .rx_data_i  (rx_data),
    .tx_stb_o   (tx_stb),
    .tx_data_o  (tx_data),
    .tx_busy_i  (tx_busy)
);

// --- UART Instances ---
uart_rx #(.CLK_HZ(100_000_000), .BAUDRATE(115200)) U_RX (
    .clk_i(clk100mhz),
    .rst_i(rst_w),
    .rx_i(uart_rx_i),
    .stb_o(rx_stb),
    .data_o(rx_data)
);

uart_tx #(.CLK_HZ(100_000_000), .BAUDRATE(115200)) U_TX (
    .clk_i(clk100mhz),
    .rst_i(rst_w),
    .stb_i(tx_stb),
    .data_i(tx_data),
    .tx_o(uart_tx_o),
    .busy_o(tx_busy)
);

endmodule