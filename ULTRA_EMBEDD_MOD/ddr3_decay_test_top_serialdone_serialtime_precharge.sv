// ddr3_decay_test_top.sv
// Fixed version with proper DDR3 initialization, timing, and ILA debug probes
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
    localparam CAS_LATENCY_C = 6;  // CL=6 for DDR3-1333

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
        S_IDLE, 
        S_INIT_START_RESET, S_INIT_WAIT_POWER_ON, S_INIT_DEASSERT_RESET, S_INIT_CKE_HIGH_WAIT,
        S_INIT_CMD_PREA, S_INIT_PREA_WAIT,
        S_INIT_CMD_EMR2, S_INIT_EMR2_WAIT,
        S_INIT_CMD_EMR3, S_INIT_EMR3_WAIT,
        S_INIT_CMD_EMR1, S_INIT_EMR1_WAIT,
        S_INIT_CMD_MR0_DLL_RESET, S_INIT_MR0_DLL_WAIT,
        S_INIT_CMD_ZQCL, S_INIT_WAIT_TZQOPER,
        S_INIT_PREA_BEFORE_REF, S_INIT_PREA_BEFORE_REF_WAIT,
        S_INIT_AUTO_REFRESH1, S_INIT_AUTO_REFRESH1_WAIT,
        S_INIT_AUTO_REFRESH2, S_INIT_AUTO_REFRESH2_WAIT,
        S_INIT_CMD_MR0_FINAL, S_INIT_WAIT_DLLK,
        S_PREA_BEFORE_WR, S_PREA_BEFORE_WR_WAIT,
        S_ACT_WR, S_ACT_WR_WAIT, S_WR_CMD, S_WR_DATA_WAIT,
        S_PREA_AFTER_WR, S_PREA_AFTER_WR_WAIT,
        S_DECAY_WAIT_PERIOD,
        S_ACT_RD, S_ACT_RD_WAIT, S_RD_CMD, S_RD_DATA_WAIT, S_RD_DATA_CAPTURE,
        S_PREA_AFTER_RD, S_PREA_AFTER_RD_WAIT,
        S_UART_SETUP_CHAR, S_UART_WAIT_TX_DONE, S_DONE
    } state_t;
    state_t current_state_q, next_state_s;

    // Fixed timing parameters based on DDR3-1333 @ 1.5ns (667MHz)
    localparam T_POWER_ON_RESET_200US_CYCLES = 24'd40_000;   // 200us @ 200MHz
    localparam T_STAB_500US_CYCLES           = 24'd100_000;  // 500us @ 200MHz
    localparam T_XPR_CYCLES                  = 24'd120;      // max(5*tRFC, 10ns) = 120 cycles
    localparam T_MRD_CYCLES                  = 24'd4;        // 4 clocks
    localparam T_MOD_CYCLES                  = 24'd12;       // max(12CK, 15ns)
    localparam T_ZQINIT_CYCLES               = 24'd512;      // 512 clocks for ZQCL
    localparam T_RFC_CYCLES                  = 24'd110;      // 160ns for 2Gb = 107 cycles
    localparam T_RP_CYCLES                   = 24'd9;        // 13.5ns = 9 cycles
    localparam T_RCD_CYCLES                  = 24'd9;        // 13.5ns = 9 cycles  
    localparam T_WR_CYCLES                   = 24'd10;       // 15ns = 10 cycles
    localparam T_RTP_CYCLES                  = 24'd5;        // max(4CK, 7.5ns) = 5 cycles
    localparam T_WTR_CYCLES                  = 24'd5;        // max(4CK, 7.5ns) = 5 cycles
    localparam WRITE_RECOVERY_CYCLES         = 24'd10;       // WR (write recovery)
    localparam TOTAL_RD_LAT_CYCLES           = TPHY_RDLAT_C + CAS_LATENCY_C + 2;
    localparam T_DECAY_5MS_CYCLES            = 24'd1_000_000;  // 5ms @ 200MHz (reduced from 10ms)

    logic [23:0] timer_q, timer_s;
    logic [13:0] test_addr_row_s_ddr;
    logic [9:0]  test_addr_col_s_ddr;  // Fixed for x8 configuration
    logic [2:0]  test_bank_s_ddr;

    logic [31:0] data_to_write_q, data_read_q;
    logic        data_match_r;

    // ILA Debug signals
    logic [5:0] ila_state;
    logic [23:0] ila_timer;
    logic ila_dfi_cmd_valid;
    logic [2:0] ila_dfi_cmd;  // {ras_n, cas_n, we_n}
    logic [14:0] ila_dfi_address;
    logic [2:0] ila_dfi_bank;
    logic ila_dfi_rddata_valid;
    logic [31:0] ila_dfi_rddata;
    logic ila_dfi_wrdata_en;
    logic [31:0] ila_dfi_wrdata;
    logic ila_start_btn_sync;
    logic [31:0] ila_data_read;
    logic ila_data_match;

    // ILA Instance - 256K samples depth, 200MHz sampling
    ila_0 u_ila (
        .clk(clk_phy_sys),
        .probe0(ila_state),           // 6 bits - FSM state
        .probe1(ila_timer[15:0]),      // 16 bits - Timer (lower bits for visibility)
        .probe2(ila_dfi_cmd_valid),    // 1 bit - Command valid (CS# active low)
        .probe3(ila_dfi_cmd),          // 3 bits - Command type
        .probe4(ila_dfi_address),      // 15 bits - Address
        .probe5(ila_dfi_bank),         // 3 bits - Bank
        .probe6(ila_dfi_rddata_valid), // 1 bit - Read data valid
        .probe7(ila_dfi_rddata),       // 32 bits - Read data from PHY
        .probe8(ila_dfi_wrdata_en),    // 1 bit - Write data enable
        .probe9(ila_dfi_wrdata),       // 32 bits - Write data
        .probe10(ila_start_btn_sync),  // 1 bit - Start button
        .probe11(ila_data_read),       // 32 bits - Captured read data
        .probe12(ila_data_match),      // 1 bit - Data match result
        .probe13(dfi_cke_s),           // 1 bit - CKE
        .probe14(dfi_reset_n_s),       // 1 bit - RESET#
        .probe15(dfi_odt_s)            // 1 bit - ODT
    );

    // Connect ILA probes
    always_comb begin
        ila_state = current_state_q;
        ila_timer = timer_q;
        ila_dfi_cmd_valid = ~dfi_cs_n_s;
        ila_dfi_cmd = {dfi_ras_n_s, dfi_cas_n_s, dfi_we_n_s};
        ila_dfi_address = dfi_address_s;
        ila_dfi_bank = dfi_bank_s;
        ila_dfi_rddata_valid = dfi_rddata_valid_r;
        ila_dfi_rddata = dfi_rddata_r;
        ila_dfi_wrdata_en = dfi_wrdata_en_s;
        ila_dfi_wrdata = dfi_wrdata_s;
        ila_start_btn_sync = start_btn_phy_sync_1;
        ila_data_read = data_read_q;
        ila_data_match = data_match_r;
    end

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
            data_to_write_q   <= 32'hDEADBEEF;  // Changed pattern for better visibility
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
            
            if (current_state_q == S_RD_DATA_WAIT && dfi_rddata_valid_r) begin
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

        // Default DFI signals - NOP command
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
        dfi_wrdata_mask_s = 4'h0;  // No masking
        dfi_rddata_en_s = 1'b0;

        // Test address configuration
        test_addr_row_s_ddr = 14'h0100;  // Row 256
        test_addr_col_s_ddr = 10'h020;   // Column 32 (within valid range for x8)
        test_bank_s_ddr     = 3'b010;    // Bank 2

        case (current_state_q)
            S_IDLE: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b1;  // Keep reset high in idle
                if (start_cmd_edge_s) begin
                    next_state_s = S_INIT_START_RESET;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_START_RESET: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b0;  // Assert reset
                timer_s = timer_q + 1;
                if (timer_q >= T_POWER_ON_RESET_200US_CYCLES) begin
                    next_state_s = S_INIT_WAIT_POWER_ON;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_WAIT_POWER_ON: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= 24'd1000) begin  // Extra delay
                    next_state_s = S_INIT_DEASSERT_RESET;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_DEASSERT_RESET: begin
                dfi_cke_s = 1'b0;
                dfi_reset_n_s = 1'b1;  // Deassert reset
                timer_s = timer_q + 1;
                if (timer_q >= T_STAB_500US_CYCLES) begin
                    next_state_s = S_INIT_CKE_HIGH_WAIT;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CKE_HIGH_WAIT: begin
                dfi_cke_s = 1'b1;  // Enable clock
                dfi_cs_n_s = 1'b0; // Keep chip selected
                timer_s = timer_q + 1;
                if (timer_q >= T_XPR_CYCLES) begin
                    next_state_s = S_INIT_CMD_PREA;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_PREA: begin
                // Precharge all banks
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0400; // A10=1 for Precharge All
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_PREA_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_PREA_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RP_CYCLES) begin
                    next_state_s = S_INIT_CMD_EMR2;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_EMR2: begin
                // Extended Mode Register 2
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0000;  // Normal operation
                dfi_bank_s = 3'b010;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_EMR2_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_EMR2_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    next_state_s = S_INIT_CMD_EMR3;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_EMR3: begin
                // Extended Mode Register 3
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0000;  // Normal operation
                dfi_bank_s = 3'b011;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_EMR3_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_EMR3_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    next_state_s = S_INIT_CMD_EMR1;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_EMR1: begin
                // Extended Mode Register 1 - Enable DLL, set drive strength
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'b00000_00_0_01_0_00_0; // DLL Enable, Drive Strength RZQ/6, AL=0
                dfi_bank_s = 3'b001;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_EMR1_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_EMR1_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MRD_CYCLES) begin
                    next_state_s = S_INIT_CMD_MR0_DLL_RESET;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_MR0_DLL_RESET: begin
                // Mode Register 0 - CL=6, BL=8, DLL Reset
                dfi_cs_n_s = 1'b0;
                dfi_address_s = {2'b00, 3'b010, 1'b1, 4'b0010, 3'b000, 1'b0}; // CL=6, WR=6, DLL Reset, BL=8
                dfi_bank_s = 3'b000;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_MR0_DLL_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_MR0_DLL_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_MOD_CYCLES) begin
                    next_state_s = S_INIT_CMD_ZQCL;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_ZQCL: begin
                // ZQ Calibration Long
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0400; // A10=1 for ZQCL
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;  // WE=0 for ZQ calibration
                next_state_s = S_INIT_WAIT_TZQOPER;
                timer_s = 24'd0;
            end
            
            S_INIT_WAIT_TZQOPER: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_ZQINIT_CYCLES) begin
                    next_state_s = S_INIT_PREA_BEFORE_REF;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_PREA_BEFORE_REF: begin
                // Precharge all before refresh
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0400; // A10=1
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_PREA_BEFORE_REF_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_PREA_BEFORE_REF_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RP_CYCLES) begin
                    next_state_s = S_INIT_AUTO_REFRESH1;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_AUTO_REFRESH1: begin
                // Auto-refresh command
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b1;
                next_state_s = S_INIT_AUTO_REFRESH1_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_AUTO_REFRESH1_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RFC_CYCLES) begin
                    next_state_s = S_INIT_AUTO_REFRESH2;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_AUTO_REFRESH2: begin
                // Second auto-refresh
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b1;
                next_state_s = S_INIT_AUTO_REFRESH2_WAIT;
                timer_s = 24'd0;
            end
            
            S_INIT_AUTO_REFRESH2_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RFC_CYCLES) begin
                    next_state_s = S_INIT_CMD_MR0_FINAL;
                    timer_s = 24'd0;
                end
            end
            
            S_INIT_CMD_MR0_FINAL: begin
                // Mode Register 0 - Normal operation (no DLL reset)
                dfi_cs_n_s = 1'b0;
                dfi_address_s = {2'b00, 3'b010, 1'b0, 4'b0010, 3'b000, 1'b0}; // CL=6, WR=6, DLL active, BL=8
                dfi_bank_s = 3'b000;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                next_state_s = S_INIT_WAIT_DLLK;
                timer_s = 24'd0;
            end
            
            S_INIT_WAIT_DLLK: begin
                timer_s = timer_q + 1;
                if (timer_q >= 24'd512) begin  // DLL lock time
                    next_state_s = S_PREA_BEFORE_WR;
                    timer_s = 24'd0;
                end
            end

            S_PREA_BEFORE_WR: begin
                // Precharge all banks before write
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0400;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                next_state_s = S_PREA_BEFORE_WR_WAIT;
                timer_s = 24'd0;
            end
            
            S_PREA_BEFORE_WR_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RP_CYCLES) begin
                    next_state_s = S_ACT_WR;
                    timer_s = 24'd0;
                end
            end

            S_ACT_WR: begin
                // Activate row
                dfi_address_s = {1'b0, test_addr_row_s_ddr};
                dfi_bank_s    = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                next_state_s = S_ACT_WR_WAIT;
                timer_s = 24'd0;
            end
            
            S_ACT_WR_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    next_state_s = S_WR_CMD;
                    timer_s = 24'd0;
                end
            end
            
            S_WR_CMD: begin
                // Write command - Fixed column address for x8
                dfi_address_s = {5'b0, test_addr_col_s_ddr};
                dfi_bank_s    = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_wrdata_s = data_to_write_q;
                dfi_wrdata_mask_s = 4'b0000;  // Write all bytes
                dfi_wrdata_en_s = 1'b1;
                dfi_odt_s = 1'b1;
                next_state_s = S_WR_DATA_WAIT;
                timer_s = 24'd0;
            end
            
            S_WR_DATA_WAIT: begin
                dfi_wrdata_en_s = 1'b0;
                dfi_odt_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TPHY_WRLAT_C + WRITE_RECOVERY_CYCLES) begin
                    next_state_s = S_PREA_AFTER_WR;
                    timer_s = 24'd0;
                end
            end
            
            S_PREA_AFTER_WR: begin
                // Precharge after write
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0000;  // A10=0 for single bank
                dfi_bank_s = test_bank_s_ddr;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                next_state_s = S_PREA_AFTER_WR_WAIT;
                timer_s = 24'd0;
            end
            
            S_PREA_AFTER_WR_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RP_CYCLES) begin
                    next_state_s = S_DECAY_WAIT_PERIOD;
                    timer_s = 24'd0;
                end
            end
            
            S_DECAY_WAIT_PERIOD: begin
                // Wait for decay - NO REFRESH COMMANDS
                timer_s = timer_q + 1;
                if (timer_q >= T_DECAY_5MS_CYCLES) begin
                    next_state_s = S_ACT_RD;
                    timer_s = 24'd0;
                end
            end
            
            S_ACT_RD: begin
                // Activate row for read
                dfi_address_s = {1'b0, test_addr_row_s_ddr};
                dfi_bank_s = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                next_state_s = S_ACT_RD_WAIT;
                timer_s = 24'd0;
            end
            
            S_ACT_RD_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    next_state_s = S_RD_CMD;
                    timer_s = 24'd0;
                end
            end
            
            S_RD_CMD: begin
                // Read command
                dfi_address_s = {5'b0, test_addr_col_s_ddr};
                dfi_bank_s = test_bank_s_ddr;
                dfi_cs_n_s = 1'b0;
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b1;
                dfi_rddata_en_s = 1'b1;
                next_state_s = S_RD_DATA_WAIT;
                timer_s = 24'd0;
            end
            
            S_RD_DATA_WAIT: begin
                dfi_rddata_en_s = 1'b0;
                timer_s = timer_q + 1;
                if (dfi_rddata_valid_r) begin
                    next_state_s = S_RD_DATA_CAPTURE;
                    timer_s = 24'd0;
                end else if (timer_q >= TOTAL_RD_LAT_CYCLES + 10) begin
                    // Timeout - capture whatever is on the bus
                    next_state_s = S_RD_DATA_CAPTURE;
                    timer_s = 24'd0;
                end
            end
            
            S_RD_DATA_CAPTURE: begin
                next_state_s = S_PREA_AFTER_RD;
                timer_s = 24'd0;
            end
            
            S_PREA_AFTER_RD: begin
                // Precharge after read
                dfi_cs_n_s = 1'b0;
                dfi_address_s = 15'h0400;  // Precharge all
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                next_state_s = S_PREA_AFTER_RD_WAIT;
                timer_s = 24'd0;
            end
            
            S_PREA_AFTER_RD_WAIT: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RP_CYCLES) begin
                    uart_current_msg_s = UART_MSG_WR_DATA;
                    uart_char_idx_s = 4'd0;
                    next_state_s = S_UART_SETUP_CHAR;
                    timer_s = 24'd0;
                end
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
                dfi_cke_s = 1'b1;  // Keep clock enabled
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
