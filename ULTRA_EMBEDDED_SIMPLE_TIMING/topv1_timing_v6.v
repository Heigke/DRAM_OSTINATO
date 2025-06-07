//-----------------------------------------------------------------
//  Arty-A7-100T  ──  Ultra-Embedded DDR3 core + UART-to-AXI bridge
//  Fixed UART implementation based on working echo test
//
//  Commands:
//     WAAAAAAAA DDDDDDDD<CR>   → write 32-bit word
//     RAAAAAAAA<CR>            → read  32-bit word
//
//  Baud-rate 115200, 8-N-1, USB-UART pins:
//     A9  → uart_rx_i (PC → FPGA)
//     D10 → uart_tx_o (FPGA → PC)
//-----------------------------------------------------------------
`timescale 1ns/1ps

//=================================================================
//  UART TX (from working version)
//=================================================================
module uart_tx #(
    parameter CLK_HZ    = 100_000_000,
    parameter BAUDRATE  = 115200
)(
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       stb_i,
    input  wire [7:0] data_i,
    output reg        tx_o,
    output wire       busy_o
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
//  UART RX (from working version)
//=================================================================
module uart_rx #(
    parameter CLK_HZ    = 100_000_000,
    parameter BAUDRATE  = 115200
)(
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       rx_i,
    output reg        stb_o,
    output reg  [7:0] data_o
);
    localparam CLKS_PER_BIT = CLK_HZ / BAUDRATE;
    
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
            case (state)
                IDLE: begin
                    stb_o   <= 0;
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
//  Mini UART-to-AXI-Lite bridge   (v2 - complete hand-shake)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v2 - complete hand-shake)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v3 - with init wait)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v4 - with timing control)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v5 - Fixed timing control)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v5 - Fixed timing control)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v6 - Working timing control)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge   (v6 - Working timing control)
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge (COMPLETELY REFACTORED)
//  This version guarantees timing control works correctly
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge - FINAL WORKING VERSION
//  Fixed timing control with proper nibble ordering
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge - FINAL WORKING VERSION
//  Fixed timing control with proper nibble ordering
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge - WITH ILA DEBUG PROBES
//  Same logic as before but with extensive debug visibility
//=================================================================
//=================================================================
//  Mini UART-to-AXI-Lite bridge - FINAL WORKING VERSION
//  Fixes one-cycle trigger delay between Parser and TX FSM.
//=================================================================
module mini_uart_axi #(
    parameter CLK_HZ   = 100_000_000,
    parameter BAUDRATE = 115200
)(
    input  wire        clk_i,
    input  wire        rst_i,

    // UART
    input  wire        rx_i,
    output wire        tx_o,

    // AXI-Lite master
    output reg         awvalid_o,
    output reg  [31:0] awaddr_o,
    output wire [3:0]  awid_o,
    input  wire        awready_i,

    output reg         wvalid_o,
    output reg  [31:0] wdata_o,
    output wire [3:0]  wstrb_o,
    output reg         wlast_o,
    input  wire        wready_i,

    input  wire        bvalid_i,
    output wire        bready_o,

    output reg         arvalid_o,
    output reg  [31:0] araddr_o,
    output wire [3:0]  arid_o,
    input  wire        arready_i,

    input  wire        rvalid_i,
    input  wire [31:0] rdata_i,
    input  wire        rlast_i,
    output wire        rready_o,
    
    // Timing control outputs
    output reg  [7:0]  timing_twr_o,
    output reg  [7:0]  timing_tras_o,
    output reg  [7:0]  timing_burst_o,
    output reg  [7:0]  timing_custom_o,
    output reg         timing_valid_o
);

// --- UART instances ---
wire       rx_stb;
wire [7:0] rx_data;
reg        tx_stb;
reg  [7:0] tx_data;
wire       tx_busy;

uart_rx #(.CLK_HZ(CLK_HZ), .BAUDRATE(BAUDRATE)) U_RX (
    .clk_i(clk_i), 
    .rst_i(rst_i), 
    .rx_i(rx_i), 
    .stb_o(rx_stb), 
    .data_o(rx_data)
);

uart_tx #(.CLK_HZ(CLK_HZ), .BAUDRATE(BAUDRATE)) U_TX (
    .clk_i(clk_i), 
    .rst_i(rst_i), 
    .stb_i(tx_stb), 
    .data_i(tx_data), 
    .tx_o(tx_o), 
    .busy_o(tx_busy)
);

// --- Init delay ---
reg [26:0] init_cnt = 0;
wire init_done = init_cnt[26];
always @(posedge clk_i) begin
    if (rst_i) 
        init_cnt <= 0; 
    else if (!init_done) 
        init_cnt <= init_cnt + 1;
end

// --- Common functions ---
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

// --- Command Parser FSM ---
localparam P_IDLE   = 2'd0, 
           P_GETADR = 2'd1, 
           P_GETDAT = 2'd2, 
           P_GETTIM = 2'd3;

reg  [1:0]  p_state;
reg  [31:0] p_data;
reg  [3:0]  p_nibbles;
reg         wr_tag, rd_tag;
reg  [31:0] wr_addr, wr_data;
reg  [31:0] rd_addr;
reg         cmd_is_write;

// --- FIX: Use combinatorial wires for single-cycle triggers ---
wire        trig_status;
wire        trig_timing;

assign trig_status = (p_state == P_IDLE) && rx_stb && (rx_data == "?");
assign trig_timing = (p_state == P_IDLE) && rx_stb && (rx_data == "t");

// --- ILA Debug signals (if still needed) ---
(* mark_debug = "true" *) wire [1:0]  dbg_p_state = p_state;
(* mark_debug = "true" *) wire [31:0] dbg_p_data = p_data;
(* mark_debug = "true" *) wire [3:0]  dbg_p_nibbles = p_nibbles;
(* mark_debug = "true" *) wire       dbg_rx_stb = rx_stb;
(* mark_debug = "true" *) wire [7:0] dbg_rx_data = rx_data;
(* mark_debug = "true" *) wire       dbg_is_hex = is_hex;
(* mark_debug = "true" *) wire       dbg_trig_status = trig_status;
(* mark_debug = "true" *) wire       dbg_trig_timing = trig_timing;
(* mark_debug = "true" *) wire [7:0] dbg_timing_twr = timing_twr_o;
(* mark_debug = "true" *) wire [7:0] dbg_timing_tras = timing_tras_o;
(* mark_debug = "true" *) wire [7:0] dbg_timing_burst = timing_burst_o;
(* mark_debug = "true" *) wire [7:0] dbg_timing_custom = timing_custom_o;
(* mark_debug = "true" *) wire       dbg_timing_valid = timing_valid_o;


always @(posedge clk_i) begin
    if (rst_i) begin
        p_state <= P_IDLE;
        p_data <= 0;
        p_nibbles <= 0;
        wr_tag <= 0;
        rd_tag <= 0;
        cmd_is_write <= 0;
        timing_twr_o <= 0;
        timing_tras_o <= 0;
        timing_burst_o <= 0;
        timing_custom_o <= 0;
        timing_valid_o <= 0;
    end else begin
        timing_valid_o <= 0;
        if (awvalid_o && awready_i) wr_tag <= 0;
        if (arvalid_o && arready_i) rd_tag <= 0;

        if (rx_stb) begin
            case (p_state)
                P_IDLE: begin
                    p_data <= 0;
                    p_nibbles <= 0;
                    // Note: We don't handle '?' or 't' here anymore - they're handled by combinatorial logic
                    if (rx_data=="W"||rx_data=="w") begin 
                        p_state <= P_GETADR; 
                        cmd_is_write <= 1; 
                    end
                    else if (rx_data=="R"||rx_data=="r") begin 
                        p_state <= P_GETADR; 
                        cmd_is_write <= 0; 
                    end
                    else if (rx_data=="T") begin 
                        p_state <= P_GETTIM; 
                    end
                end
                
                P_GETTIM: begin
                    if (is_hex && p_nibbles < 8) begin
                        p_data <= {p_data[27:0], hex2n(rx_data)};
                        p_nibbles <= p_nibbles + 1;
                    end else if ((rx_data==8'h0d)||(rx_data==8'h0a)) begin
                        if (p_nibbles == 8) begin
                            timing_twr_o    <= p_data[31:24];
                            timing_tras_o   <= p_data[23:16];
                            timing_burst_o  <= p_data[15:8];
                            timing_custom_o <= p_data[7:0];
                            timing_valid_o  <= 1;
                        end
                        p_state <= P_IDLE;
                    end
                end
                
                P_GETADR: begin
                    if (is_hex && p_nibbles < 8) begin
                        p_data <= {p_data[27:0], hex2n(rx_data)};
                        p_nibbles <= p_nibbles + 1;
                    end else if (rx_data==" " && cmd_is_write) begin
                        wr_addr <= p_data;
                        p_data <= 0;
                        p_nibbles <= 0;
                        p_state <= P_GETDAT;
                    end else if ((rx_data==8'h0d)||(rx_data==8'h0a)) begin
                        if (!cmd_is_write && init_done) begin
                            rd_addr <= p_data;
                            rd_tag <= 1;
                        end
                        p_state <= P_IDLE;
                    end
                end
                
                P_GETDAT: begin
                    if (is_hex && p_nibbles < 8) begin
                        p_data <= {p_data[27:0], hex2n(rx_data)};
                        p_nibbles <= p_nibbles + 1;
                    end else if ((rx_data==8'h0d)||(rx_data==8'h0a)) begin
                        if (init_done) begin
                            wr_data <= p_data;
                            wr_tag <= 1;
                        end
                        p_state <= P_IDLE;
                    end
                end
            endcase
        end
    end
end

// --- TX Response FSM ---
reg [3:0]  tx_state;
reg [3:0]  tx_cnt;
reg [31:0] rdata_latch;

localparam TX_IDLE   = 4'd0, 
           TX_STATUS = 4'd1, 
           TX_TIMING = 4'd2, 
           TX_RDATA  = 4'd3;

// More debug signals
(* mark_debug = "true" *) wire [3:0]  dbg_tx_state = tx_state;
(* mark_debug = "true" *) wire [3:0]  dbg_tx_cnt = tx_cnt;
(* mark_debug = "true" *) wire       dbg_tx_stb = tx_stb;
(* mark_debug = "true" *) wire [7:0] dbg_tx_data = tx_data;
(* mark_debug = "true" *) wire       dbg_tx_busy = tx_busy;

always @(posedge clk_i) begin
    if (rst_i) begin
        tx_state <= TX_IDLE;
        tx_cnt <= 0;
        tx_stb <= 0;
        tx_data <= 0;
        rdata_latch <= 0;
    end else begin
        tx_stb <= 0;
        
        case (tx_state)
            TX_IDLE: begin
                // Now the triggers are combinatorial, so they're available immediately!
                if (trig_status) begin 
                    tx_state <= TX_STATUS; 
                    tx_cnt <= 0; 
                end
                else if (trig_timing) begin 
                    tx_state <= TX_TIMING; 
                    tx_cnt <= 0; 
                end
                else if (rvalid_i) begin 
                    rdata_latch <= rdata_i; 
                    tx_state <= TX_RDATA; 
                    tx_cnt <= 0; 
                end
            end
            
            TX_STATUS: begin
                if (!tx_busy) begin
                    case (tx_cnt)
                        0: begin tx_data <= init_done ? "R" : "W"; tx_stb <= 1; tx_cnt <= 1; end
                        1: begin tx_data <= 8'h0A; tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_TIMING: begin
                if (!tx_busy) begin
                    case (tx_cnt)
                        0:  begin tx_data <= "T";                       tx_stb <= 1; tx_cnt <= 1; end
                        1:  begin tx_data <= ":";                       tx_stb <= 1; tx_cnt <= 2; end
                        2:  begin tx_data <= n2h(timing_twr_o[7:4]);    tx_stb <= 1; tx_cnt <= 3; end
                        3:  begin tx_data <= n2h(timing_twr_o[3:0]);    tx_stb <= 1; tx_cnt <= 4; end
                        4:  begin tx_data <= n2h(timing_tras_o[7:4]);   tx_stb <= 1; tx_cnt <= 5; end
                        5:  begin tx_data <= n2h(timing_tras_o[3:0]);   tx_stb <= 1; tx_cnt <= 6; end
                        6:  begin tx_data <= n2h(timing_burst_o[7:4]);  tx_stb <= 1; tx_cnt <= 7; end
                        7:  begin tx_data <= n2h(timing_burst_o[3:0]);  tx_stb <= 1; tx_cnt <= 8; end
                        8:  begin tx_data <= n2h(timing_custom_o[7:4]); tx_stb <= 1; tx_cnt <= 9; end
                        9:  begin tx_data <= n2h(timing_custom_o[3:0]); tx_stb <= 1; tx_cnt <= 10; end
                        10: begin tx_data <= 8'h0A;                     tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
            
            TX_RDATA: begin
                if (!tx_busy) begin
                    case (tx_cnt)
                        0: begin tx_data <= n2h(rdata_latch[31:28]); tx_stb <= 1; tx_cnt <= 1; end
                        1: begin tx_data <= n2h(rdata_latch[27:24]); tx_stb <= 1; tx_cnt <= 2; end
                        2: begin tx_data <= n2h(rdata_latch[23:20]); tx_stb <= 1; tx_cnt <= 3; end
                        3: begin tx_data <= n2h(rdata_latch[19:16]); tx_stb <= 1; tx_cnt <= 4; end
                        4: begin tx_data <= n2h(rdata_latch[15:12]); tx_stb <= 1; tx_cnt <= 5; end
                        5: begin tx_data <= n2h(rdata_latch[11:8]);  tx_stb <= 1; tx_cnt <= 6; end
                        6: begin tx_data <= n2h(rdata_latch[7:4]);   tx_stb <= 1; tx_cnt <= 7; end
                        7: begin tx_data <= n2h(rdata_latch[3:0]);   tx_stb <= 1; tx_cnt <= 8; end
                        8: begin tx_data <= 8'h0A;                   tx_stb <= 1; tx_state <= TX_IDLE; end
                    endcase
                end
            end
        endcase
    end
end

// --- AXI Write Handler ---
always @(posedge clk_i) begin
    if (rst_i) begin
        awvalid_o <= 0; 
        wvalid_o <= 0; 
        wlast_o <= 0;
    end else begin
        if (wr_tag && !awvalid_o) begin
            awaddr_o <= wr_addr;
            wdata_o <= wr_data;
            awvalid_o <= 1;
            wvalid_o <= 1;
            wlast_o <= 1;
        end
        if (awready_i) awvalid_o <= 0;
        if (wready_i) begin
            wvalid_o <= 0;
            wlast_o <= 0;
        end
    end
end

// --- AXI Read Handler ---
always @(posedge clk_i) begin
    if (rst_i) begin
        arvalid_o <= 0;
    end else begin
        if (rd_tag && !arvalid_o) begin
            araddr_o <= rd_addr;
            arvalid_o <= 1;
        end
        if (arready_i) arvalid_o <= 0;
    end
end

// --- Fixed AXI signals ---
assign wstrb_o = 4'hF;
assign awid_o = 4'd0;
assign arid_o = 4'd0;
assign bready_o = 1'b1;
assign rready_o = 1'b1;

endmodule

//=================================================================
//  TOP
//=================================================================
module top (
    input  wire         clk100mhz,

    // USB-UART
    input  wire         uart_rx_i,   // A9 (PC → FPGA)
    output wire         uart_tx_o,   // D10 (FPGA → PC)

    // Debug LEDs
    output reg [3:0]    led,

    // DDR3 SDRAM
    output wire         ddr3_reset_n,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_ck_p, 
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_cs_n,
    output wire         ddr3_ras_n, 
    output wire         ddr3_cas_n, 
    output wire         ddr3_we_n,
    output wire [2:0]   ddr3_ba,
    output wire [13:0]  ddr3_addr,
    output wire [0:0]   ddr3_odt,
    output wire [1:0]   ddr3_dm,
    inout  wire [1:0]   ddr3_dqs_p,
    inout  wire [1:0]   ddr3_dqs_n,
    inout  wire [15:0]  ddr3_dq  
);

//-----------------------------------------------------------------
// Clock & reset
//-----------------------------------------------------------------
wire clk_w, rst_w, clk_ddr_w, clk_ddr_dqs_w, clk_ref_w;

artix7_pll u_pll (
     .clkref_i (clk100mhz),
     .clkout0_o(clk_w),          // 100 MHz fabric
     .clkout1_o(clk_ddr_w),      // 400 MHz DDR
     .clkout2_o(clk_ref_w),      // 200 MHz IDELAYREF
     .clkout3_o(clk_ddr_dqs_w)   // 400 MHz, 90° phase shift
);

reset_gen u_rst (
     .clk_i (clk_w),
     .rst_o (rst_w)
);

// Debug heartbeat
reg [24:0] heartbeat;
always @(posedge clk_w) heartbeat <= heartbeat + 1;

// Activity indicators
reg [22:0] rx_activity;
reg [22:0] tx_activity;

//-----------------------------------------------------------------
// UART-to-AXI bridge
//-----------------------------------------------------------------
wire        axi_awvalid, axi_wvalid, axi_bready, axi_arvalid, axi_rready;
wire [31:0] axi_awaddr,  axi_wdata, axi_araddr;
wire        axi_wlast;
wire [3:0]  axi_wstrb;
wire        axi_awready, axi_wready, axi_bvalid;
wire        axi_arready, axi_rvalid;
wire [31:0] axi_rdata;
wire [1:0]  axi_bresp, axi_rresp;
wire [3:0]  axi_bid, axi_rid;
wire        axi_rlast;

// NEW: Timing control signals
wire [7:0]  timing_twr;
wire [7:0]  timing_tras;
wire [7:0]  timing_burst;
wire [7:0]  timing_custom;
wire        timing_valid;

mini_uart_axi #(
    .CLK_HZ  (100_000_000),
    .BAUDRATE(115200)
) u_uart (
    .clk_i   (clk_w),
    .rst_i   (rst_w),
    .rx_i    (uart_rx_i),
    .tx_o    (uart_tx_o),

    .awvalid_o(axi_awvalid),
    .awaddr_o (axi_awaddr),
    .awready_i(axi_awready),

    .wvalid_o (axi_wvalid),
    .wdata_o  (axi_wdata),
    .wstrb_o  (axi_wstrb),
    .wlast_o  (axi_wlast),
    .wready_i (axi_wready),

    .bvalid_i (axi_bvalid),
    .bready_o (axi_bready),

    .arvalid_o(axi_arvalid),
    .araddr_o (axi_araddr),
    .arready_i(axi_arready),

    .rvalid_i (axi_rvalid),
    .rdata_i  (axi_rdata),
    .rlast_i  (axi_rlast),
    .rready_o (axi_rready),
    
    // NEW: Timing control outputs
    .timing_twr_o(timing_twr),
    .timing_tras_o(timing_tras),
    .timing_burst_o(timing_burst),
    .timing_custom_o(timing_custom),
    .timing_valid_o(timing_valid)
);
// Fixed-value AXI fields
wire [3:0] axi_awid   = 4'd0;
wire [7:0] axi_awlen  = 8'd0;    // single beat
wire [1:0] axi_awburst= 2'b01;   // INCR
wire [3:0] axi_arid   = 4'd0;
wire [7:0] axi_arlen  = 8'd0;    // single beat
wire [1:0] axi_arburst= 2'b01;   // INCR

// Monitor UART activity
always @(posedge clk_w) begin
    if (axi_awvalid || axi_arvalid) rx_activity <= 23'h7FFFFF;
    else if (rx_activity) rx_activity <= rx_activity - 1;
    
    if (axi_rvalid) tx_activity <= 23'h7FFFFF;
    else if (tx_activity) tx_activity <= tx_activity - 1;
end

//-----------------------------------------------------------------
// DDR3 Controller
//-----------------------------------------------------------------
wire [14:0] dfi_addr;
wire [2:0]  dfi_bank;
wire        dfi_cas_n, dfi_cke, dfi_cs_n, dfi_odt, dfi_ras_n, dfi_reset_n, dfi_we_n;
wire [31:0] dfi_wrdata, dfi_rddata;
wire        dfi_wrdata_en, dfi_rddata_en, dfi_rddata_valid;
wire [3:0]  dfi_wrdata_mask;
wire [1:0]  dfi_rddata_dnv;

ddr3_axi #(
    .DDR_MHZ          (100),
    .DDR_WRITE_LATENCY(4),
    .DDR_READ_LATENCY (4)
) u_ddr (
    .clk_i (clk_w),
    .rst_i (rst_w),

    // AXI from UART bridge
    .inport_awvalid_i (axi_awvalid),
    .inport_awaddr_i  (axi_awaddr),
    .inport_awid_i    (axi_awid),
    .inport_awlen_i   (axi_awlen),
    .inport_awburst_i (axi_awburst),
    .inport_wvalid_i  (axi_wvalid),
    .inport_wdata_i   (axi_wdata),
    .inport_wstrb_i   (axi_wstrb),
    .inport_wlast_i   (axi_wlast),
    .inport_bready_i  (axi_bready),
    .inport_arvalid_i (axi_arvalid),
    .inport_araddr_i  (axi_araddr),
    .inport_arid_i    (axi_arid),
    .inport_arlen_i   (axi_arlen),
    .inport_arburst_i (axi_arburst),
    .inport_rready_i  (axi_rready),

    .inport_awready_o (axi_awready),
    .inport_wready_o  (axi_wready),
    .inport_bvalid_o  (axi_bvalid),
    .inport_bresp_o   (axi_bresp),
    .inport_bid_o     (axi_bid),
    .inport_arready_o (axi_arready),
    .inport_rvalid_o  (axi_rvalid),
    .inport_rdata_o   (axi_rdata),
    .inport_rresp_o   (axi_rresp),
    .inport_rid_o     (axi_rid),
    .inport_rlast_o   (axi_rlast),

    // DFI toward PHY
    .dfi_address_o    (dfi_addr),
    .dfi_bank_o       (dfi_bank),
    .dfi_cas_n_o      (dfi_cas_n),
    .dfi_cke_o        (dfi_cke),
    .dfi_cs_n_o       (dfi_cs_n),
    .dfi_odt_o        (dfi_odt),
    .dfi_ras_n_o      (dfi_ras_n),
    .dfi_reset_n_o    (dfi_reset_n),
    .dfi_we_n_o       (dfi_we_n),
    .dfi_wrdata_o     (dfi_wrdata),
    .dfi_wrdata_en_o  (dfi_wrdata_en),
    .dfi_wrdata_mask_o(dfi_wrdata_mask),
    .dfi_rddata_en_o  (dfi_rddata_en),
    .dfi_rddata_i     (dfi_rddata),
    .dfi_rddata_valid_i(dfi_rddata_valid),
    .dfi_rddata_dnv_i (dfi_rddata_dnv),
    
    // NEW: Timing control inputs
    .timing_twr_i(timing_twr),
    .timing_tras_i(timing_tras),
    .timing_burst_i(timing_burst),
    .timing_custom_i(timing_custom),
    .timing_valid_i(timing_valid)
);

//-----------------------------------------------------------------
// DDR3 PHY
//-----------------------------------------------------------------
ddr3_dfi_phy #(
    .REFCLK_FREQUENCY  (200),
    .DQS_TAP_DELAY_INIT(30),
    .DQ_TAP_DELAY_INIT (0),
    .TPHY_RDLAT        (5)
) u_phy (
    .clk_i         (clk_w),
    .rst_i         (rst_w),

    .clk_ddr_i     (clk_ddr_w),
    .clk_ddr90_i   (clk_ddr_dqs_w),
    .clk_ref_i     (clk_ref_w),

    .cfg_valid_i   (1'b0),
    .cfg_i         (32'b0),

    .dfi_address_i (dfi_addr),
    .dfi_bank_i    (dfi_bank),
    .dfi_cas_n_i   (dfi_cas_n),
    .dfi_cke_i     (dfi_cke),
    .dfi_cs_n_i    (dfi_cs_n),
    .dfi_odt_i     (dfi_odt),
    .dfi_ras_n_i   (dfi_ras_n),
    .dfi_reset_n_i (dfi_reset_n),
    .dfi_we_n_i    (dfi_we_n),
    .dfi_wrdata_i  (dfi_wrdata),
    .dfi_wrdata_en_i(dfi_wrdata_en),
    .dfi_wrdata_mask_i(dfi_wrdata_mask),
    .dfi_rddata_en_i(dfi_rddata_en),
    .dfi_rddata_o     (dfi_rddata),
    .dfi_rddata_valid_o(dfi_rddata_valid),
    .dfi_rddata_dnv_o (dfi_rddata_dnv),

    .ddr3_ck_p_o   (ddr3_ck_p),
    .ddr3_ck_n_o   (ddr3_ck_n),
    .ddr3_cke_o    (ddr3_cke),
    .ddr3_reset_n_o(ddr3_reset_n),
    .ddr3_ras_n_o  (ddr3_ras_n),
    .ddr3_cas_n_o  (ddr3_cas_n),
    .ddr3_we_n_o   (ddr3_we_n),
    .ddr3_cs_n_o   (ddr3_cs_n),
    .ddr3_ba_o     (ddr3_ba),
    .ddr3_addr_o   (ddr3_addr),
    .ddr3_odt_o    (ddr3_odt),
    .ddr3_dm_o     (ddr3_dm),
    .ddr3_dq_io    (ddr3_dq),
    .ddr3_dqs_p_io (ddr3_dqs_p),
    .ddr3_dqs_n_io (ddr3_dqs_n)
);

/*// NEW: Add ILA probes for timing debugging
(* mark_debug = "true" *) wire [7:0]  ila_timing_twr = timing_twr;
(* mark_debug = "true" *) wire [7:0]  ila_timing_tras = timing_tras;
(* mark_debug = "true" *) wire [7:0]  ila_timing_burst = timing_burst;
(* mark_debug = "true" *) wire        ila_timing_valid = timing_valid;
(* mark_debug = "true" *) wire [3:0]  ila_wr_cycle_cnt = u_ddr.u_core.u_seq.wr_cycle_cnt_q;
(* mark_debug = "true" *) wire        ila_partial_write = u_ddr.u_core.u_seq.partial_write_mode_q;
(* mark_debug = "true" *) wire [79:0] ila_ddr_state = u_ddr.u_core.dbg_state;*/
// =================================================================
// ILA DEBUG PROBES - Comprehensive debugging
// =================================================================

// Direct probes from within mini_uart_axi using hierarchical references
(* mark_debug = "true" *) wire [1:0]  ila_p_state        = u_uart.dbg_p_state;
(* mark_debug = "true" *) wire [31:0] ila_p_data         = u_uart.dbg_p_data;
(* mark_debug = "true" *) wire [3:0]  ila_p_nibbles      = u_uart.dbg_p_nibbles;
(* mark_debug = "true" *) wire        ila_rx_stb         = u_uart.dbg_rx_stb;
(* mark_debug = "true" *) wire [7:0]  ila_rx_data        = u_uart.dbg_rx_data;
(* mark_debug = "true" *) wire        ila_is_hex         = u_uart.dbg_is_hex;
(* mark_debug = "true" *) wire        ila_trig_status    = u_uart.dbg_trig_status;
(* mark_debug = "true" *) wire        ila_trig_timing    = u_uart.dbg_trig_timing;
(* mark_debug = "true" *) wire [7:0]  ila_timing_twr     = u_uart.dbg_timing_twr;
(* mark_debug = "true" *) wire [7:0]  ila_timing_tras    = u_uart.dbg_timing_tras;
(* mark_debug = "true" *) wire [7:0]  ila_timing_burst   = u_uart.dbg_timing_burst;
(* mark_debug = "true" *) wire [7:0]  ila_timing_custom  = u_uart.dbg_timing_custom;
(* mark_debug = "true" *) wire        ila_timing_valid   = u_uart.dbg_timing_valid;
(* mark_debug = "true" *) wire [3:0]  ila_tx_state       = u_uart.dbg_tx_state;
(* mark_debug = "true" *) wire [3:0]  ila_tx_cnt         = u_uart.dbg_tx_cnt;
(* mark_debug = "true" *) wire        ila_tx_stb         = u_uart.dbg_tx_stb;
(* mark_debug = "true" *) wire [7:0]  ila_tx_data        = u_uart.dbg_tx_data;
(* mark_debug = "true" *) wire        ila_tx_busy        = u_uart.dbg_tx_busy;

// Deep hierarchical probes - reach into UART TX/RX modules
(* mark_debug = "true" *) wire [1:0]  ila_uart_rx_state  = u_uart.U_RX.state;
(* mark_debug = "true" *) wire [15:0] ila_uart_rx_clkcnt = u_uart.U_RX.clk_cnt;
(* mark_debug = "true" *) wire [3:0]  ila_uart_tx_bitcnt = u_uart.U_TX.bit_cnt;
(* mark_debug = "true" *) wire [15:0] ila_uart_tx_clkcnt = u_uart.U_TX.clk_cnt;

// Top-level timing signals
(* mark_debug = "true" *) wire [7:0]  ila_top_timing_twr = timing_twr;
(* mark_debug = "true" *) wire [7:0]  ila_top_timing_tras = timing_tras;
(* mark_debug = "true" *) wire [7:0]  ila_top_timing_burst = timing_burst;
(* mark_debug = "true" *) wire [7:0]  ila_top_timing_custom = timing_custom;
(* mark_debug = "true" *) wire        ila_top_timing_valid = timing_valid;

// Debug calculation to show what we SHOULD be sending
(* mark_debug = "true" *) wire [7:0]  ila_expected_char_0 = "T";
(* mark_debug = "true" *) wire [7:0]  ila_expected_char_1 = ":";
(* mark_debug = "true" *) wire [7:0]  ila_expected_char_2 = (u_uart.timing_twr_o[7:4] < 10) ? 
                                                               ("0" + u_uart.timing_twr_o[7:4]) : 
                                                               ("a" + u_uart.timing_twr_o[7:4] - 10);

// Create a debug trigger wire
(* mark_debug = "true" *) wire ila_trigger = ila_rx_stb && (ila_rx_data == 8'h74 || ila_rx_data == 8'h54); // 't' or 'T'
// First, let's create some combined probe buses to reduce ILA ports
wire [63:0] ila_probe0;
wire [63:0] ila_probe1;
wire [63:0] ila_probe2;
wire [31:0] ila_probe3;

// Pack signals into probe buses
assign ila_probe0 = {
    24'b0,                      // [63:40] - unused
    ila_timing_custom,          // [39:32] - 8 bits
    ila_timing_burst,           // [31:24] - 8 bits
    ila_timing_tras,            // [23:16] - 8 bits
    ila_timing_twr,             // [15:8]  - 8 bits
    ila_rx_data                 // [7:0]   - 8 bits
};

assign ila_probe1 = {
    16'b0,                      // [63:48] - unused
    ila_uart_tx_clkcnt,         // [47:32] - 16 bits
    ila_uart_rx_clkcnt,         // [31:16] - 16 bits
    ila_tx_data,                // [15:8]  - 8 bits
    ila_p_nibbles,              // [7:4]   - 4 bits
    ila_tx_cnt                  // [3:0]   - 4 bits
};

assign ila_probe2 = {
    20'b0,                      // [63:44] - unused
    ila_uart_tx_bitcnt,         // [43:40] - 4 bits
    ila_uart_rx_state,          // [39:38] - 2 bits
    ila_p_state,                // [37:36] - 2 bits
    ila_tx_state,               // [35:32] - 4 bits (using 4 bits for safety)
    ila_p_data                  // [31:0]  - 32 bits
};

assign ila_probe3 = {
    16'b0,                      // [31:16] - unused
    ila_timing_valid,           // [15]
    ila_trig_timing,            // [14]
    ila_trig_status,            // [13]
    ila_is_hex,                 // [12]
    ila_tx_busy,                // [11]
    ila_tx_stb,                 // [10]
    ila_rx_stb,                 // [9]
    ila_trigger,                // [8]
    8'b0                        // [7:0] - unused
};

// ILA Core instantiation
ila_0 u_ila (
    .clk(clk_w),               // Connect to your main clock
    .probe0(ila_probe0),       // 64-bit probe
    .probe1(ila_probe1),       // 64-bit probe
    .probe2(ila_probe2),       // 64-bit probe
    .probe3(ila_probe3)        // 32-bit probe
);
// LED assignments
always @(posedge clk_w) begin
    led[0] <= (rx_activity != 0);    // RX activity
    led[1] <= (tx_activity != 0);    // TX activity
    led[2] <= heartbeat[24];         // Heartbeat
    led[3] <= ddr3_reset_n;          // DDR3 out of reset
end

endmodule



