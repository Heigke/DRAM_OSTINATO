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
//  Mini UART-to-AXI-Lite bridge
//=================================================================
module mini_uart_axi #(
    parameter CLK_HZ   = 100_000_000,
    parameter BAUDRATE = 115200
)(
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rx_i,
    output wire        tx_o,

    // AXI-Lite master
    output reg         awvalid_o,
    output reg [31:0]  awaddr_o,
    output wire [3:0]  awid_o,
    input  wire        awready_i,

    output reg         wvalid_o,
    output reg [31:0]  wdata_o,
    output wire [3:0]  wstrb_o,
    output reg         wlast_o,
    input  wire        wready_i,

    input  wire        bvalid_i,
    output wire        bready_o,

    output reg         arvalid_o,
    output reg [31:0]  araddr_o,
    output wire [3:0]  arid_o,
    input  wire        arready_i,

    input  wire        rvalid_i,
    input  wire [31:0] rdata_i,
    input  wire        rlast_i,
    output wire        rready_o
);

// UART instantiation
wire        rx_stb;
wire [7:0]  rx_data;
reg         tx_stb;
reg  [7:0]  tx_data;
wire        tx_busy;

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

// Command parser
localparam C_IDLE   = 0,
           C_GETWR  = 1,
           C_GETRD  = 2;

reg [1:0]  state_q;
reg [3:0]  nib_cnt_q;
reg [63:0] shift_q;

function automatic [3:0] hex2n;
    input [7:0] c;
begin
    if (c >= "0" && c <= "9") hex2n = c - "0";
    else if (c >= "a" && c <= "f") hex2n = c - "a" + 4'd10;
    else hex2n = c - "A" + 4'd10;
end
endfunction

wire is_hex = (rx_data >= "0" && rx_data <= "9") ||
              (rx_data >= "a" && rx_data <= "f") ||
              (rx_data >= "A" && rx_data <= "F");

always @(posedge clk_i)
if (rst_i) begin
    awvalid_o <= 0;
    wvalid_o  <= 0;
    arvalid_o <= 0;
    awaddr_o  <= 0;
    araddr_o  <= 0;
    wdata_o   <= 0;
    wlast_o   <= 0;
    nib_cnt_q <= 0;
    shift_q   <= 0;
    state_q   <= C_IDLE;
end else begin
    // Default: clear single-cycle signals
    awvalid_o <= 0;
    wvalid_o  <= 0;
    arvalid_o <= 0;
    wlast_o   <= 0;

    if (rx_stb) begin
        case (state_q)
        C_IDLE: begin
            if (rx_data == "W" || rx_data == "w") begin
                state_q   <= C_GETWR;
                nib_cnt_q <= 0;
                shift_q   <= 0;
            end
            else if (rx_data == "R" || rx_data == "r") begin
                state_q   <= C_GETRD;
                nib_cnt_q <= 0;
                shift_q   <= 0;
            end
        end
        
        C_GETWR: begin
            if (is_hex) begin
                shift_q   <= {shift_q[59:0], hex2n(rx_data)};
                nib_cnt_q <= nib_cnt_q + 1;
            end
            else if (rx_data == " ") begin
                awaddr_o  <= shift_q[31:0];
                shift_q   <= 0;
                nib_cnt_q <= 0;
            end
            else if (rx_data == 8'h0A || rx_data == 8'h0D) begin
                wdata_o   <= shift_q[31:0];
                wvalid_o  <= 1;
                wlast_o   <= 1;
                awvalid_o <= 1;
                state_q   <= C_IDLE;
            end
        end
        
        C_GETRD: begin
            if (is_hex) begin
                shift_q   <= {shift_q[59:0], hex2n(rx_data)};
                nib_cnt_q <= nib_cnt_q + 1;
            end
            else if (rx_data == 8'h0A || rx_data == 8'h0D) begin
                araddr_o  <= shift_q[31:0];
                arvalid_o <= 1;
                state_q   <= C_IDLE;
            end
        end
        endcase
    end
end

assign awid_o   = 4'd0;
assign arid_o   = 4'd0;
assign wstrb_o  = 4'hF;
assign bready_o = 1'b1;
assign rready_o = 1'b1;

// Echo read-back
reg [3:0] tx_cnt_q;
reg       tx_busy_d;

function automatic [7:0] nib2hex;
    input [3:0] n;
begin
    nib2hex = (n < 10) ? (n + "0") : (n - 10 + "a");
end
endfunction

always @(posedge clk_i) begin
    tx_busy_d <= tx_busy;
    tx_stb    <= 1'b0;

    if (rvalid_i && !tx_busy)
        tx_cnt_q <= 4'd0;
    else if (!tx_busy && tx_busy_d)
        tx_cnt_q <= tx_cnt_q + 1;

    if (!tx_busy) begin
        case (tx_cnt_q)
        0: begin tx_data <= nib2hex(rdata_i[31:28]); tx_stb <= 1; end
        1: begin tx_data <= nib2hex(rdata_i[27:24]); tx_stb <= 1; end
        2: begin tx_data <= nib2hex(rdata_i[23:20]); tx_stb <= 1; end
        3: begin tx_data <= nib2hex(rdata_i[19:16]); tx_stb <= 1; end
        4: begin tx_data <= nib2hex(rdata_i[15:12]); tx_stb <= 1; end
        5: begin tx_data <= nib2hex(rdata_i[11: 8]); tx_stb <= 1; end
        6: begin tx_data <= nib2hex(rdata_i[ 7: 4]); tx_stb <= 1; end
        7: begin tx_data <= nib2hex(rdata_i[ 3: 0]); tx_stb <= 1; end
        8: begin tx_data <= 8'h0A;                   tx_stb <= 1; end
        endcase
    end
end
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
    .rready_o (axi_rready)
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
    .dfi_rddata_dnv_i (dfi_rddata_dnv)
);

//-----------------------------------------------------------------
// DDR3 PHY
//-----------------------------------------------------------------
ddr3_dfi_phy #(
    .REFCLK_FREQUENCY  (200),
    .DQS_TAP_DELAY_INIT(27),
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

// LED assignments
always @(posedge clk_w) begin
    led[0] <= (rx_activity != 0);    // RX activity
    led[1] <= (tx_activity != 0);    // TX activity
    led[2] <= heartbeat[24];         // Heartbeat
    led[3] <= ddr3_reset_n;          // DDR3 out of reset
end

endmodule