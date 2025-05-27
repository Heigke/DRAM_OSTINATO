// ddr3_decay_test_top.sv
// Fixed version with proper CDC for UART signals
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
    localparam CAS_LATENCY_C = 6;

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
    typedef enum logic [5:0] {
        S_IDLE, S_INIT_START_RESET, S_INIT_WAIT_POWER_ON, S_INIT_DEASSERT_RESET, S_INIT_CKE_HIGH_WAIT,
        S_INIT_CMD_PREA, S_INIT_CMD_EMR2, S_INIT_CMD_EMR3, S_INIT_CMD_EMR1, S_INIT_CMD_MR0_DLL_RESET, 
        S_INIT_CMD_ZQCL, S_INIT_WAIT_TZQOPER, S_INIT_CMD_MR0_FINAL, S_INIT_WAIT_DLLK,
        S_ACT_WR, S_WR_CMD, S_WR_DATA_WAIT, S_DECAY_WAIT_PERIOD,
        S_ACT_RD, S_RD_CMD, S_RD_DATA_WAIT, S_RD_DATA_CAPTURE,
        S_UART_SETUP_CHAR, S_UART_WAIT_TX_DONE, S_DONE
    } state_t;
    state_t current_state_q, next_state_s;

    // Timing parameters
    localparam T_POWER_ON_RESET_200US_CYCLES = 24'd40_000;
    localparam T_STAB_500US_CYCLES           = 24'd100_000;
    localparam T_XPR_CYCLES                  = 24'd100;
    localparam T_MRD_CYCLES                  = 24'd4;
    localparam T_MOD_CYCLES                  = 24'd12;
    localparam T_ZQINIT_CYCLES               = 24'd512;
    localparam T_ZQOPER_CYCLES               = 24'd256;
    localparam T_DLLK_CYCLES                 = 24'd512;
    //localparam T_DECAY_10MS_CYCLES           = 24'd2_000_000;
    localparam T_DECAY_10MS_CYCLES = 24'd20_000;  // 100μs = 20,000 cycles
    localparam T_RP_CYCLES                   = 24'd3;
    localparam T_RCD_CYCLES                  = 24'd3;
    localparam TOTAL_RD_LAT_CYCLES           = TPHY_RDLAT_C + CAS_LATENCY_C + 3;

    logic [23:0] timer_q, timer_s;
    logic [13:0] test_addr_row_s_ddr;
    logic [9:0]  test_addr_col_s_ddr;
    logic [2:0]  test_bank_s_ddr;

    logic [31:0] data_to_write_q, data_read_q;
    logic        data_match_r;

    // UART control signals in FSM domain (200MHz)
    logic uart_tx_start_pulse_s;
    logic [7:0] uart_tx_data_s;
    
    // UART signals for CDC
    logic uart_tx_busy_from_uart;     // From UART (100MHz domain)
    logic uart_tx_done_from_uart;     // From UART (100MHz domain)
    logic uart_tx_start_to_uart;      // To UART (100MHz domain)
    logic [7:0] uart_tx_data_to_uart; // To UART (100MHz domain)
    
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
    assign uart_tx_done_edge = uart_tx_busy_sync2 & ~uart_tx_busy_sync1;

    // CDC for UART start and data (200MHz -> 100MHz)
    // We'll use a simple handshake mechanism
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
            if (uart_tx_start_pulse_s && !uart_cmd_req_200mhz) begin
                uart_cmd_req_200mhz <= 1'b1;
                uart_cmd_data_200mhz <= uart_tx_data_s;
            end else if (uart_cmd_ack_sync2) begin
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
    assign uart_cmd_req_edge = uart_cmd_req_sync1 & ~uart_cmd_req_sync2;
    
    always_ff @(posedge clk100mhz_i or posedge rst_for_uart) begin
        if (rst_for_uart) begin
            uart_tx_start_to_uart <= 1'b0;
            uart_tx_data_to_uart <= 8'h00;
            uart_cmd_ack_100mhz <= 1'b0;
        end else begin
            uart_tx_start_to_uart <= 1'b0; // Default
            
            if (uart_cmd_req_edge) begin
                uart_tx_start_to_uart <= 1'b1;
                uart_tx_data_to_uart <= uart_cmd_data_200mhz; // This is relatively safe as data is stable
                uart_cmd_ack_100mhz <= 1'b1;
            end else if (!uart_cmd_req_sync1) begin
                uart_cmd_ack_100mhz <= 1'b0;
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

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q    <= S_IDLE;
            timer_q           <= 24'd0;
            data_to_write_q   <= 32'hCAFEF00D;
            data_read_q       <= 32'd0;
            status_led0_o     <= 1'b0;
            status_led1_o     <= 1'b0;
            status_led2_o     <= 1'b0;
            uart_char_idx_q   <= 4'd0;
            uart_current_msg_q <= UART_MSG_NONE;
        end else begin
            current_state_q <= next_state_s;
            timer_q <= timer_s;
            uart_char_idx_q <= uart_char_idx_s;
            uart_current_msg_q <= uart_current_msg_s;
            
            if (current_state_q == S_RD_DATA_WAIT && next_state_s == S_RD_DATA_CAPTURE) begin
                data_read_q <= dfi_rddata_r;
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

    // State machine combinational logic
    always_comb begin
        logic current_msg_done_s;
        
        // Default assignments
        next_state_s = current_state_q;
        timer_s = timer_q;
        data_match_r = (data_to_write_q == data_read_q);
        uart_char_idx_s = uart_char_idx_q;
        uart_current_msg_s = uart_current_msg_q;
        uart_tx_start_pulse_s = 1'b0;
        uart_tx_data_s = 8'hx;
        current_msg_done_s = 1'b0;

        // Default DFI signals
        dfi_address_s = 15'd0;
        dfi_bank_s = 3'd0;
        dfi_cas_n_s = 1'b1;
        dfi_cke_s = 1'b1;
        dfi_cs_n_s = 1'b1;
        dfi_odt_s = 1'b0;
        dfi_ras_n_s = 1'b1;
        dfi_reset_n_s = 1'b1;
        dfi_we_n_s = 1'b1;
        dfi_wrdata_s = 32'd0;
        dfi_wrdata_en_s = 1'b0;
        dfi_wrdata_mask_s = 4'hF;
        dfi_rddata_en_s = 1'b0;

        test_addr_row_s_ddr = 14'h001A;
        test_addr_col_s_ddr = 10'h00F;
        test_bank_s_ddr     = 3'b001;

        case (current_state_q)
            S_IDLE: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b0;
                if (start_cmd_edge_s) begin
                    next_state_s = S_INIT_START_RESET;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_START_RESET: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= T_POWER_ON_RESET_200US_CYCLES) begin
                    next_state_s = S_INIT_DEASSERT_RESET;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_DEASSERT_RESET: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b1;
                timer_s = timer_q + 1;
                if (timer_q >= 10) begin
                    next_state_s = S_INIT_CKE_HIGH_WAIT;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CKE_HIGH_WAIT: begin
                dfi_cke_s = 1'b1;
                dfi_cs_n_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= T_STAB_500US_CYCLES) begin
                    next_state_s = S_INIT_CMD_PREA;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_PREA: begin
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0400; // A10=1 for Precharge All
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= T_RP_CYCLES) begin
                    next_state_s = S_INIT_CMD_EMR2;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_EMR2: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0;
                    dfi_address_s = 15'h0000;
                    dfi_bank_s = 3'b010;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b0;
                    next_state_s = S_INIT_CMD_EMR3;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_EMR3: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0;
                    dfi_address_s = 15'h0000;
                    dfi_bank_s = 3'b011;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b0;
                    next_state_s = S_INIT_CMD_EMR1;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_EMR1: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0;
                    dfi_address_s = 15'b00000_00_0_01_0_00_0; // DLL Enable, Drive Strength RZQ/6
                    dfi_bank_s = 3'b001;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b0;
                    next_state_s = S_INIT_CMD_MR0_DLL_RESET;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_MR0_DLL_RESET: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0;
                    dfi_address_s = 15'b0_010_10010_0000; // CL6, WR6, DLL Reset, BL8
                    dfi_bank_s = 3'b000;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b0;
                    next_state_s = S_INIT_CMD_ZQCL;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_ZQCL: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MOD_CYCLES) begin
                    dfi_cs_n_s = 1'b0;
                    dfi_address_s = 15'h0400; // A10=1 for ZQCL
                    dfi_ras_n_s = 1'b1;
                    dfi_cas_n_s = 1'b1;
                    dfi_we_n_s = 1'b1;
                    next_state_s = S_INIT_WAIT_TZQOPER;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_WAIT_TZQOPER: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_ZQOPER_CYCLES) begin
                    next_state_s = S_INIT_CMD_MR0_FINAL;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_MR0_FINAL: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    dfi_cs_n_s = 1'b0;
                    dfi_address_s = 15'b0_010_00010_0000; // CL6, WR6, DLL active, BL8
                    dfi_bank_s = 3'b000;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b0;
                    next_state_s = S_INIT_WAIT_DLLK;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_WAIT_DLLK: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_DLLK_CYCLES) begin
                    next_state_s = S_ACT_WR;
                    timer_s = 24'd0;
                end
            end

            S_ACT_WR: begin
                dfi_address_s = {1'b0, test_addr_row_s_ddr};
                dfi_bank_s    = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                next_state_s = S_WR_CMD;
                timer_s = 24'd0;
            end
            
            S_WR_CMD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    dfi_address_s = {5'b0, test_addr_col_s_ddr};
                    dfi_bank_s    = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0;
                    dfi_ras_n_s = 1'b1;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b0;
                    dfi_wrdata_s = data_to_write_q;
                    dfi_wrdata_mask_s = 4'b0000;
                    dfi_wrdata_en_s = 1'b1;
                    dfi_odt_s = 1'b1;
                    next_state_s = S_WR_DATA_WAIT;
                    timer_s = 24'd0;
                end else begin
                    dfi_address_s = {1'b0, test_addr_row_s_ddr};
                    dfi_bank_s = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b1;
                    dfi_we_n_s = 1'b1;
                end
            end
            
            S_WR_DATA_WAIT: begin
                dfi_wrdata_en_s = 1'b0;
                dfi_odt_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TPHY_WRLAT_C + 4) begin
                    next_state_s = S_DECAY_WAIT_PERIOD;
                    timer_s = 24'd0;
                end
            end
            
            S_DECAY_WAIT_PERIOD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_DECAY_10MS_CYCLES) begin
                    next_state_s = S_ACT_RD;
                    timer_s = 24'd0;
                end
            end
            
            S_ACT_RD: begin
                dfi_address_s = {1'b0, test_addr_row_s_ddr};
                dfi_bank_s = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                next_state_s = S_RD_CMD;
                timer_s = 24'd0;
            end
            
            S_RD_CMD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    dfi_address_s = {5'b0, test_addr_col_s_ddr};
                    dfi_bank_s = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0;
                    dfi_ras_n_s = 1'b1;
                    dfi_cas_n_s = 1'b0;
                    dfi_we_n_s = 1'b1;
                    dfi_rddata_en_s = 1'b1;
                    next_state_s = S_RD_DATA_WAIT;
                    timer_s = 24'd0;
                end else begin
                    dfi_address_s = {1'b0, test_addr_row_s_ddr};
                    dfi_bank_s = test_bank_s_ddr;
                    dfi_cs_n_s = 1'b0;
                    dfi_ras_n_s = 1'b0;
                    dfi_cas_n_s = 1'b1;
                    dfi_we_n_s = 1'b1;
                end
            end
            
            S_RD_DATA_WAIT: begin
                dfi_rddata_en_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TOTAL_RD_LAT_CYCLES - 1) begin
                    if (dfi_rddata_valid_r) begin
                        next_state_s = S_RD_DATA_CAPTURE;
                        timer_s = 24'd0;
                    end else if (timer_q >= TOTAL_RD_LAT_CYCLES + 10) begin
                        $display("%t: Read data valid timeout!", $time);
                        uart_current_msg_s = UART_MSG_WR_DATA;
                        uart_char_idx_s = 4'd0;
                        next_state_s = S_UART_SETUP_CHAR;
                        timer_s = 24'd0;
                    end
                end
            end
            
            S_RD_DATA_CAPTURE: begin
                uart_current_msg_s = UART_MSG_WR_DATA;
                uart_char_idx_s = 4'd0;
                next_state_s = S_UART_SETUP_CHAR;
            end

            S_UART_SETUP_CHAR: begin
                logic [7:0] char_to_send_s;
                logic last_char_for_msg_s;
                last_char_for_msg_s = 1'b0;

                case(uart_current_msg_q)
                    UART_MSG_WR_DATA: begin
                        case(uart_char_idx_q)
                            0: char_to_send_s = "W";
                            1: char_to_send_s = ":";
                            2: char_to_send_s = " ";
                            3,4,5,6,7,8,9,10: begin
                                logic [3:0] nibble;
                                nibble = (data_to_write_q >> ((10-uart_char_idx_q) * 4)) & 4'hF;
                                if (nibble < 10)
                                    char_to_send_s = nibble + "0";
                                else
                                    char_to_send_s = nibble - 10 + "A";
                            end
                            11: begin
                                char_to_send_s = " ";
                                last_char_for_msg_s = 1'b1;
                            end
                            default: begin
                                char_to_send_s = "?";
                                last_char_for_msg_s = 1'b1;
                            end
                        endcase
                    end
                    
                    UART_MSG_RD_DATA: begin
                        case(uart_char_idx_q)
                            0: char_to_send_s = "R";
                            1: char_to_send_s = ":";
                            2: char_to_send_s = " ";
                            3,4,5,6,7,8,9,10: begin
                                logic [3:0] nibble;
                                nibble = (data_read_q >> ((10-uart_char_idx_q) * 4)) & 4'hF;
                                if (nibble < 10)
                                    char_to_send_s = nibble + "0";
                                else
                                    char_to_send_s = nibble - 10 + "A";
                            end
                            11: begin
                                char_to_send_s = " ";
                                last_char_for_msg_s = 1'b1;
                            end
                            default: begin
                                char_to_send_s = "?";
                                last_char_for_msg_s = 1'b1;
                            end
                        endcase
                    end
                    
                    UART_MSG_RESULT: begin
                        case(uart_char_idx_q)
                            0: char_to_send_s = "-";
                            1: char_to_send_s = " ";
                            2: char_to_send_s = data_match_r ? "M" : "F";
                            3: char_to_send_s = " ";
                            4: begin
                                char_to_send_s = "\n";
                                last_char_for_msg_s = 1'b1;
                            end
                            default: begin
                                char_to_send_s = "?";
                                last_char_for_msg_s = 1'b1;
                            end
                        endcase
                    end
                    
                    default: begin
                        char_to_send_s = "E";
                        last_char_for_msg_s = 1'b1;
                    end
                endcase

                // Check if we can send (no pending request)
                if (!uart_cmd_req_200mhz && !uart_tx_busy_sync1) begin
                    uart_tx_data_s = char_to_send_s;
                    uart_tx_start_pulse_s = 1'b1;
                    next_state_s = S_UART_WAIT_TX_DONE;
                    
                    // Update message tracking
                    if (last_char_for_msg_s) begin
                        uart_char_idx_s = 4'd0;
                        case(uart_current_msg_q)
                            UART_MSG_WR_DATA: uart_current_msg_s = UART_MSG_RD_DATA;
                            UART_MSG_RD_DATA: uart_current_msg_s = UART_MSG_RESULT;
                            UART_MSG_RESULT:  uart_current_msg_s = UART_MSG_NONE;
                            default:          uart_current_msg_s = UART_MSG_NONE;
                        endcase
                        current_msg_done_s = 1'b1;
                    end else begin
                        uart_char_idx_s = uart_char_idx_q + 1;
                    end
                end
            end

            S_UART_WAIT_TX_DONE: begin
                // Wait for transmission to complete
                if (uart_tx_done_edge) begin
                    if (uart_current_msg_q == UART_MSG_NONE) begin
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
                    timer_s = 24'd0;
                end
            end
            
            default: next_state_s = S_IDLE;
        endcase
    end

    // UART Instance
    uart_tx #(
        .CLKS_PER_BIT(868)  // 100MHz / 115200 baud
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
