// ddr3_decay_test_top.sv
// Fully fixed version with proper DDR3 timing and refresh management
module ddr3_decay_test_top (
    input wire clk100mhz_i,      // Board clock 100MHz
    input wire reset_btn_i,      // Active high reset button for whole system
    input wire start_btn_i,      // Button to start the DDR3 test sequence

    // LEDs for status
    output logic status_led0_o,    // Test in progress / Idle
    output logic status_led1_o,    // Test success (data match)
    output logic status_led2_o,    // Test fail (data mismatch / decay)
    output logic status_led3_o,    // UART TX activity

    output logic uart_txd_o,        // UART TX pin

    // DDR3 Interface signals
    output logic [13:0] ddr3_addr_o,
    output logic [2:0]  ddr3_ba_o,
    output logic        ddr3_cas_n_o,
    output logic [0:0]  ddr3_cke_o,
    output logic [0:0]  ddr3_ck_n_o,
    output logic [0:0]  ddr3_ck_p_o,
    output logic [0:0]  ddr3_cs_n_o,
    output logic [1:0]  ddr3_dm_o,
    inout  wire [15:0]  ddr3_dq_io,
    inout  wire [1:0]   ddr3_dqs_n_io,
    inout  wire [1:0]   ddr3_dqs_p_io,
    output logic [0:0]  ddr3_odt_o,
    output logic        ddr3_ras_n_o,
    output logic        ddr3_reset_n_o,
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

    // MMCM instance
    clk_wiz_0 u_clk_wiz (
        .clk_phy_sys(clk_phy_sys),
        .clk_phy_ddr(clk_phy_ddr),
        .clk_phy_ddr90(clk_phy_ddr90),
        .clk_idelay_ref(clk_idelay_ref),
        .reset(reset_btn_i),
        .locked(mmcm_locked),
        .clk_in1(clk100mhz_i)
    );

    // Reset synchronizers
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
    localparam TPHY_RDLAT_C  = 4;
    localparam TPHY_WRLAT_C  = 3;

    logic [14:0] dfi_address_s;
    logic [2:0]  dfi_bank_s;
    logic        dfi_cas_n_s, dfi_cke_s, dfi_cs_n_s, dfi_odt_s, dfi_ras_n_s;
    logic        dfi_reset_n_s, dfi_we_n_s, dfi_wrdata_en_s, dfi_rddata_en_s;
    logic [31:0] dfi_wrdata_s, dfi_rddata_r;
    logic [3:0]  dfi_wrdata_mask_s;
    logic        dfi_rddata_valid_r;
    logic [1:0]  dfi_rddata_dnv_r;

    ddr3_dfi_phy #( 
        .REFCLK_FREQUENCY(200), 
        .DQS_TAP_DELAY_INIT(15), 
        .DQ_TAP_DELAY_INIT(1),
        .TPHY_RDLAT(TPHY_RDLAT_C), 
        .TPHY_WRLAT(TPHY_WRLAT_C), 
        .TPHY_WRDATA(0) 
    )
    u_ddr3_phy_inst (
        .clk_i(clk_phy_sys), 
        .clk_ddr_i(clk_phy_ddr), 
        .clk_ddr90_i(clk_phy_ddr90), 
        .clk_ref_i(clk_idelay_ref),
        .rst_i(sys_rst_fsm_phy), 
        .cfg_valid_i(1'b0), 
        .cfg_i(32'd0),
        .dfi_address_i(dfi_address_s[14:0]),
        .dfi_bank_i(dfi_bank_s), 
        .dfi_cas_n_i(dfi_cas_n_s),
        .dfi_cke_i(dfi_cke_s), 
        .dfi_cs_n_i(dfi_cs_n_s), 
        .dfi_odt_i(dfi_odt_s),
        .dfi_ras_n_i(dfi_ras_n_s), 
        .dfi_reset_n_i(dfi_reset_n_s), 
        .dfi_we_n_i(dfi_we_n_s),
        .dfi_wrdata_i(dfi_wrdata_s), 
        .dfi_wrdata_en_i(dfi_wrdata_en_s), 
        .dfi_wrdata_mask_i(dfi_wrdata_mask_s),
        .dfi_rddata_en_i(dfi_rddata_en_s), 
        .dfi_rddata_o(dfi_rddata_r),
        .dfi_rddata_valid_o(dfi_rddata_valid_r), 
        .dfi_rddata_dnv_o(dfi_rddata_dnv_r),
        .ddr3_ck_p_o(ddr3_ck_p_o[0]), 
        .ddr3_ck_n_o(ddr3_ck_n_o[0]), 
        .ddr3_cke_o(ddr3_cke_o[0]),
        .ddr3_reset_n_o(ddr3_reset_n_o), 
        .ddr3_ras_n_o(ddr3_ras_n_o), 
        .ddr3_cas_n_o(ddr3_cas_n_o),
        .ddr3_we_n_o(ddr3_we_n_o), 
        .ddr3_cs_n_o(ddr3_cs_n_o[0]), 
        .ddr3_ba_o(ddr3_ba_o),
        .ddr3_addr_o(ddr3_addr_o), 
        .ddr3_odt_o(ddr3_odt_o[0]), 
        .ddr3_dm_o(ddr3_dm_o),
        .ddr3_dqs_p_io(ddr3_dqs_p_io), 
        .ddr3_dqs_n_io(ddr3_dqs_n_io), 
        .ddr3_dq_io(ddr3_dq_io)
    );

    // --- Controller FSM ---
    typedef enum logic [6:0] {
        S_IDLE,
        // Initialization states
        S_INIT_START_RESET, S_INIT_WAIT_POWER_ON, S_INIT_DEASSERT_RESET, S_INIT_CKE_HIGH_WAIT,
        S_INIT_CMD_PREA, S_INIT_CMD_EMR2, S_INIT_CMD_EMR3, S_INIT_CMD_EMR1, S_INIT_CMD_MR0_DLL_RESET, 
        S_INIT_CMD_ZQCL, S_INIT_WAIT_TZQINIT, S_INIT_CMD_MR0_FINAL, S_INIT_WAIT_DLLK,
        // Refresh states
        S_REF_CMD, S_REF_WAIT,
        // Write states
        S_ACT_WR, S_WR_CMD_ISSUE, S_WAIT_TWR,
        S_PRECHARGE_WR_CMD, S_WAIT_TRP_WR,
        // Decay wait
        S_DECAY_WAIT_PERIOD,
        // Read states
        S_ACT_RD, S_RD_CMD_ISSUE, S_RD_DATA_WAIT, S_RD_DATA_CAPTURE,
        S_PRECHARGE_RD_CMD, S_WAIT_TRP_RD,
        // UART states
        S_UART_SETUP_CHAR, S_UART_WAIT_TX_DONE, S_DONE
    } state_t;
    state_t current_state_q, next_state_s;

    // Timing parameters (in 200MHz clock cycles, 5ns period)
    localparam T_POWER_ON_RESET_200US_CYCLES = 24'd40_000;
    localparam T_STAB_500US_CYCLES           = 24'd100_000;
    localparam T_MRD_CYCLES                  = 24'd4;      
    localparam T_MOD_CYCLES                  = 24'd12;     
    localparam T_ZQINIT_CYCLES               = 24'd512;    
    localparam T_DLLK_CYCLES                 = 24'd512;    
    localparam T_DECAY_10MS_CYCLES           = 24'd2_000_000; 
    localparam T_RP_SYS_CYCLES               = 24'd3;      
    localparam T_RCD_SYS_CYCLES              = 24'd3;      
    localparam T_WR_SYS_CYCLES               = 24'd6;      // Based on MR0 setting for tWR
    localparam T_RFC_CYCLES                  = 24'd32;     // tRFC for 2Gb device is ~160ns. 160ns/5ns = 32 cycles
    localparam T_REFI_CYCLES                 = 24'd1560;   // 7.8us refresh interval / 5ns = 1560 cycles
     
    localparam ACTUAL_TOTAL_RD_LAT_CYCLES    = TPHY_RDLAT_C; 

    logic [23:0] timer_q, timer_s;
    logic [23:0] refresh_timer_q; // Removed refresh_timer_s, direct update in always_ff
    logic        refresh_pending_q, refresh_pending_s; // refresh_pending_s is combinational, refresh_pending_q is registered
     
    logic [13:0] test_addr_row_s_ddr;
    logic [9:0]  test_addr_col_s_ddr;
    logic [2:0]  test_bank_s_ddr;

    logic [31:0] data_to_write_q, data_read_q;
    logic        data_match_r;

    // UART control signals
    logic uart_tx_start_pulse_s;
    logic [7:0] uart_tx_data_s;
     
    // UART signals for CDC
    logic uart_tx_busy_from_uart;
    logic uart_tx_done_from_uart;
    logic uart_tx_start_to_uart;
    logic [7:0] uart_tx_data_to_uart;
     
    // CDC for UART busy signal (100MHz -> 200MHz)
    logic uart_tx_busy_sync0, uart_tx_busy_sync1, uart_tx_busy_sync2;
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            uart_tx_busy_sync0 <= 1'b0;
            uart_tx_busy_sync1 <= 1'b0;
            uart_tx_busy_sync2 <= 1'b0;
        end else begin
            uart_tx_busy_sync0 <= uart_tx_busy_from_uart;
            uart_tx_busy_sync1 <= uart_tx_busy_sync0;
            uart_tx_busy_sync2 <= uart_tx_busy_sync1;
        end
    end
     
    // Edge detection for busy going low (transmission complete)
    logic uart_tx_done_edge;
    assign uart_tx_done_edge = uart_tx_busy_sync1 & ~uart_tx_busy_sync2; // Falling edge of busy

    // CDC for UART start and data (200MHz -> 100MHz)
    logic uart_cmd_req_200mhz;
    logic [7:0] uart_cmd_data_200mhz;
    logic uart_cmd_ack_100mhz;
    logic uart_cmd_ack_sync0, uart_cmd_ack_sync1, uart_cmd_ack_sync2;
     
    // Generate request in 200MHz domain
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            uart_cmd_req_200mhz <= 1'b0;
            uart_cmd_data_200mhz <= 8'h00;
        end else begin
            if (uart_tx_start_pulse_s && !uart_cmd_req_200mhz && !uart_cmd_ack_sync2) begin // Only send new req if old one is acked
                uart_cmd_req_200mhz <= 1'b1;
                uart_cmd_data_200mhz <= uart_tx_data_s;
            end else if (uart_cmd_ack_sync2) begin // Ack received, de-assert request
                uart_cmd_req_200mhz <= 1'b0;
            end
        end
    end
     
    // Sync request to 100MHz domain
    logic uart_cmd_req_sync0, uart_cmd_req_sync1, uart_cmd_req_sync2;
    always_ff @(posedge clk100mhz_i or posedge rst_for_uart) begin
        if (rst_for_uart) begin
            uart_cmd_req_sync0 <= 1'b0;
            uart_cmd_req_sync1 <= 1'b0;
            uart_cmd_req_sync2 <= 1'b0;
        end else begin
            uart_cmd_req_sync0 <= uart_cmd_req_200mhz;
            uart_cmd_req_sync1 <= uart_cmd_req_sync0;
            uart_cmd_req_sync2 <= uart_cmd_req_sync1;
        end
    end
     
    // Detect rising edge and capture data in 100MHz domain
    logic uart_cmd_req_edge;
    assign uart_cmd_req_edge = uart_cmd_req_sync2 & ~uart_cmd_req_sync1; // Rising edge of synced request
     
    always_ff @(posedge clk100mhz_i or posedge rst_for_uart) begin
        if (rst_for_uart) begin
            uart_tx_start_to_uart <= 1'b0;
            uart_tx_data_to_uart <= 8'h00;
            uart_cmd_ack_100mhz <= 1'b0;
        end else begin
            uart_tx_start_to_uart <= 1'b0; // Default to pulse
            uart_cmd_ack_100mhz   <= 1'b0; // Default ack low
            
            if (uart_cmd_req_edge) begin // New request from 200MHz domain
                if (!uart_tx_busy_from_uart) begin // Only if UART TX module is not busy
                    uart_tx_start_to_uart <= 1'b1;
                    uart_tx_data_to_uart  <= uart_cmd_data_200mhz; 
                    uart_cmd_ack_100mhz   <= 1'b1; // Acknowledge the request
                end
            end
        end
    end
     
    // Sync ack back to 200MHz domain
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            uart_cmd_ack_sync0 <= 1'b0;
            uart_cmd_ack_sync1 <= 1'b0;
            uart_cmd_ack_sync2 <= 1'b0;
        end else begin
            uart_cmd_ack_sync0 <= uart_cmd_ack_100mhz;
            uart_cmd_ack_sync1 <= uart_cmd_ack_sync0;
            uart_cmd_ack_sync2 <= uart_cmd_ack_sync1;
        end
    end

    typedef enum logic [1:0] {UART_MSG_NONE, UART_MSG_WR_DATA, UART_MSG_RD_DATA, UART_MSG_RESULT} uart_msg_type_t;
    uart_msg_type_t uart_current_msg_q, uart_current_msg_s;
    logic [3:0] uart_char_idx_q, uart_char_idx_s;

    logic start_cmd_edge_s;
    logic start_btn_phy_sync_0, start_btn_phy_sync_1, start_btn_phy_prev_q;

    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            start_btn_phy_sync_0 <= 1'b0;
            start_btn_phy_sync_1 <= 1'b0;
            start_btn_phy_prev_q <= 1'b0;
        end else begin
            start_btn_phy_sync_0 <= start_btn_i;
            start_btn_phy_sync_1 <= start_btn_phy_sync_0;
            start_btn_phy_prev_q <= start_btn_phy_sync_1;
        end
    end
    assign start_cmd_edge_s = start_btn_phy_sync_1 & ~start_btn_phy_prev_q;

    // Refresh timer logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            refresh_timer_q <= 24'd0;
            refresh_pending_q <= 1'b0; 
        end else begin
            // Only count refresh timer if FSM is in an operational state (past init)
            // and not currently handling a refresh or in reset.
            if (current_state_q > S_INIT_WAIT_DLLK && current_state_q < S_REF_CMD && ~sys_rst_fsm_phy) begin
                if (refresh_timer_q >= T_REFI_CYCLES - 1) begin
                    refresh_timer_q <= 24'd0;
                    if (!refresh_pending_q) begin // Set pending only if not already set (to avoid re-triggering before handled)
                        refresh_pending_q <= 1'b1; 
                    end
                end else begin
                    refresh_timer_q <= refresh_timer_q + 1;
                end
            end else if (current_state_q == S_IDLE || current_state_q < S_INIT_WAIT_DLLK) begin 
                 refresh_timer_q <= 24'd0; // Reset timer if in IDLE or during init
            end
            // refresh_pending_q is cleared by the main FSM's combinational logic when it decides to go to S_REF_CMD
        end
    end

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q    <= S_IDLE;
            timer_q            <= 24'd0;
            data_to_write_q    <= 32'hCAFEF00D;
            data_read_q        <= 32'd0;
            status_led0_o      <= 1'b0;
            status_led1_o      <= 1'b0;
            status_led2_o      <= 1'b0;
            uart_char_idx_q    <= 4'd0;
            uart_current_msg_q <= UART_MSG_NONE;
            // refresh_pending_q is reset in its own always_ff block
        end else begin
            current_state_q    <= next_state_s;
            timer_q            <= timer_s;
            uart_char_idx_q    <= uart_char_idx_s;
            uart_current_msg_q <= uart_current_msg_s;
            refresh_pending_q  <= refresh_pending_s; // Update registered refresh_pending from combinational logic
            
            // Capture read data only when valid and transitioning to CAPTURE state
            if (current_state_q == S_RD_DATA_WAIT && next_state_s == S_RD_DATA_CAPTURE && dfi_rddata_valid_r) begin
                data_read_q <= dfi_rddata_r;
                $display("%t: FSM Captured read data: %h", $time, dfi_rddata_r);
            end
            
            status_led0_o <= (current_state_q != S_IDLE && current_state_q != S_DONE);
            
            if (current_state_q == S_DONE) begin
                status_led1_o <= data_match_r;
                status_led2_o <= ~data_match_r;
            end else if (next_state_s == S_IDLE) begin
                status_led1_o <= 1'b0;
                status_led2_o <= 1'b0;
            end
        end
    end

    always_comb begin
        logic current_msg_done_s;
        logic [3:0] nibble_uart;
        
        next_state_s          = current_state_q;
        timer_s               = timer_q; 
        refresh_pending_s     = refresh_pending_q; // Default: keep current registered pending state

        data_match_r          = (data_to_write_q == data_read_q);
        uart_char_idx_s       = uart_char_idx_q;
        uart_current_msg_s    = uart_current_msg_q;
        uart_tx_start_pulse_s = 1'b0;
        uart_tx_data_s        = 8'hx;
        current_msg_done_s    = 1'b0;

        dfi_address_s       = 15'd0;
        dfi_bank_s          = 3'd0;
        dfi_cas_n_s         = 1'b1;
        dfi_cke_s           = 1'b1; 
        dfi_cs_n_s          = 1'b1;
        dfi_odt_s           = 1'b0;
        dfi_ras_n_s         = 1'b1;
        dfi_reset_n_s       = 1'b1; 
        dfi_we_n_s          = 1'b1;
        dfi_wrdata_s        = 32'd0;
        dfi_wrdata_en_s     = 1'b0;
        dfi_wrdata_mask_s   = 4'hF; 
        dfi_rddata_en_s     = 1'b0;

        test_addr_row_s_ddr = 14'h001A; 
        test_addr_col_s_ddr = 10'h00F; 
        test_bank_s_ddr     = 3'b001;  

        // Refresh Preemption Logic
        if (refresh_pending_q && 
            (current_state_q == S_DECAY_WAIT_PERIOD || current_state_q == S_ACT_WR || current_state_q == S_ACT_RD || current_state_q == S_DONE || current_state_q == S_IDLE)) begin // Add S_IDLE to allow refresh even if test not running
            if (current_state_q != S_REF_CMD && current_state_q != S_REF_WAIT) begin 
                next_state_s = S_REF_CMD;
                timer_s = 24'd0;
                refresh_pending_s = 1'b0; // Clear the pending flag as we are about to handle it
            end
        end else begin // Normal FSM operation
            case (current_state_q)
                S_IDLE: begin
                    dfi_cke_s       = 1'b0; 
                    dfi_reset_n_s   = 1'b0; 
                    if (start_cmd_edge_s) begin
                        next_state_s = S_INIT_START_RESET;
                        timer_s      = 24'd0;
                    end
                end
                
                S_INIT_START_RESET: begin 
                    dfi_cke_s     = 1'b0;
                    dfi_reset_n_s = 1'b0;
                    timer_s       = timer_q + 1;
                    if (timer_q >= T_POWER_ON_RESET_200US_CYCLES) begin
                        next_state_s = S_INIT_DEASSERT_RESET;
                        timer_s      = 24'd0;
                    end
                end
                
                S_INIT_DEASSERT_RESET: begin 
                    dfi_cke_s     = 1'b0;
                    dfi_reset_n_s = 1'b1;
                    timer_s       = timer_q + 1;
                    if (timer_q >= 2) begin // Min delay after reset deassertion
                        next_state_s = S_INIT_CKE_HIGH_WAIT;
                        timer_s      = 24'd0;
                    end
                end
                
                S_INIT_CKE_HIGH_WAIT: begin 
                    dfi_cke_s  = 1'b1;
                    dfi_cs_n_s = 1'b1; // NOPs or command inhibit
                    timer_s    = timer_q + 1;
                    if (timer_q >= T_STAB_500US_CYCLES) begin 
                        next_state_s = S_INIT_CMD_PREA;
                        timer_s      = 24'd0;
                    end
                end
                
                S_INIT_CMD_PREA: begin 
                    dfi_address_s = 15'h0400; // A10=1 for Precharge All
                    dfi_bank_s    = 3'b000;   // Bank is don"t care for PREA
                    dfi_cs_n_s    = 1'b0;
                    dfi_ras_n_s   = 1'b0;
                    dfi_cas_n_s   = 1'b1;
                    dfi_we_n_s    = 1'b0;
                    next_state_s  = S_INIT_CMD_EMR2; 
                    timer_s       = 24'd0; 
                end
                
                S_INIT_CMD_EMR2: begin 
                    timer_s = timer_q + 1; 
                    if (timer_q >= T_RP_SYS_CYCLES) begin  // Wait tRP before first MRS
                        // MR2: Set CWL. For CL=6, AL=0 => CWL=6 (A5-A3 = 010)
                        dfi_address_s = 15'b0000000000_010_000; 
                        dfi_bank_s    = 3'b010;   // BA[2:0] = 010 for MR2
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0;
                        dfi_cas_n_s   = 1'b0;
                        dfi_we_n_s    = 1'b0;
                        next_state_s  = S_INIT_CMD_EMR3;
                        timer_s       = 24'd0;
                    end
                end

                S_INIT_CMD_EMR3: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_MRD_CYCLES) begin
                        dfi_address_s = 15'h0000; // MR3: Default values (MPR disabled)
                        dfi_bank_s    = 3'b011;   // BA[2:0] = 011 for MR3
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0;
                        dfi_cas_n_s   = 1'b0;
                        dfi_we_n_s    = 1'b0;
                        next_state_s  = S_INIT_CMD_EMR1;
                        timer_s       = 24'd0;
                    end
                end
                
                S_INIT_CMD_EMR1: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_MRD_CYCLES) begin
                        // MR1: DLL Enable (A0=1), AL=0 (A4,A3=00), Output Drive RZQ/6 (A5=0,A1=1), RTT_Nom disabled
                        dfi_address_s = 15'b00000_00_0_00_0_01_1; 
                        dfi_bank_s    = 3'b001;   // BA[2:0] = 001 for MR1
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0;
                        dfi_cas_n_s   = 1'b0;
                        dfi_we_n_s    = 1'b0;
                        next_state_s  = S_INIT_CMD_MR0_DLL_RESET;
                        timer_s       = 24'd0;
                    end
                end

                S_INIT_CMD_MR0_DLL_RESET: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_MRD_CYCLES) begin
                        // MR0: CL=6 (A6,A5,A4,A2 = 0100), tWR=6 (A11,A10,A9 = 010), DLL_RST=1, BL8 (A1,A0=00)
                        dfi_address_s = 15'b0_010_1_0_010_0_0_00; 
                        dfi_bank_s    = 3'b000;   // BA[2:0] = 000 for MR0
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0;
                        dfi_cas_n_s   = 1'b0;
                        dfi_we_n_s    = 1'b0;
                        next_state_s  = S_INIT_CMD_ZQCL;
                        timer_s       = 24'd0;
                    end
                end
                
                S_INIT_CMD_ZQCL: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_MOD_CYCLES) begin 
                        dfi_address_s = 15'h0400; // A10=1 for ZQCL command
                        dfi_bank_s    = 3'b000;   // Bank for ZQCL is 000
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0; 
                        dfi_cas_n_s   = 1'b0; 
                        dfi_we_n_s    = 1'b0; 
                        next_state_s  = S_INIT_WAIT_TZQINIT; 
                        timer_s       = 24'd0;
                    end
                end
                
                S_INIT_WAIT_TZQINIT: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_ZQINIT_CYCLES) begin
                        next_state_s = S_INIT_CMD_MR0_FINAL;
                        timer_s      = 24'd0;
                    end
                end
                
                S_INIT_CMD_MR0_FINAL: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_MRD_CYCLES) begin 
                        // MR0: CL=6, tWR=6, DLL_RST=0 (Normal Op), BL8
                        dfi_address_s = 15'b0_010_0_0_010_0_0_00; 
                        dfi_bank_s    = 3'b000;
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0;
                        dfi_cas_n_s   = 1'b0;
                        dfi_we_n_s    = 1'b0;
                        next_state_s  = S_INIT_WAIT_DLLK;
                        timer_s       = 24'd0;
                    end
                end
                
                S_INIT_WAIT_DLLK: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_DLLK_CYCLES) begin
                        next_state_s = S_ACT_WR; 
                        timer_s      = 24'd0;
                        // refresh_timer_s is reset in its own block based on sys_rst_fsm_phy
                    end
                end

                S_REF_CMD: begin
                    dfi_address_s = 15'd0; 
                    dfi_bank_s    = 3'd0;
                    dfi_cs_n_s    = 1'b0;
                    dfi_ras_n_s   = 1'b0;
                    dfi_cas_n_s   = 1'b0;
                    dfi_we_n_s    = 1'b1; 
                    next_state_s  = S_REF_WAIT;
                    timer_s       = 24'd0;
                    refresh_pending_s = 1'b0; // Refresh is being handled
                end

                S_REF_WAIT: begin
                    timer_s = timer_q + 1;
                    if (timer_q >= T_RFC_CYCLES) begin
                        next_state_s = S_ACT_WR; // Resume normal operation, e.g., by trying a write
                        timer_s      = 24'd0;
                    end
                end

                S_ACT_WR: begin
                    dfi_address_s = {1'b0, test_addr_row_s_ddr}; 
                    dfi_bank_s    = test_bank_s_ddr;
                    dfi_cs_n_s    = 1'b0;
                    dfi_ras_n_s   = 1'b0;
                    dfi_cas_n_s   = 1'b1;
                    dfi_we_n_s    = 1'b1;
                    next_state_s  = S_WR_CMD_ISSUE;
                    timer_s       = 24'd0;
                end
                
                S_WR_CMD_ISSUE: begin
                    timer_s = timer_q + 1;
                    if (timer_q >= T_RCD_SYS_CYCLES) begin
                        dfi_address_s     = {1'b0, 1'b0, 1'b0, test_addr_col_s_ddr[9:0], 2'b00}; // A12(BC)=0, A10(AP)=0
                        dfi_bank_s        = test_bank_s_ddr;
                        dfi_cs_n_s        = 1'b0;
                        dfi_ras_n_s       = 1'b1;
                        dfi_cas_n_s       = 1'b0;
                        dfi_we_n_s        = 1'b0;
                        
                        dfi_wrdata_s      = data_to_write_q; 
                        dfi_wrdata_mask_s = 4'b0000;         
                        dfi_wrdata_en_s   = 1'b1;            
                        dfi_odt_s         = 1'b1;            
                        
                        next_state_s      = S_WAIT_TWR; 
                        timer_s           = 24'd0;
                    end else begin 
                        dfi_address_s = {1'b0, test_addr_row_s_ddr}; 
                        dfi_bank_s    = test_bank_s_ddr; 
                        dfi_cs_n_s    = 1'b0;   
                        dfi_ras_n_s   = 1'b0;   
                        dfi_cas_n_s   = 1'b1;
                        dfi_we_n_s    = 1'b1;
                    end
                end

                S_WAIT_TWR: begin
                    dfi_wrdata_en_s = 1'b0; 
                    dfi_odt_s       = 1'b0; 
                    timer_s         = timer_q + 1;
                    if (timer_q >= T_WR_SYS_CYCLES) begin  
                        next_state_s = S_PRECHARGE_WR_CMD;
                        timer_s      = 24'd0;
                    end
                end

                S_PRECHARGE_WR_CMD: begin
                    dfi_address_s     = 15'h0; 
                    dfi_address_s[10] = 1'b0;    // A10=0 for Precharge selected bank
                    dfi_bank_s        = test_bank_s_ddr;
                    dfi_cs_n_s        = 1'b0;
                    dfi_ras_n_s       = 1'b0;
                    dfi_cas_n_s       = 1'b1;
                    dfi_we_n_s        = 1'b0;
                    next_state_s      = S_WAIT_TRP_WR;
                    timer_s           = 24'd0;
                end

                S_WAIT_TRP_WR: begin
                    timer_s = timer_q + 1;
                    if (timer_q >= T_RP_SYS_CYCLES) begin 
                        next_state_s = S_DECAY_WAIT_PERIOD;
                        timer_s      = 24'd0;
                    end
                end
                
                S_DECAY_WAIT_PERIOD: begin
                    timer_s = timer_q + 1;
                    if (timer_q >= T_DECAY_10MS_CYCLES) begin 
                        next_state_s = S_ACT_RD;
                        timer_s      = 24'd0;
                    end
                end
                
                S_ACT_RD: begin
                    dfi_cke_s     = 1'b1; 
                    dfi_address_s = {1'b0, test_addr_row_s_ddr};
                    dfi_bank_s    = test_bank_s_ddr;
                    dfi_cs_n_s    = 1'b0;
                    dfi_ras_n_s   = 1'b0;
                    dfi_cas_n_s   = 1'b1;
                    dfi_we_n_s    = 1'b1;
                    next_state_s  = S_RD_CMD_ISSUE;
                    timer_s       = 24'd0;
                end
                
                S_RD_CMD_ISSUE: begin
                    timer_s = timer_q + 1;
                    if (timer_q >= T_RCD_SYS_CYCLES) begin
                        dfi_address_s   = {1'b0, 1'b0, 1'b0, test_addr_col_s_ddr[9:0], 2'b00}; // A12(BC)=0, A10(AP)=0
                        dfi_bank_s      = test_bank_s_ddr;
                        dfi_cs_n_s      = 1'b0;
                        dfi_ras_n_s     = 1'b1;
                        dfi_cas_n_s     = 1'b0;
                        dfi_we_n_s      = 1'b1;
                        dfi_rddata_en_s = 1'b1; 
                        next_state_s    = S_RD_DATA_WAIT;
                        timer_s         = 24'd0;
                    end else begin 
                        dfi_address_s = {1'b0, test_addr_row_s_ddr};
                        dfi_bank_s    = test_bank_s_ddr;
                        dfi_cs_n_s    = 1'b0;
                        dfi_ras_n_s   = 1'b0;
                        dfi_cas_n_s   = 1'b1;
                        dfi_we_n_s    = 1'b1;
                    end
                end

                S_RD_DATA_WAIT: begin
                    dfi_rddata_en_s = 1'b0; 
                    timer_s         = timer_q + 1;
                    if (timer_q >= (ACTUAL_TOTAL_RD_LAT_CYCLES - 1)) begin 
                        if (dfi_rddata_valid_r) begin
                            next_state_s = S_RD_DATA_CAPTURE;
                            timer_s      = 24'd0;
                        } else if (timer_q >= (ACTUAL_TOTAL_RD_LAT_CYCLES + 10)) begin 
                            $display("%t: FSM Read data valid timeout! PHY Read Data Reg: %h", $time, dfi_rddata_r);
                            next_state_s = S_RD_DATA_CAPTURE; 
                            timer_s      = 24'd0;
                        end
                    end
                end

                S_RD_DATA_CAPTURE: begin
                    next_state_s       = S_PRECHARGE_RD_CMD; 
                    timer_s            = 24'd0;
                end

                S_PRECHARGE_RD_CMD: begin 
                    dfi_address_s     = 15'h0;
                    dfi_address_s[10] = 1'b0;    
                    dfi_bank_s        = test_bank_s_ddr;
                    dfi_cs_n_s        = 1'b0;
                    dfi_ras_n_s       = 1'b0;
                    dfi_cas_n_s       = 1'b1;
                    dfi_we_n_s        = 1'b0;
                    next_state_s      = S_WAIT_TRP_RD; 
                    timer_s           = 24'd0;
                end

                S_WAIT_TRP_RD: begin 
                    timer_s = timer_q + 1;
                    if (timer_q >= T_RP_SYS_CYCLES) begin
                        uart_current_msg_s = UART_MSG_WR_DATA; 
                        uart_char_idx_s    = 4'd0;
                        next_state_s       = S_UART_SETUP_CHAR;
                        timer_s            = 24'd0;
                    end
                end
                
                S_UART_SETUP_CHAR: begin
                    logic [7:0] char_to_send_s_local; 
                    logic last_char_for_msg_s_local;
                    last_char_for_msg_s_local = 1'b0;
                    char_to_send_s_local = "?"; 

                    case(uart_current_msg_q)
                        UART_MSG_WR_DATA: begin
                            case(uart_char_idx_q)
                                0: begin char_to_send_s_local = "W"; end
                                1: begin char_to_send_s_local = ":"; end
                                2: begin char_to_send_s_local = " "; end
                                3,4,5,6,7,8,9,10: begin
                                    nibble_uart = (data_to_write_q >> ((10-uart_char_idx_q) * 4)) & 4'hF;
                                    if (nibble_uart < 10) char_to_send_s_local = nibble_uart + "0"; else char_to_send_s_local = nibble_uart - 10 + "A";
                                end
                                11: begin char_to_send_s_local = " "; last_char_for_msg_s_local = 1'b1; end
                                default: begin char_to_send_s_local = "?"; last_char_for_msg_s_local = 1'b1; end
                            endcase
                        end 
                        UART_MSG_RD_DATA: begin
                             case(uart_char_idx_q)
                                0: begin char_to_send_s_local = "R"; end
                                1: begin char_to_send_s_local = ":"; end
                                2: begin char_to_send_s_local = " "; end
                                3,4,5,6,7,8,9,10: begin
                                    nibble_uart = (data_read_q >> ((10-uart_char_idx_q) * 4)) & 4'hF;
                                    if (nibble_uart < 10) char_to_send_s_local = nibble_uart + "0"; else char_to_send_s_local = nibble_uart - 10 + "A";
                                end
                                11: begin char_to_send_s_local = " "; last_char_for_msg_s_local = 1'b1; end
                                default: begin char_to_send_s_local = "?"; last_char_for_msg_s_local = 1'b1; end
                            endcase
                        end 
                        UART_MSG_RESULT: begin
                            case(uart_char_idx_q)
                                0: begin char_to_send_s_local = "-"; end
                                1: begin char_to_send_s_local = " "; end
                                2: begin char_to_send_s_local = data_match_r ? "M" : "F"; end
                                3: begin char_to_send_s_local = " "; end
                                4: begin char_to_send_s_local = "\n"; last_char_for_msg_s_local = 1'b1; end
                                default: begin char_to_send_s_local = "?"; last_char_for_msg_s_local = 1'b1; end
                            endcase
                        end 
                        default: begin 
                            char_to_send_s_local = "E"; 
                            last_char_for_msg_s_local = 1'b1; 
                        end
                    endcase 

                    if (!uart_cmd_req_200mhz && !uart_tx_busy_sync1 && !uart_cmd_ack_sync2 ) begin 
                        uart_tx_data_s = char_to_send_s_local;
                        uart_tx_start_pulse_s = 1'b1;
                        next_state_s = S_UART_WAIT_TX_DONE;
                        
                        if (last_char_for_msg_s_local) begin
                            uart_char_idx_s = 4'd0;
                            case(uart_current_msg_q)
                                UART_MSG_WR_DATA: uart_current_msg_s = UART_MSG_RD_DATA;
                                UART_MSG_RD_DATA: uart_current_msg_s = UART_MSG_RESULT;
                                UART_MSG_RESULT:  uart_current_msg_s = UART_MSG_NONE;
                                default:          uart_current_msg_s = UART_MSG_NONE;
                            endcase
                        end else begin
                            uart_char_idx_s = uart_char_idx_q + 1;
                        end
                    end
                end 

                S_UART_WAIT_TX_DONE: begin
                    if (uart_tx_done_edge) begin 
                        if (uart_current_msg_s == UART_MSG_NONE) begin 
                            next_state_s = S_DONE;
                        end else begin
                            next_state_s = S_UART_SETUP_CHAR;
                        end
                    end
                end

                S_DONE: begin
                    dfi_cke_s = 1'b0; 
                    if (start_cmd_edge_s) begin 
                        next_state_s = S_INIT_START_RESET; 
                        timer_s      = 24'd0;
                    end
                end
                
                default: next_state_s = S_IDLE;
            endcase // End case(current_state_q)
        end // End normal operation (else of refresh_needed_s)
    end // End always_comb

    uart_tx #(
        .CLKS_PER_BIT(868)  
    ) u_uart_tx_inst (
        .clk(clk100mhz_i),
        .rst(rst_for_uart),
        .tx_start(uart_tx_start_to_uart),
        .tx_data(uart_tx_data_to_uart),
        .tx_serial(uart_txd_o),
        .tx_busy(uart_tx_busy_from_uart),
        .tx_done(uart_tx_done_from_uart) 
    );
     
    assign status_led3_o = uart_tx_busy_from_uart; 

endmodule

