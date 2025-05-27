// ddr3_decay_test_top.sv
// Includes Clock Domain Crossing for UART signals and revised DDR3L init
module ddr3_decay_test_top (
    input wire clk100mhz_i,      // Board clock 100MHz
    input wire reset_btn_i,      // Active high reset button for whole system
    input wire start_btn_i,      // Button to start the DDR3 test sequence

    // LEDs for status
    output logic status_led0_o,    // Test in progress / Idle
    output logic status_led1_o,    // Test success (data match)
    output logic status_led2_o,    // Test fail (data mismatch / decay)
    output logic status_led3_o,    // UART TX activity

    output logic uart_txd_o,       // UART TX pin

    // DDR3 Interface signals
    output logic [13:0] ddr3_addr_o, // Matches 16K rows A[13:0] for 128M16 part [cite: 11]
    output logic [2:0]  ddr3_ba_o,
    output logic        ddr3_cas_n_o,
    output logic [0:0]  ddr3_cke_o,    // Single CKE line
    output logic [0:0]  ddr3_ck_n_o,
    output logic [0:0]  ddr3_ck_p_o,
    output logic [0:0]  ddr3_cs_n_o,   // Single Chip Select
    output logic [1:0]  ddr3_dm_o,     // LDM and UDM for x16 [cite: 31, 36]
    inout  wire [15:0]  ddr3_dq_io,    // x16 data width
    inout  wire [1:0]   ddr3_dqs_n_io, // LDQS_n, UDQS_n
    inout  wire [1:0]   ddr3_dqs_p_io, // LDQS_p, UDQS_p
    output logic [0:0]  ddr3_odt_o,    // Single ODT line
    output logic        ddr3_ras_n_o,
    output logic        ddr3_reset_n_o, // To DDR3 chip (active LOW)
    output logic        ddr3_we_n_o
);

    // --- Clocking and Reset Logic ---
    logic clk_phy_sys;      // PHY system clock (200MHz), FSM runs on this
    logic clk_phy_ddr;      // PHY DDR clock (400MHz)
    logic clk_phy_ddr90;    // PHY DDR clock 90-deg phase (400MHz)
    logic clk_idelay_ref;   // PHY IDELAYCTRL reference clock (200MHz)
    logic mmcm_locked;
    
    logic sys_rst_fsm_phy;  // Synchronized, active high reset for FSM and PHY (clk_phy_sys domain)
    logic rst_for_uart;     // Synchronized, active high reset for UART (clk100mhz_i domain)

    // MMCM instance (Vivado Clocking Wizard IP MUST be named 'clk_wiz_0')
 // MMCM instance (Vivado Clocking Wizard IP named 'clk_wiz_0')
clk_wiz_0 u_clk_wiz ( // Instance name 'u_clk_wiz'
    // Clock out ports - IP port name(your_signal_name)
    .clk_phy_sys(clk_phy_sys),         // IP port is clk_phy_sys, connected to your clk_phy_sys
    .clk_phy_ddr(clk_phy_ddr),         // IP port is clk_phy_ddr, connected to your clk_phy_ddr
    .clk_phy_ddr90(clk_phy_ddr90),     // IP port is clk_phy_ddr90, connected to your clk_phy_ddr90
    .clk_idelay_ref(clk_idelay_ref),   // IP port is clk_idelay_ref, connected to your clk_idelay_ref
    // Status and control signals
    .reset(reset_btn_i),             // IP port is reset, connected to your reset_btn_i
    .locked(mmcm_locked),            // IP port is locked, connected to your mmcm_locked
   // Clock in ports
    .clk_in1(clk100mhz_i)            // IP port is clk_in1, connected to your clk100mhz_i
);

    logic reset_btn_phy_sync_0, reset_btn_phy_sync_1;
    always_ff @(posedge clk_phy_sys) begin
        reset_btn_phy_sync_0 <= reset_btn_i;
        reset_btn_phy_sync_1 <= reset_btn_phy_sync_0;
    end
    assign sys_rst_fsm_phy = reset_btn_phy_sync_1 | ~mmcm_locked;

    logic reset_btn_uart_sync_0, reset_btn_uart_sync_1;
    always_ff @(posedge clk100mhz_i) begin
        reset_btn_uart_sync_0 <= reset_btn_i;
        reset_btn_uart_sync_1 <= reset_btn_uart_sync_0;
    end
    assign rst_for_uart = reset_btn_uart_sync_1 | ~mmcm_locked;

    // --- DFI PHY Instance ---
    localparam TPHY_RDLAT_C  = 4; // From PHY parameters
    localparam TPHY_WRLAT_C  = 3; // From PHY parameters
    localparam CAS_LATENCY_C = 6; // Programmed into MR0, CL for DDR3-800 operation

    logic [14:0] dfi_address_s; // DFI address can be up to 15 bits wide
    logic [2:0]  dfi_bank_s;
    logic        dfi_cas_n_s, dfi_cke_s, dfi_cs_n_s, dfi_odt_s, dfi_ras_n_s;
    logic        dfi_reset_n_s, dfi_we_n_s, dfi_wrdata_en_s, dfi_rddata_en_s;
    logic [31:0] dfi_wrdata_s, dfi_rddata_r;
    logic [3:0]  dfi_wrdata_mask_s; // For x16, corresponds to 2 DFI phases, 2 DMs per phase
    logic        dfi_rddata_valid_r;
    logic [1:0]  dfi_rddata_dnv_r;

    ddr3_dfi_phy #( .REFCLK_FREQUENCY(200), .DQS_TAP_DELAY_INIT(15), .DQ_TAP_DELAY_INIT(1),
                   .TPHY_RDLAT(TPHY_RDLAT_C), .TPHY_WRLAT(TPHY_WRLAT_C), .TPHY_WRDATA(0) )
    u_ddr3_phy_inst (
        .clk_i(clk_phy_sys), .clk_ddr_i(clk_phy_ddr), .clk_ddr90_i(clk_phy_ddr90), .clk_ref_i(clk_idelay_ref),
        .rst_i(sys_rst_fsm_phy), .cfg_valid_i(1'b0), .cfg_i(32'd0),
        .dfi_address_i(dfi_address_s[14:0]), // PHY dfi_address_i is 15 bits wide
        .dfi_bank_i(dfi_bank_s), .dfi_cas_n_i(dfi_cas_n_s),
        .dfi_cke_i(dfi_cke_s), .dfi_cs_n_i(dfi_cs_n_s), .dfi_odt_i(dfi_odt_s),
        .dfi_ras_n_i(dfi_ras_n_s), .dfi_reset_n_i(dfi_reset_n_s), .dfi_we_n_i(dfi_we_n_s),
        .dfi_wrdata_i(dfi_wrdata_s), .dfi_wrdata_en_i(dfi_wrdata_en_s), 
        .dfi_wrdata_mask_i(dfi_wrdata_mask_s), // PHY dfi_wrdata_mask_i is 4 bits
        .dfi_rddata_en_i(dfi_rddata_en_s), .dfi_rddata_o(dfi_rddata_r),
        .dfi_rddata_valid_o(dfi_rddata_valid_r), .dfi_rddata_dnv_o(dfi_rddata_dnv_r),
        .ddr3_ck_p_o(ddr3_ck_p_o[0]), .ddr3_ck_n_o(ddr3_ck_n_o[0]), .ddr3_cke_o(ddr3_cke_o[0]),
        .ddr3_reset_n_o(ddr3_reset_n_o), .ddr3_ras_n_o(ddr3_ras_n_o), .ddr3_cas_n_o(ddr3_cas_n_o),
        .ddr3_we_n_o(ddr3_we_n_o), .ddr3_cs_n_o(ddr3_cs_n_o[0]), .ddr3_ba_o(ddr3_ba_o),
        .ddr3_addr_o(ddr3_addr_o), .ddr3_odt_o(ddr3_odt_o[0]), .ddr3_dm_o(ddr3_dm_o),
        .ddr3_dqs_p_io(ddr3_dqs_p_io), .ddr3_dqs_n_io(ddr3_dqs_n_io), .ddr3_dq_io(ddr3_dq_io)
    );

    // --- Controller FSM ---
    typedef enum logic [5:0] {
        S_IDLE, S_INIT_START_RESET, S_INIT_WAIT_POWER_ON, S_INIT_DEASSERT_RESET, S_INIT_CKE_HIGH_WAIT,
        S_INIT_CMD_PREA, S_INIT_CMD_EMR2, S_INIT_CMD_EMR3, S_INIT_CMD_EMR1, S_INIT_CMD_MR0_DLL_RESET, S_INIT_CMD_ZQCL, S_INIT_WAIT_TZQOPER, S_INIT_CMD_MR0_FINAL, S_INIT_WAIT_DLLK,
        S_ACT_WR, S_WR_CMD, S_WR_DATA_WAIT, S_DECAY_WAIT_PERIOD,
        S_ACT_RD, S_RD_CMD, S_RD_DATA_WAIT, S_RD_DATA_CAPTURE,
        S_UART_SETUP_CHAR, S_UART_WAIT_TX_DONE, S_DONE
    } state_t;
    state_t current_state_q, next_state_s;

    localparam T_POWER_ON_RESET_200US_CYCLES = 24'd40_000; // Min 200us RESET# low after VDD stable
    localparam T_STAB_500US_CYCLES           = 24'd100_000; // Min 500us CKE high & NOPs before first MRS
    localparam T_XPR_CYCLES                  = 24'd100;     // Max(5*tCK, tRFC+10ns), simplified for ZQCL/MRS after PREA
    localparam T_MRD_CYCLES                  = 24'd4;       // Mode Register Set command period (min 4 tCK)
    localparam T_MOD_CYCLES                  = 24'd12;      // Min 12 tCK or 15ns (MRS to non-MRS command)
    localparam T_ZQINIT_CYCLES               = 24'd512;     // ZQ Init Calibration time (min 512 tCK)
    localparam T_ZQOPER_CYCLES               = 24'd256;     // ZQ Long Calibration time (tZQCL, min 256 tCK)
    localparam T_DLLK_CYCLES                 = 24'd512;     // DLL Lock time
    localparam T_DECAY_10MS_CYCLES           = 24'd2_000_000;
    localparam T_RP_CYCLES                   = 24'd3;       // 13.75ns / 5ns -> 3 (for -125 speed grade [cite: 6])
    localparam T_RCD_CYCLES                  = 24'd3;       // 13.75ns / 5ns -> 3 [cite: 6]
    localparam TOTAL_RD_LAT_CYCLES           = TPHY_RDLAT_C + CAS_LATENCY_C + 3; // +3 margin

    logic [23:0] timer_q, timer_s;
    logic [13:0] test_addr_row_s_ddr; // For actual DDR A[13:0]
    logic [9:0]  test_addr_col_s_ddr; // For actual DDR A[9:0]
    logic [2:0]  test_bank_s_ddr;

    logic [31:0] data_to_write_q, data_read_q;
    logic        data_match_r;

    logic uart_tx_start_from_fsm_s;
    logic [7:0] uart_tx_data_from_fsm_s;
    logic uart_tx_busy_raw_from_uart;    // From UART module (100MHz domain)
    logic uart_tx_done_raw_from_uart;    // From UART module (100MHz domain)
    
    logic tx_done_flag_clk_phy_sys_q;      
    logic clear_tx_done_flag_s;            
    logic uart_tx_busy_sync0_clk_phy_sys, uart_tx_busy_sync1_clk_phy_sys; 

    typedef enum logic [1:0] {UART_MSG_NONE, UART_MSG_WR_DATA, UART_MSG_RD_DATA, UART_MSG_RESULT} uart_msg_type_t;
    uart_msg_type_t uart_current_msg_q, uart_current_msg_s;
    logic [3:0] uart_char_idx_q, uart_char_idx_s;

    logic start_cmd_edge_s;
    logic start_btn_phy_sync_0, start_btn_phy_sync_1, start_btn_phy_prev_q;

    // --- CDC Logic for UART Signals ---
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) tx_done_flag_clk_phy_sys_q <= 1'b0;
        else if (clear_tx_done_flag_s) tx_done_flag_clk_phy_sys_q <= 1'b0;
        else if (uart_tx_done_raw_from_uart) tx_done_flag_clk_phy_sys_q <= 1'b1;
    end

    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) {uart_tx_busy_sync0_clk_phy_sys, uart_tx_busy_sync1_clk_phy_sys} <= 2'b11;
        else {uart_tx_busy_sync0_clk_phy_sys, uart_tx_busy_sync1_clk_phy_sys} <= {uart_tx_busy_raw_from_uart, uart_tx_busy_sync0_clk_phy_sys};
    end
    // --- End CDC Logic ---

    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) {start_btn_phy_sync_0, start_btn_phy_sync_1, start_btn_phy_prev_q} <= 3'b000;
        else {start_btn_phy_sync_0, start_btn_phy_sync_1, start_btn_phy_prev_q} <= {start_btn_i, start_btn_phy_sync_0, start_btn_phy_sync_1};
    end
    assign start_cmd_edge_s = start_btn_phy_sync_1 & ~start_btn_phy_prev_q;

    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q    <= S_IDLE; timer_q <= 24'd0; data_to_write_q <= 32'hCAFEF00D;
            data_read_q <= 32'd0; status_led0_o <= 1'b0; status_led1_o <= 1'b0; status_led2_o <= 1'b0;
            uart_char_idx_q <= 4'd0; uart_current_msg_q <= UART_MSG_NONE;
        end else begin
            current_state_q <= next_state_s; timer_q <= timer_s; uart_char_idx_q <= uart_char_idx_s;
            uart_current_msg_q <= uart_current_msg_s;
            if (current_state_q == S_RD_DATA_WAIT && next_state_s == S_RD_DATA_CAPTURE) data_read_q <= dfi_rddata_r;
            status_led0_o <= (current_state_q != S_IDLE && current_state_q != S_DONE);
            if (current_state_q == S_DONE) {status_led1_o, status_led2_o} <= {data_match_r, ~data_match_r};
            else if (next_state_s == S_IDLE) {status_led1_o, status_led2_o} <= 2'b00;
        end
    end

    always_comb begin
        logic current_msg_done_s; 
        next_state_s = current_state_q; timer_s = timer_q; data_match_r = (data_to_write_q == data_read_q);
        uart_char_idx_s = uart_char_idx_q; uart_current_msg_s = uart_current_msg_q;
        uart_tx_start_from_fsm_s = 1'b0; uart_tx_data_from_fsm_s  = 8'hx; 
        current_msg_done_s = 1'b0; clear_tx_done_flag_s = 1'b0;

        dfi_address_s = 15'd0; dfi_bank_s = 3'd0; dfi_cas_n_s = 1'b1; dfi_cke_s = 1'b1; 
        dfi_cs_n_s = 1'b1; dfi_odt_s = 1'b0; dfi_ras_n_s = 1'b1; dfi_reset_n_s = 1'b1; 
        dfi_we_n_s = 1'b1; dfi_wrdata_s = 32'd0; dfi_wrdata_en_s = 1'b0; 
        dfi_wrdata_mask_s = 4'hF; dfi_rddata_en_s = 1'b0;

        test_addr_row_s_ddr = 14'h001A; // A[13:0] for 128M16 [cite: 11]
        test_addr_col_s_ddr = 10'h00F;  // A[9:0] for 128M16 [cite: 11]
        test_bank_s_ddr     = 3'b001;

        // DFI address mapping (concatenating row/col as needed by specific commands)
        // For ACTIVATE: DFI address is row address
        // For READ/WRITE: DFI address is column address (A10 used for AutoPrecharge bit)
        // For MRS: DFI address provides op-code

        case (current_state_q)
            S_IDLE: begin
                dfi_cke_s = 1'b0; dfi_reset_n_s = 1'b0; // DFI_RESET_N to PHY, asserts physical DDR_RESET_N
                if (start_cmd_edge_s) begin next_state_s = S_INIT_START_RESET; timer_s = 24'd0; end
            end
            S_INIT_START_RESET: begin // Assert physical DDR_RESET_N for >200us (min is not specified clearly as just RESET# assertion time)
                                    // JEDEC Figure 20 (Power-up and Initialization Sequence) shows RESET# low while VDD ramps.
                                    // We assume VDD is stable, then assert RESET# for > 0ns (datasheet says asynch).
                                    // For safety, ensure CKE is low during RESET# and for some time after.
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b0; // This makes u_ddr3_phy_inst drive ddr3_reset_n_o LOW
                timer_s = timer_q + 1;
                if (timer_q >= T_POWER_ON_RESET_200US_CYCLES) begin // Hold reset for 200us for stability
                    next_state_s = S_INIT_DEASSERT_RESET; timer_s = 24'd0;
                end
            end
            S_INIT_DEASSERT_RESET: begin // De-assert physical DDR_RESET_N
                dfi_cke_s = 1'b0; // Keep CKE low
                dfi_reset_n_s = 1'b1; // De-asserts ddr3_reset_n_o
                timer_s = timer_q + 1;
                if (timer_q >= 10) begin // Small delay after RESET# high before CKE high (tXPR not strictly defined here but good practice)
                    next_state_s = S_INIT_CKE_HIGH_WAIT; timer_s = 24'd0;
                end
            end
            S_INIT_CKE_HIGH_WAIT: begin
                dfi_cke_s = 1'b1; dfi_cs_n_s = 1'b0; // NOPs, CKE now high. Wait tXPR (min 5tCK or tRFC+10ns) after reset release before first command.
                                                // Or more generally, tSTAB (500us in Micron Figure 7 [cite: 181])
                timer_s = timer_q + 1;
                if (timer_q >= T_STAB_500US_CYCLES) begin
                    next_state_s = S_INIT_CMD_PREA; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_PREA: begin
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0400; /*A10=1 for Precharge All*/
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b0; // PREA
                timer_s = timer_q + 1; 
                if (timer_q >= T_RP_CYCLES) begin
                    next_state_s = S_INIT_CMD_EMR2; timer_s = 24'd0; // tRP met, EMR2 needs tMRD after
                end
            end
            S_INIT_CMD_EMR2: begin // EMR2: RTT_WR (Dynamic ODT for writes). Default often 0 (Dynamic ODT off)
                                  // For simplicity, let's use 0 (Dynamic ODT for write disabled)
                timer_s = timer_q + 1; // Counting for tMRD
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0000; dfi_bank_s = 3'b010; // EMR2
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                    next_state_s = S_INIT_CMD_EMR3; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_EMR3: begin // EMR3: No specific settings critical for basic operation
                timer_s = timer_q + 1; // Counting for tMRD
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0000; dfi_bank_s = 3'b011; // EMR3
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                    next_state_s = S_INIT_CMD_EMR1; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_EMR1: begin // EMR1: DLL Enable (A0=0), Output Drive Strength (A1,A5), RTT_NOM (A2,A6,A9)
                                  // RTT_NOM: Arty has 40 Ohm discrete termination on DQS.
                                  // Effective RTT_NOM disabled (000) or RZQ/4 (010 for A9,A6,A2 -> 60 Ohm) is common.
                                  // Drive Strength: RZQ/6 (01 for A5,A1) -> 40 Ohm.
                timer_s = timer_q + 1; // Counting for tMRD
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; 
                    dfi_address_s = 15'b00000_00_0_01_0_00_0; // A0=0(DLL En), A1=0,A5=1 (RZQ/6 DrStr), A2,A6,A9=0(RTT_Nom dis)
                    dfi_bank_s = 3'b001; // EMR1
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                    next_state_s = S_INIT_CMD_MR0_DLL_RESET; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_MR0_DLL_RESET: begin // MR0: BL8 (A1,A0=00), CL=6 (A6,A5,A4=010), DLL Reset (A8=1)
                timer_s = timer_q + 1; // Counting for tMRD
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; 
                    dfi_address_s = 15'b0000_1_0_010_1_0_00_0; // CL=6 (010 at A6,A5,A4); A2=1 for WR=6; BL8 (00 at A1,A0); DLL_Reset (A8=1)
                                                              // WR (Write Recovery) A11,A10,A9. For DDR3-800 CL6, WR=6 (010).
                                                              // MR0 Bits: B=A0(BL0),B=A1(BL1),B=A2(CL0),R=A3(RBT),B=A4(CL1),B=A5(CL2),B=A6(CL3),R=A7(TM),W=A8(DLL),B=A9(WR0),B=A10(WR1),B=A11(WR2),R=A12(PD)
                                                              // CL = 6 -> A[6:4] = 010
                                                              // WR = 6 -> A[11:9] = 010
                                                              // Final: 15'b0_010_1_010_0_0_00_0  (Addr: A12 A11 A10 A9 A8 A7 A6 A5 A4 A3 A2 A1 A0)
                                                              // A12(PPD)=0, A[11:9](WR)=010 (WR=6), A8(DLL_RST)=1, A7(TM)=0, A[6:4](CL)=010 (CL=6), A3(RBT)=0(Seq), A2(BL_Chop)=0 (BL8), A[1:0](BL)=00 (BL8)
                    dfi_address_s = 15'b0_010_10010_0000; // Corrected MR0 for CL6, WR6, DLL Reset, BL8
                    dfi_bank_s = 3'b000; // MR0
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                    next_state_s = S_INIT_CMD_ZQCL; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_ZQCL: begin // ZQ Long Calibration (takes tZQoper)
                timer_s = timer_q + 1; // Wait tMOD before ZQCL
                if (timer_q >= T_MOD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0400; /*A10=1 for ZQCL during NOP*/
                    dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // ZQCL command
                    next_state_s = S_INIT_WAIT_TZQOPER; timer_s = 24'd0;
                end
            end
            S_INIT_WAIT_TZQOPER: begin // Wait tZQoper (min 256 tCK)
                timer_s = timer_q + 1;
                if (timer_q >= T_ZQOPER_CYCLES) begin
                    next_state_s = S_INIT_CMD_MR0_FINAL; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_MR0_FINAL: begin // MR0: Same as before but A8=0 (DLL not in reset)
                timer_s = timer_q + 1; // tMRD
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; 
                    dfi_address_s = 15'b0_010_00010_0000; // CL6, WR6, A8=0 (DLL active), BL8
                    dfi_bank_s = 3'b000; // MR0
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                    next_state_s = S_INIT_WAIT_DLLK; timer_s = 24'd0;
                end
            end
            S_INIT_WAIT_DLLK: begin // Wait for DLL to lock (tDLLK, min 512 tCK)
                timer_s = timer_q + 1;
                if (timer_q >= T_DLLK_CYCLES) begin
                    next_state_s = S_ACT_WR; timer_s = 24'd0;
                end
            end

            S_ACT_WR: begin
                dfi_address_s = {1'b0, test_addr_row_s_ddr}; // DFI addr is row for ACT
                dfi_bank_s    = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0; dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // ACT
                next_state_s = S_WR_CMD; timer_s = 24'd0;
            end
            S_WR_CMD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    dfi_address_s = {5'b0, test_addr_col_s_ddr}; // DFI addr is col for WR (A10=0)
                    dfi_bank_s    = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0; dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // WR
                    dfi_wrdata_s = data_to_write_q; dfi_wrdata_mask_s = 4'b0000; dfi_wrdata_en_s = 1'b1;
                    dfi_odt_s = 1'b1;
                    next_state_s = S_WR_DATA_WAIT; timer_s = 24'd0;
                end else begin // Keep ACT active
                    dfi_address_s = {1'b0, test_addr_row_s_ddr}; dfi_bank_s = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0; dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; 
                end
            end
            S_WR_DATA_WAIT: begin
                dfi_wrdata_en_s = 1'b0; dfi_odt_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TPHY_WRLAT_C + 4) begin 
                    next_state_s = S_DECAY_WAIT_PERIOD; timer_s = 24'd0;
                end
            end
            S_DECAY_WAIT_PERIOD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_DECAY_10MS_CYCLES) begin
                    next_state_s = S_ACT_RD; timer_s = 24'd0;
                end
            end
            S_ACT_RD: begin
                dfi_address_s = {1'b0, test_addr_row_s_ddr}; dfi_bank_s = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0; dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // ACT
                next_state_s = S_RD_CMD; timer_s = 24'd0;
            end
            S_RD_CMD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    dfi_address_s = {5'b0, test_addr_col_s_ddr}; dfi_bank_s = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0; dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b1; // RD
                    dfi_rddata_en_s = 1'b1;
                    next_state_s = S_RD_DATA_WAIT; timer_s = 24'd0;
                end else begin
                    dfi_address_s = {1'b0, test_addr_row_s_ddr}; dfi_bank_s = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0; dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; 
                end
            end
            S_RD_DATA_WAIT: begin
                dfi_rddata_en_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TOTAL_RD_LAT_CYCLES - 1 ) begin
                    if (dfi_rddata_valid_r) begin
                        next_state_s = S_RD_DATA_CAPTURE; timer_s = 24'd0;
                    end else if (timer_q >= TOTAL_RD_LAT_CYCLES + 10) begin 
                        $display("%t: Read data valid timeout!", $time);
                        uart_current_msg_s = UART_MSG_WR_DATA; uart_char_idx_s = 4'd0;
                        next_state_s = S_UART_SETUP_CHAR; timer_s = 24'd0;
                    end
                end
            end
            S_RD_DATA_CAPTURE: begin
                uart_current_msg_s = UART_MSG_WR_DATA; uart_char_idx_s = 4'd0;
                next_state_s = S_UART_SETUP_CHAR;
            end

            S_UART_SETUP_CHAR: begin
                logic [7:0] char_to_send_s; 
                logic last_char_for_msg_s; 
                last_char_for_msg_s = 1'b0; 

                case(uart_current_msg_q)
                    UART_MSG_WR_DATA: begin 
                        case(uart_char_idx_q) 
                            0: char_to_send_s = "W"; 1: char_to_send_s = ":"; 2: char_to_send_s = " ";
                            3,4,5,6,7,8,9,10: begin 
                                logic [3:0] nibble; 
                                nibble = (data_to_write_q >> ( ( (10-uart_char_idx_q)) * 4) ) & 4'hF;
                                if (nibble < 10) char_to_send_s = nibble + "0"; else char_to_send_s = nibble - 10 + "A";
                            end
                            11: begin char_to_send_s = " "; last_char_for_msg_s = 1'b1; end
                            default: begin char_to_send_s = "?"; last_char_for_msg_s = 1'b1; end 
                        endcase
                    end
                    UART_MSG_RD_DATA: begin 
                         case(uart_char_idx_q) 
                            0: char_to_send_s = "R"; 1: char_to_send_s = ":"; 2: char_to_send_s = " ";
                            3,4,5,6,7,8,9,10: begin 
                                logic [3:0] nibble; 
                                nibble = (data_read_q >> ( ( (10-uart_char_idx_q)) * 4) ) & 4'hF;
                                if (nibble < 10) char_to_send_s = nibble + "0"; else char_to_send_s = nibble - 10 + "A";
                            end
                            11: begin char_to_send_s = " "; last_char_for_msg_s = 1'b1; end
                            default: begin char_to_send_s = "?"; last_char_for_msg_s = 1'b1; end
                        endcase
                    end
                    UART_MSG_RESULT: begin 
                        case(uart_char_idx_q) 
                            0: char_to_send_s = "-"; 1: char_to_send_s = " ";
                            2: char_to_send_s = data_match_r ? "M" : "F"; 3: char_to_send_s = " ";
                            4: begin char_to_send_s = "\n"; last_char_for_msg_s = 1'b1; end
                            default: begin char_to_send_s = "?"; last_char_for_msg_s = 1'b1; end
                        endcase
                    end
                    default: begin char_to_send_s = "E"; last_char_for_msg_s = 1'b1; end 
                endcase

                if (!uart_tx_busy_sync1_clk_phy_sys) begin // Use synchronized busy signal
                    uart_tx_data_from_fsm_s = char_to_send_s;
                    uart_tx_start_from_fsm_s = 1'b1; 
                    next_state_s = S_UART_WAIT_TX_DONE;
                end
            end

            S_UART_WAIT_TX_DONE: begin
                uart_tx_start_from_fsm_s = 1'b0; 
                if (tx_done_flag_clk_phy_sys_q) begin // Use synchronized done flag
                    clear_tx_done_flag_s = 1'b1; // Clear the flag
                    uart_char_idx_s = uart_char_idx_q + 1; 
                    
                    case(uart_current_msg_q)
                        UART_MSG_WR_DATA: current_msg_done_s = (uart_char_idx_q == 11);
                        UART_MSG_RD_DATA: current_msg_done_s = (uart_char_idx_q == 11);
                        UART_MSG_RESULT:  current_msg_done_s = (uart_char_idx_q == 4);
                        default:          current_msg_done_s = 1'b1; 
                    endcase

                    if (current_msg_done_s) begin
                        uart_char_idx_s = 4'd0; 
                        case(uart_current_msg_q) 
                            UART_MSG_WR_DATA: uart_current_msg_s = UART_MSG_RD_DATA;
                            UART_MSG_RD_DATA: uart_current_msg_s = UART_MSG_RESULT;
                            UART_MSG_RESULT:  uart_current_msg_s = UART_MSG_NONE; 
                            default:          uart_current_msg_s = UART_MSG_NONE;
                        endcase
                        
                        if (uart_current_msg_q == UART_MSG_RESULT) begin 
                            next_state_s = S_DONE;
                        end else begin
                            next_state_s = S_UART_SETUP_CHAR; 
                        end
                    end else begin 
                        next_state_s = S_UART_SETUP_CHAR; 
                    end
                end
            end

            S_DONE: begin
                dfi_cke_s = 1'b0;
                if (start_cmd_edge_s) begin
                    next_state_s = S_INIT_START_RESET; timer_s = 24'd0;
                end
            end
            default: next_state_s = S_IDLE;
        endcase
    end

    // UART Instance (using your uart_tx.v)
    uart_tx u_uart_tx_inst (
        .clk(clk100mhz_i), 
        .rst(rst_for_uart), // This reset is synchronous to clk100mhz_i
        .tx_start(uart_tx_start_from_fsm_s), // Controlled by FSM (clk_phy_sys domain, but start is a pulse)
        .tx_data(uart_tx_data_from_fsm_s),   // Controlled by FSM (clk_phy_sys domain)
        .tx_serial(uart_txd_o), 
        .tx_busy(uart_tx_busy_raw_from_uart), // Raw signal from UART (100MHz domain)
        .tx_done(uart_tx_done_raw_from_uart)  // Raw signal from UART (100MHz domain)
    );
    assign status_led3_o = uart_tx_busy_raw_from_uart; // Show raw busy for UART activity

endmodule
