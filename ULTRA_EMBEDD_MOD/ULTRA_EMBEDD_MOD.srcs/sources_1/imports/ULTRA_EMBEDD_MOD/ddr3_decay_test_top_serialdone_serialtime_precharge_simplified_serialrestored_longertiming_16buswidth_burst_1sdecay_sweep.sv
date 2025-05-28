// ddr3_decay_test_top.sv
// Enhanced version with multiple decay time iterations, multiple tests per setting,
// similarity calculation, and detailed UART output.
module ddr3_decay_test_top (
    input wire clk100mhz_i,      // Board clock 100MHz
    input wire reset_btn_i,      // Active high reset button for whole system
    input wire start_btn_i,      // Button to start the DDR3 test sequence

    // LEDs for status
    output logic status_led0_o,  // Test in progress / Idle / All Complete
    output logic status_led1_o,  // Last test success (data match)
    output logic status_led2_o,  // Last test fail (data mismatch / decay)
    output logic status_led3_o,  // UART TX activity

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
    logic clk_phy_sys;       // PHY system clock (200MHz), FSM runs on this
    logic clk_phy_ddr;       // PHY DDR clock (400MHz)
    logic clk_phy_ddr90;     // PHY DDR clock 90-deg phase (400MHz)
    logic clk_idelay_ref;    // PHY IDELAYCTRL reference clock (200MHz)
    logic mmcm_locked;
    
    logic sys_rst_fsm_phy;   // Synchronized, active high reset for FSM and PHY (clk_phy_sys domain)
    logic rst_for_uart;      // Synchronized, active high reset for UART (clk100mhz_i domain)

    clk_wiz_0 u_clk_wiz (
        .clk_phy_sys(clk_phy_sys),
        .clk_phy_ddr(clk_phy_ddr),
        .clk_phy_ddr90(clk_phy_ddr90),
        .clk_idelay_ref(clk_idelay_ref),
        .reset(reset_btn_i), // MMCM reset tied to board reset
        .locked(mmcm_locked),
        .clk_in1(clk100mhz_i)
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
    localparam TPHY_RDLAT_C  = 4;
    localparam TPHY_WRLAT_C  = 3;
    localparam CAS_LATENCY_C = 6;  // CL=6 for DDR3-1333 (adjust if using different speed grade)

    logic [14:0] dfi_address_s;
    logic [2:0]  dfi_bank_s;
    logic        dfi_cas_n_s, dfi_cke_s, dfi_cs_n_s, dfi_odt_s, dfi_ras_n_s;
    logic        dfi_reset_n_s, dfi_we_n_s, dfi_wrdata_en_s, dfi_rddata_en_s;
    logic [31:0] dfi_wrdata_s, dfi_rddata_r;
    logic [3:0]  dfi_wrdata_mask_s;
    logic        dfi_rddata_valid_r;
    logic [1:0]  dfi_rddata_dnv_r; // Not used in this example, but part of DFI

    ddr3_dfi_phy #( 
        .REFCLK_FREQUENCY(200),      // IDELAYCTRL reference clock frequency in MHz
        .DQS_TAP_DELAY_INIT(15),     // Initial DQS IDELAY tap value (adjust per board)
        .DQ_TAP_DELAY_INIT(1),       // Initial DQ IDELAY tap value (adjust per board)
        .TPHY_RDLAT(TPHY_RDLAT_C), 
        .TPHY_WRLAT(TPHY_WRLAT_C), 
        .TPHY_WRDATA(0)              // Delay from dfi_wrdata_en to first DQ/DM change
    )
    u_ddr3_phy_inst (
        .clk_i(clk_phy_sys), 
        .clk_ddr_i(clk_phy_ddr), 
        .clk_ddr90_i(clk_phy_ddr90), 
        .clk_ref_i(clk_idelay_ref),
        .rst_i(sys_rst_fsm_phy), 
        .cfg_valid_i(1'b0),          // Configuration interface not used in this example
        .cfg_i(32'd0),
        .dfi_address_i(dfi_address_s[14:0]), // DFI Address (Row/Col)
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
        .dfi_wrdata_mask_i(dfi_wrdata_mask_s), // DFI Write Data Mask (all enabled)
        .dfi_rddata_en_i(dfi_rddata_en_s), 
        .dfi_rddata_o(dfi_rddata_r),
        .dfi_rddata_valid_o(dfi_rddata_valid_r), 
        .dfi_rddata_dnv_o(dfi_rddata_dnv_r),  // DFI Read Data Not Valid (per DQS group)
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
    // Iteration and Test Parameters
    localparam NUM_DECAY_SETTINGS = 4; // Number of different decay times to test
    localparam NUM_TESTS_PER_DECAY_SETTING = 3; // Number of write/decay/read cycles per decay time

    // Decay times in milliseconds, converted to clock cycles (200MHz clock)
    // 1ms = 200,000 cycles; 10ms = 2,000,000; 100ms = 20,000,000; 1000ms = 200,000,000
    logic [27:0] decay_time_target_cycles [NUM_DECAY_SETTINGS-1:0];
    initial begin // For simulation; for synthesis, consider localparam array or ROM
        decay_time_target_cycles[0] = 28'd200_000;     // 1ms
        decay_time_target_cycles[1] = 28'd2_000_000;    // 10ms
        decay_time_target_cycles[2] = 28'd20_000_000;   // 100ms
        decay_time_target_cycles[3] = 28'd200_000_000;  // 1000ms
    end
    
    // Corresponding decay times in ms for UART output
    logic [15:0] decay_time_ms_values [NUM_DECAY_SETTINGS-1:0];
     initial begin
        decay_time_ms_values[0] = 16'd1;
        decay_time_ms_values[1] = 16'd10;
        decay_time_ms_values[2] = 16'd100;
        decay_time_ms_values[3] = 16'd1000;
    end

    logic [$clog2(NUM_DECAY_SETTINGS)-1:0] current_decay_idx_q;
    logic [$clog2(NUM_TESTS_PER_DECAY_SETTING):0] tests_run_for_current_decay_q; // Counter for tests
    logic [27:0] current_decay_setting_cycles_q;
    logic [15:0] current_decay_ms_for_uart_q;


    // FSM States
    typedef enum logic [6:0] { // Wider for more states
        S_IDLE,
        S_INIT_RESET, S_INIT_RESET_WAIT, S_INIT_CKE_LOW, S_INIT_STABLE,
        S_INIT_MRS2, S_INIT_MRS3, S_INIT_MRS1, S_INIT_MRS0, S_INIT_ZQCL,
        S_INIT_DONE,

        S_START_NEW_DECAY_SETTING,
        S_START_TEST_ITERATION,

        S_WRITE_ACTIVATE, S_WRITE_ACTIVATE_WAIT, S_WRITE_CMD,
        S_WRITE_BURST_0, S_WRITE_BURST_1, S_WRITE_BURST_2, S_WRITE_BURST_3,
        S_WRITE_WAIT, S_PRECHARGE_AFTER_WRITE, S_PRECHARGE_WAIT,
        S_DECAY_WAIT,
        S_READ_ACTIVATE, S_READ_ACTIVATE_WAIT, S_READ_CMD, S_READ_WAIT,
        S_READ_CAPTURE_0, S_READ_CAPTURE_1, S_READ_CAPTURE_2, S_READ_CAPTURE_3,
        S_READ_DONE,
        
        S_CALCULATE_SIMILARITY,

        S_UART_PREPARE_MSG, // Prepares current segment of UART message
        S_UART_SEND_CHAR,   // Sends one character
        S_UART_WAIT_TX_DONE,// Waits for UART TX to be free

        S_CHECK_FOR_MORE_TESTS,
        S_ALL_TESTS_COMPLETE
    } state_t;
    
    state_t current_state_q, next_state_s;

    // Timing parameters (200MHz clock for FSM)
    localparam T_RESET_US           = 24'd40_000;   // 200us @ 200MHz
    localparam T_STABLE_US          = 24'd100_000;  // 500us @ 200MHz 
    localparam T_INIT_WAIT          = 24'd1024;     // General init wait
    localparam T_MODE_REG_SET       = 24'd20;       // tMRD (4 cycles) + margin
    localparam T_ZQINIT             = 24'd102_400;  // tZQinit (512ns -> 102.4 cycles @ 200MHz), use 512 cycles for safety
    localparam T_ACTIVATE_TO_RW     = 24'd20;       // tRCD (e.g., 13.75ns for -125 -> ~3 cycles) + margin
    localparam T_WRITE_TO_PRECHARGE = 24'd20;       // tWR (15ns -> 3 cycles) + tWL + margin
    localparam T_PRECHARGE          = 24'd20;       // tRP (e.g., 13.75ns -> ~3 cycles) + margin
    localparam T_READ_LATENCY       = TPHY_RDLAT_C + CAS_LATENCY_C + 4; // CL + PHY latency + margin
    
    logic [27:0] timer_q; 

    logic [127:0] write_data_q;  // Full burst data (8 x 16-bit)
    logic [127:0] read_data_q;   // Full burst data captured
    logic init_sequence_done_q;
    logic [2:0]  burst_cnt_q;    // Burst counter for write
    logic [2:0]  read_burst_cnt_q; // Read burst counter for capture
    logic [7:0]  similar_bits_count_q; // Max 128 similar bits

    localparam [127:0] TEST_PATTERN = 128'hA5A5_B6B6_C7C7_D8D8_E9E9_F0F0_1234_5678; // Example pattern
    
    localparam TEST_ROW  = 14'h0001; // Use a different row to avoid bank 0, row 0 if possible
    localparam TEST_COL  = 10'h000;  // Start of column
    localparam TEST_BANK = 3'b001;   // Use a different bank

    // UART control
    logic uart_tx_busy;
    logic uart_tx_busy_sync0, uart_tx_busy_sync1; // Synchronized to clk_phy_sys
    logic uart_tx_start_s; // Internal signal before potential CDC
    logic [7:0] uart_tx_data_s;  // Internal signal before potential CDC

    // UART message assembly
    typedef enum logic [3:0] {
        UART_SEG_DECAY_VAL, UART_SEG_COMMA1,
        UART_SEG_WRITE_HEX, UART_SEG_COMMA2,
        UART_SEG_READ_HEX,  UART_SEG_COMMA3,
        UART_SEG_SIMILARITY_VAL,
        UART_SEG_CR, UART_SEG_LF,
        UART_SEG_DONE
    } uart_segment_type_t;

    uart_segment_type_t uart_current_segment_q;
    logic [4:0] uart_char_ptr_q; // Max 32 chars for hex patterns

    logic [7:0] uart_data_segment_str_q [31:0]; // Buffer for current string segment being sent (max 32 hex chars)
    logic [4:0] uart_data_segment_len_q;      // Length of current segment in buffer

    // Start button synchronization
    logic start_btn_sync, start_btn_prev, start_btn_edge;
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            start_btn_sync <= 1'b0;
            start_btn_prev <= 1'b0;
        end else begin
            start_btn_sync <= start_btn_i; // start_btn_i is already on clk100mhz_i, needs proper CDC if FSM is faster
                                          // Assuming start_btn_i is debounced and held long enough
            start_btn_prev <= start_btn_sync;
        end
    end
    assign start_btn_edge = start_btn_sync & ~start_btn_prev;

    // UART busy signal synchronization
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            uart_tx_busy_sync0 <= 1'b0;
            uart_tx_busy_sync1 <= 1'b0;
        end else begin
            uart_tx_busy_sync0 <= uart_tx_busy;
            uart_tx_busy_sync1 <= uart_tx_busy_sync0;
        end
    end

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q <= S_IDLE;
            timer_q <= 28'd0;
            write_data_q <= TEST_PATTERN;
            read_data_q <= 128'd0;
            init_sequence_done_q <= 1'b0;
            burst_cnt_q <= 3'd0;
            read_burst_cnt_q <= 3'd0;
            similar_bits_count_q <= 8'd0;
            
            current_decay_idx_q <= 0;
            tests_run_for_current_decay_q <= 0;
            current_decay_setting_cycles_q <= decay_time_target_cycles[0];
            current_decay_ms_for_uart_q    <= decay_time_ms_values[0];

            uart_current_segment_q <= UART_SEG_DECAY_VAL;
            uart_char_ptr_q <= 5'd0;
            uart_data_segment_len_q <= 5'd0;

        end else begin
            current_state_q <= next_state_s;
            
            if (current_state_q != next_state_s) begin // Reset timer on state change
                timer_q <= 28'd0;
            end else begin
                if (timer_q < '1) begin // Prevent timer overflow, saturate
                    timer_q <= timer_q + 1;
                end
            end
            
            if (next_state_s == S_IDLE) begin // Reset test parameters when returning to IDLE
                init_sequence_done_q <= 1'b0;
                current_decay_idx_q <= 0;
                tests_run_for_current_decay_q <= 0;
                 current_decay_setting_cycles_q <= decay_time_target_cycles[0];
                 current_decay_ms_for_uart_q    <= decay_time_ms_values[0];
            end

            if (next_state_s == S_START_NEW_DECAY_SETTING) begin
                current_decay_setting_cycles_q <= decay_time_target_cycles[current_decay_idx_q];
                current_decay_ms_for_uart_q    <= decay_time_ms_values[current_decay_idx_q];
                tests_run_for_current_decay_q <= 0;
            end
            
            if (next_state_s == S_START_TEST_ITERATION) begin
                read_data_q <= 128'd0;
                similar_bits_count_q <= 8'd0;
                read_burst_cnt_q <= 3'd0; // Ensure read burst counter is reset here
            end

            if (current_state_q == S_INIT_DONE && init_sequence_done_q == 1'b0) begin // Latch that init sequence is done
                 init_sequence_done_q <= 1'b1;
            end
            
            // Handle burst counter for writes
            if (current_state_q == S_WRITE_CMD) begin
                burst_cnt_q <= 3'd0;
            end else if (current_state_q >= S_WRITE_BURST_0 && current_state_q < S_WRITE_WAIT) begin // Check if it's a burst state
                 if (dfi_wrdata_en_s) begin // Increment only when data is actually sent
                    burst_cnt_q <= burst_cnt_q + 1;
                 end
            end
            
            // Handle read data capture
            if (current_state_q == S_READ_CMD) begin // Reset read burst counter before read command
                read_burst_cnt_q <= 3'd0;
                read_data_q <= 128'd0; // Clear previous read data
            end else if (dfi_rddata_valid_r && current_state_q >= S_READ_CAPTURE_0 && current_state_q <= S_READ_CAPTURE_3) begin
                if (read_burst_cnt_q < 4) begin // Capture 4 beats of 32-bit data for 128-bit total
                    case (read_burst_cnt_q)
                        3'd0: read_data_q[31:0]   <= dfi_rddata_r;
                        3'd1: read_data_q[63:32]  <= dfi_rddata_r;
                        3'd2: read_data_q[95:64]  <= dfi_rddata_r;
                        3'd3: read_data_q[127:96] <= dfi_rddata_r;
                    endcase
                    read_burst_cnt_q <= read_burst_cnt_q + 1;
                end
            end

            if (next_state_s == S_CALCULATE_SIMILARITY) begin
                logic [7:0] count = 8'd0;
                for (int i = 0; i < 128; i = i + 1) begin
                    if (write_data_q[i] == read_data_q[i]) begin
                        count = count + 1;
                    end
                end
                similar_bits_count_q <= count;
            end

            // UART message state updates
            if (next_state_s == S_UART_PREPARE_MSG) begin
                uart_char_ptr_q <= 5'd0;
                // uart_current_segment_q is set by the state transitioning TO S_UART_PREPARE_MSG
            end else if (current_state_q == S_UART_SEND_CHAR && next_state_s == S_UART_WAIT_TX_DONE) begin
                // Character has been sent (or attempted)
            end else if (current_state_q == S_UART_WAIT_TX_DONE && next_state_s == S_UART_PREPARE_MSG) begin
                // Current segment finished, moving to next segment
                uart_char_ptr_q <= 5'd0; // Reset for new segment
            end else if (current_state_q == S_UART_WAIT_TX_DONE && next_state_s == S_UART_SEND_CHAR) begin
                // More characters in current segment
                uart_char_ptr_q <= uart_char_ptr_q + 1;
            end
            
            if (next_state_s == S_CHECK_FOR_MORE_TESTS) begin
                if (tests_run_for_current_decay_q < NUM_TESTS_PER_DECAY_SETTING - 1) begin
                    tests_run_for_current_decay_q <= tests_run_for_current_decay_q + 1;
                end else begin // All tests for current decay done
                    if (current_decay_idx_q < NUM_DECAY_SETTINGS - 1) begin
                        current_decay_idx_q <= current_decay_idx_q + 1;
                        // tests_run_for_current_decay_q is reset in S_START_NEW_DECAY_SETTING
                    end else begin
                        // All decay settings and tests complete
                    end
                end
            end
        end
    end

    // State machine combinational logic
    always_comb begin
        next_state_s = current_state_q;
        uart_tx_start_s = 1'b0;
        uart_tx_data_s = 8'h00;
        
        dfi_cs_n_s = 1'b0; // Keep chip selected unless in IDLE or specific deselect phases
        dfi_ras_n_s = 1'b1;
        dfi_cas_n_s = 1'b1;
        dfi_we_n_s = 1'b1;
        dfi_cke_s = 1'b1;   // CKE high during normal operation
        dfi_reset_n_s = 1'b1;
        dfi_odt_s = 1'b0;   // ODT typically enabled by PHY during writes/reads, controller can suggest
        dfi_address_s = 15'd0;
        dfi_bank_s = 3'd0;
        dfi_wrdata_s = 32'd0;
        dfi_wrdata_en_s = 1'b0;
        dfi_wrdata_mask_s = 4'h0; // Enable all byte lanes
        dfi_rddata_en_s = 1'b0;

        // Default UART segment data (cleared before each segment preparation)
        for (int i=0; i<32; i++) uart_data_segment_str_q[i] = 8'h00;
        uart_data_segment_len_q = 0;
        
        case (current_state_q)
            S_IDLE: begin
                dfi_cs_n_s = 1'b1; // Deselect chip
                dfi_cke_s = 1'b0;  // CKE low for power down or pre-init
                if (start_btn_edge) begin
                    if (!init_sequence_done_q) begin
                        next_state_s = S_INIT_RESET;
                    end else begin
                        next_state_s = S_START_NEW_DECAY_SETTING; // Restart tests
                    end
                end
            end
            
            // --- Initialization Sequence ---
            S_INIT_RESET: begin
                dfi_reset_n_s = 1'b0; // Assert DDR_RESET_N
                dfi_cke_s = 1'b0;     // Keep CKE low
                next_state_s = S_INIT_RESET_WAIT;
            end
            S_INIT_RESET_WAIT: begin
                dfi_reset_n_s = 1'b0;
                dfi_cke_s = 1'b0;
                if (timer_q >= T_RESET_US) begin // Wait for tPW_RESET (min 200us)
                    next_state_s = S_INIT_CKE_LOW;
                end
            end
            S_INIT_CKE_LOW: begin // After reset deassertion, CKE must remain low for tXPR (min 5 CKs or tRFC+10ns)
                                  // Here using a longer stable time
                dfi_reset_n_s = 1'b1; // Deassert DDR_RESET_N
                dfi_cke_s = 1'b0;
                if (timer_q >= T_STABLE_US) begin // Wait for clock stable and CKE low duration (min 500us)
                    next_state_s = S_INIT_STABLE;
                end
            end
            S_INIT_STABLE: begin // Bring CKE high
                dfi_cke_s = 1'b1;
                if (timer_q >= T_INIT_WAIT) begin // General wait, e.g. tDLLK (min 512 CKs)
                    next_state_s = S_INIT_MRS2;
                end
            end
            S_INIT_MRS2: begin // Load Mode Register MR2
                // MR2: BA1=1, BA0=0. Set write latency, etc.
                // For simplicity, keeping default values (often 0 for self-refresh settings)
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS command
                dfi_bank_s  = 3'b010; // Select MR2
                dfi_address_s = 15'h0000; // A5-A3 for WL (CAS Write Latency). CL=6, AL=0 -> WL=CL-1=5 (010b)
                                         // A6 for Self-Refresh Temp Range (0 normal)
                if (timer_q >= T_MODE_REG_SET) begin // Wait tMRD (min 4 CKs)
                    next_state_s = S_INIT_MRS3;
                end
            end
            S_INIT_MRS3: begin // Load Mode Register MR3
                // MR3: BA1=1, BA0=1. MPR settings.
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0;
                dfi_bank_s  = 3'b011; // Select MR3
                dfi_address_s = 15'h0000; // All zeros for default MPR settings
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS1;
                end
            end
            S_INIT_MRS1: begin // Load Mode Register MR1
                // MR1: BA1=0, BA0=1. DLL Enable, ODT settings.
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0;
                dfi_bank_s  = 3'b001; // Select MR1
                // A0=0 (DLL Enable), A2,A6,A9 for Rtt_Nom (e.g., 001 for RZQ/4=60ohm)
                // A1,A5 for AL (Additive Latency). AL=0 for this example.
                dfi_address_s = 15'b00000_00_0_01_0_00_0; // DLL Enable, AL=0, Rtt_Nom=RZQ/4 (001 for A9,A6,A2)
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS0;
                end
            end
            S_INIT_MRS0: begin // Load Mode Register MR0
                // MR0: BA1=0, BA0=0. Burst Length, CAS Latency, DLL Reset.
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0;
                dfi_bank_s  = 3'b000; // Select MR0
                // BL8 (A1,A0=00), CL=6 (A6,A5,A4=010), DLL Reset (A8=1)
                // A2=0 (Sequential), A12=0 (TDQS disable)
                dfi_address_s = 15'b0_0_0_1_010_1_0_00; // BL=8, Read Burst Type=Sequential, CL=6, DLL Reset
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_ZQCL;
                end
            end
            S_INIT_ZQCL: begin // ZQ Calibration Long
                dfi_we_n_s = 1'b0; // ZQCL command (WE_n=0, CS_n=0, RAS_n=1, CAS_n=1)
                dfi_address_s[10] = 1'b1; // A10=1 for ZQCL (ZQ Long Calibration)
                if (timer_q >= T_ZQINIT) begin // Wait tZQinit (min 512ns or 512 CKs for some devices)
                    next_state_s = S_INIT_DONE;
                end
            end
            S_INIT_DONE: begin
                if (timer_q >= T_INIT_WAIT) begin // Extra wait after init
                    next_state_s = S_START_NEW_DECAY_SETTING;
                end
            end

            // --- Test Iteration Control ---
            S_START_NEW_DECAY_SETTING: begin
                // Parameters (current_decay_setting_cycles_q, etc.) are set in sequential block
                next_state_s = S_START_TEST_ITERATION;
            end
            S_START_TEST_ITERATION: begin
                 // Parameters (read_data_q, etc.) are set in sequential block
                next_state_s = S_WRITE_ACTIVATE;
            end

            // --- Write Sequence ---
            S_WRITE_ACTIVATE: begin
                dfi_ras_n_s = 1'b0; // ACTIVATE command
                dfi_bank_s  = TEST_BANK;
                dfi_address_s = {1'b0, TEST_ROW}; // Row address on A13-A0
                next_state_s = S_WRITE_ACTIVATE_WAIT;
            end
            S_WRITE_ACTIVATE_WAIT: begin
                if (timer_q >= T_ACTIVATE_TO_RW) begin // Wait tRCD
                    next_state_s = S_WRITE_CMD;
                end
            end
            S_WRITE_CMD: begin
                dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // WRITE command
                dfi_bank_s  = TEST_BANK;
                dfi_address_s = {5'd0, TEST_COL}; // Column address on A9-A0 (A10=0 for no AP)
                dfi_odt_s = 1'b1; // Enable ODT for write
                next_state_s = S_WRITE_BURST_0;
            end
            S_WRITE_BURST_0: begin
                dfi_wrdata_s = write_data_q[31:0];
                dfi_wrdata_en_s = 1'b1; dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_1;
            end
            S_WRITE_BURST_1: begin
                dfi_wrdata_s = write_data_q[63:32];
                dfi_wrdata_en_s = 1'b1; dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_2;
            end
            S_WRITE_BURST_2: begin
                dfi_wrdata_s = write_data_q[95:64];
                dfi_wrdata_en_s = 1'b1; dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_3;
            end
            S_WRITE_BURST_3: begin
                dfi_wrdata_s = write_data_q[127:96];
                dfi_wrdata_en_s = 1'b1; dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_WAIT;
            end
            S_WRITE_WAIT: begin // Wait for tWR (Write Recovery) + tWL (Write Latency)
                dfi_odt_s = 1'b0; // Can disable ODT after burst
                if (timer_q >= T_WRITE_TO_PRECHARGE) begin
                    next_state_s = S_PRECHARGE_AFTER_WRITE;
                end
            end
            S_PRECHARGE_AFTER_WRITE: begin
                dfi_ras_n_s = 1'b0; dfi_we_n_s = 1'b0; // PRECHARGE command
                dfi_address_s[10] = 1'b1; // A10=1 for Precharge All Banks
                // Or precharge specific bank: dfi_bank_s = TEST_BANK; dfi_address_s[10] = 1'b0;
                next_state_s = S_PRECHARGE_WAIT;
            end
            S_PRECHARGE_WAIT: begin
                if (timer_q >= T_PRECHARGE) begin // Wait tRP (Precharge Period)
                    next_state_s = S_DECAY_WAIT;
                end
            end
            S_DECAY_WAIT: begin
                dfi_cke_s = 1'b0; // Optional: CKE low during long decay to save power (if no refresh needed)
                                  // For this test, assume refresh is handled or not critical for short decay.
                                  // If CKE is low, it must be brought high tXP before next command.
                if (timer_q >= current_decay_setting_cycles_q) begin
                    next_state_s = S_READ_ACTIVATE;
                end
            end

            // --- Read Sequence ---
            S_READ_ACTIVATE: begin
                dfi_cke_s = 1'b1; // Ensure CKE is high
                dfi_ras_n_s = 1'b0; // ACTIVATE command
                dfi_bank_s  = TEST_BANK;
                dfi_address_s = {1'b0, TEST_ROW};
                next_state_s = S_READ_ACTIVATE_WAIT;
            end
            S_READ_ACTIVATE_WAIT: begin
                if (timer_q >= T_ACTIVATE_TO_RW) begin // Wait tRCD
                    next_state_s = S_READ_CMD;
                end
            end
            S_READ_CMD: begin
                dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b1; // READ command
                dfi_bank_s  = TEST_BANK;
                dfi_address_s = {5'd0, TEST_COL};
                dfi_rddata_en_s = 1'b1; // Enable DFI read data path
                next_state_s = S_READ_WAIT;
            end
            S_READ_WAIT: begin // Wait for CAS Latency + PHY Read Latency
                dfi_rddata_en_s = 1'b1;
                if (timer_q >= T_READ_LATENCY) begin
                    next_state_s = S_READ_CAPTURE_0;
                end
            end
            S_READ_CAPTURE_0: begin // Start capturing burst data
                dfi_rddata_en_s = 1'b1;
                if (read_burst_cnt_q >= 1) next_state_s = S_READ_CAPTURE_1; // Wait for first data beat
            end
            S_READ_CAPTURE_1: begin
                dfi_rddata_en_s = 1'b1;
                if (read_burst_cnt_q >= 2) next_state_s = S_READ_CAPTURE_2;
            end
            S_READ_CAPTURE_2: begin
                dfi_rddata_en_s = 1'b1;
                if (read_burst_cnt_q >= 3) next_state_s = S_READ_CAPTURE_3;
            end
            S_READ_CAPTURE_3: begin
                dfi_rddata_en_s = 1'b1; // Keep enabled for last beat
                if (read_burst_cnt_q >= 4) begin // All 4 beats (128 bits) captured
                    next_state_s = S_READ_DONE;
                end
            end
            S_READ_DONE: begin
                dfi_rddata_en_s = 1'b0; // Disable DFI read path
                if (timer_q >= 4'd5) begin // Small delay before calculating/UART
                    next_state_s = S_CALCULATE_SIMILARITY;
                end
            end
            S_CALCULATE_SIMILARITY: begin
                // similar_bits_count_q is updated in sequential block based on this state
                uart_current_segment_q <= UART_SEG_DECAY_VAL; // Start UART message
                next_state_s = S_UART_PREPARE_MSG;
            end

            // --- UART Output Sequence ---
            S_UART_PREPARE_MSG: begin
                // Prepare uart_data_segment_str_q and uart_data_segment_len_q based on uart_current_segment_q
                case (uart_current_segment_q)
                    UART_SEG_DECAY_VAL: begin
                        logic [15:0] val = current_decay_ms_for_uart_q;
                        uart_data_segment_str_q[0] = (val / 1000) % 10 + "0"; // Thousands
                        uart_data_segment_str_q[1] = (val / 100)  % 10 + "0"; // Hundreds
                        uart_data_segment_str_q[2] = (val / 10)   % 10 + "0"; // Tens
                        uart_data_segment_str_q[3] = (val / 1)    % 10 + "0"; // Ones
                        uart_data_segment_len_q = 4; // Fixed 4 digits
                    end
                    UART_SEG_COMMA1, UART_SEG_COMMA2, UART_SEG_COMMA3: begin
                        uart_data_segment_str_q[0] = ",";
                        uart_data_segment_len_q = 1;
                    end
                    UART_SEG_WRITE_HEX: begin
                        for (int i=0; i<32; i++) begin // 128 bits / 4 bits_per_hex_char = 32 chars
                            uart_data_segment_str_q[i] = hex_to_ascii(write_data_q[(127 - i*4) -: 4]);
                        end
                        uart_data_segment_len_q = 32;
                    end
                    UART_SEG_READ_HEX: begin
                        for (int i=0; i<32; i++) begin
                            uart_data_segment_str_q[i] = hex_to_ascii(read_data_q[(127 - i*4) -: 4]);
                        end
                        uart_data_segment_len_q = 32;
                    end
                    UART_SEG_SIMILARITY_VAL: begin
                        logic [7:0] val = similar_bits_count_q;
                        uart_data_segment_str_q[0] = (val / 100) % 10 + "0"; // Hundreds
                        uart_data_segment_str_q[1] = (val / 10)  % 10 + "0"; // Tens
                        uart_data_segment_str_q[2] = (val / 1)   % 10 + "0"; // Ones
                        uart_data_segment_len_q = 3; // Fixed 3 digits
                    end
                    UART_SEG_CR: begin
                        uart_data_segment_str_q[0] = "\r"; // Carriage Return
                        uart_data_segment_len_q = 1;
                    end
                    UART_SEG_LF: begin
                        uart_data_segment_str_q[0] = "\n"; // Line Feed
                        uart_data_segment_len_q = 1;
                    end
                    UART_SEG_DONE: begin // Should not prepare here, this is a transition target
                        uart_data_segment_len_q = 0;
                    end
                    default: uart_data_segment_len_q = 0;
                endcase
                if (uart_data_segment_len_q > 0) begin
                    next_state_s = S_UART_SEND_CHAR;
                end else if (uart_current_segment_q == UART_SEG_DONE) { // All segments sent
                     next_state_s = S_CHECK_FOR_MORE_TESTS;
                } else { // Error or empty segment, try next
                    // This logic needs to be robust: if len is 0, advance segment
                    uart_current_segment_q <= uart_current_segment_q + 1; // Advance to next segment
                    // next_state_s remains S_UART_PREPARE_MSG to re-evaluate
                }
            end

            S_UART_SEND_CHAR: begin
                if (uart_char_ptr_q < uart_data_segment_len_q) begin
                    uart_tx_data_s = uart_data_segment_str_q[uart_char_ptr_q];
                    uart_tx_start_s = 1'b1;
                    next_state_s = S_UART_WAIT_TX_DONE;
                end else begin // Current segment fully sent
                    uart_current_segment_q <= uart_current_segment_q + 1; // Advance to next segment
                    if (uart_current_segment_q >= UART_SEG_DONE) begin // Check if all segments are done
                        next_state_s = S_CHECK_FOR_MORE_TESTS;
                    end else begin
                        next_state_s = S_UART_PREPARE_MSG; // Prepare next segment
                    end
                end
            end

            S_UART_WAIT_TX_DONE: begin
                if (!uart_tx_busy_sync1) begin // UART is ready for next char
                    next_state_s = S_UART_SEND_CHAR; // Send next char of current segment (ptr incremented in seq logic)
                                                    // Actually, ptr should be incremented here before going back
                                                    // Or, S_UART_SEND_CHAR handles completion of segment
                }
                // Stays in S_UART_WAIT_TX_DONE if busy
            end
            
            // --- Loop Control ---
            S_CHECK_FOR_MORE_TESTS: begin
                if (tests_run_for_current_decay_q < NUM_TESTS_PER_DECAY_SETTING - 1) begin
                    // More tests for current decay setting
                    next_state_s = S_START_TEST_ITERATION; 
                end else begin // All tests for current decay done
                    if (current_decay_idx_q < NUM_DECAY_SETTINGS - 1) begin
                        // More decay settings to test
                        next_state_s = S_START_NEW_DECAY_SETTING;
                    end else begin
                        // All decay settings and tests complete
                        next_state_s = S_ALL_TESTS_COMPLETE;
                    end
                end
            end

            S_ALL_TESTS_COMPLETE: begin
                if (start_btn_edge) begin
                    next_state_s = S_IDLE; // Restart entire sequence
                end
            end
            
            default: begin
                next_state_s = S_IDLE;
            end
        endcase
    end
    
    // LED outputs
    always_comb begin
        status_led0_o = (current_state_q != S_IDLE) && (current_state_q != S_ALL_TESTS_COMPLETE);
        // status_led1_o and status_led2_o reflect the result of the *last completed test* when in S_ALL_TESTS_COMPLETE
        if (current_state_q == S_ALL_TESTS_COMPLETE || (current_state_q == S_CHECK_FOR_MORE_TESTS && uart_current_segment_q == UART_SEG_DONE)) begin
             status_led1_o = (similar_bits_count_q == 128); // Success if all bits matched
             status_led2_o = (similar_bits_count_q != 128); // Fail otherwise
        end else begin
             status_led1_o = 1'b0;
             status_led2_o = 1'b0;
        end
        status_led3_o = uart_tx_busy; // Direct from UART module (clk100mhz domain)
                                      // Or use uart_tx_busy_sync1 for FSM domain indication
    end

    // Helper function for hex to ASCII conversion
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 10)
                hex_to_ascii = hex + "0";
            else
                hex_to_ascii = hex - 10 + "A";
        end
    endfunction

    // UART instance
    // Baud rate = clk / CLKS_PER_BIT. For 115200 baud with 100MHz clk:
    // CLKS_PER_BIT = 100,000,000 / 115200 = ~868
    uart_tx #(
        .CLKS_PER_BIT(868) 
    ) u_uart_tx (
        .clk(clk100mhz_i),
        .rst(rst_for_uart), // Reset for UART module
        .tx_start(uart_tx_start_s), // FSM controls start, needs CDC if domains differ significantly
        .tx_data(uart_tx_data_s),   // FSM provides data
        .tx_serial(uart_txd_o),
        .tx_busy(uart_tx_busy),
        .tx_done() // Not used here
    );

    // ILA signals for debugging (subset)
    logic [6:0]  ila_state_q;
    logic [15:0] ila_timer_q_low; // Lower 16 bits of timer
    logic [7:0]  ila_similar_bits;
    logic [$clog2(NUM_DECAY_SETTINGS)-1:0] ila_decay_idx;
    logic [$clog2(NUM_TESTS_PER_DECAY_SETTING):0] ila_test_iter;
    logic [3:0] ila_uart_segment;
    logic [4:0] ila_uart_char_ptr;
    
    always_comb begin
        ila_state_q = current_state_q;
        ila_timer_q_low = timer_q[15:0];
        ila_similar_bits = similar_bits_count_q;
        ila_decay_idx = current_decay_idx_q;
        ila_test_iter = tests_run_for_current_decay_q;
        ila_uart_segment = uart_current_segment_q;
        ila_uart_char_ptr = uart_char_ptr_q;
    end

    // ILA instance (adjust probe connections to match your ILA configuration)
    // ila_0 u_ila (
    //     .clk(clk_phy_sys),
    //     .probe0(ila_state_q),          // Current FSM state
    //     .probe1(ila_timer_q_low),      // Timer value (lower bits)
    //     .probe2(dfi_address_s[9:0]),   // DFI address (lower bits for column)
    //     .probe3(dfi_bank_s),           // DFI bank
    //     .probe4({dfi_ras_n_s, dfi_cas_n_s, dfi_we_n_s}), // DFI command type
    //     .probe5(dfi_wrdata_en_s),      // DFI write enable
    //     .probe6(dfi_rddata_valid_r),   // DFI read valid
    //     .probe7(ila_similar_bits),     // Calculated similar bits
    //     .probe8(ila_decay_idx),        // Current decay setting index
    //     .probe9(ila_test_iter),        // Current test iteration for decay setting
    //     .probe10(ila_uart_segment),    // UART message segment
    //     .probe11(ila_uart_char_ptr),   // UART character pointer in segment
    //     .probe12(read_data_q[31:0]),   // Sample of read data
    //     .probe13(write_data_q[31:0]),  // Sample of write data
    //     .probe14(start_btn_edge),
    //     .probe15(uart_tx_busy_sync1)
    // );

endmodule

// Basic UART TX module (ensure this matches your project's UART module)
// This is a placeholder if you don't have one.
// A real UART module would handle start/stop bits, parity, etc.
module uart_tx #(
    parameter CLKS_PER_BIT = 868 // Default for 115200 baud @ 100MHz
) (
    input wire clk,
    input wire rst,
    input wire tx_start,      // Start transmission signal (pulse)
    input wire [7:0] tx_data, // Data to transmit
    output logic tx_serial,   // Serial output
    output logic tx_busy,     // UART is busy transmitting
    output logic tx_done      // Transmission of one byte complete (pulse)
);
    typedef enum logic [3:0] {
        S_IDLE,
        S_START_BIT,
        S_DATA_BITS,
        S_STOP_BIT
    } uart_state_t;

    uart_state_t current_state, next_state;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_counter;
    logic [3:0] bit_counter; // For 8 data bits + start/stop
    logic [7:0] data_reg;

    assign tx_done = (current_state == S_STOP_BIT) && (clk_counter == CLKS_PER_BIT - 1);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= S_IDLE;
            clk_counter <= 0;
            bit_counter <= 0;
            tx_serial <= 1'b1; // Idle high
            tx_busy <= 1'b0;
            data_reg <= 8'h00;
        end else begin
            current_state <= next_state;
            clk_counter <= (current_state == S_IDLE || clk_counter == CLKS_PER_BIT -1) ? 0 : clk_counter + 1;
            
            if (current_state == S_IDLE && tx_start) begin
                data_reg <= tx_data;
            end

            if (clk_counter == CLKS_PER_BIT - 1) begin
                if (current_state == S_DATA_BITS || current_state == S_START_BIT) begin
                    bit_counter <= bit_counter + 1;
                end else if (current_state == S_STOP_BIT) begin
                     bit_counter <= 0; // Reset for next byte
                end
            end
            
            case (current_state)
                S_IDLE: tx_busy <= 1'b0;
                S_START_BIT, S_DATA_BITS, S_STOP_BIT: tx_busy <= 1'b1;
            endcase

            // Serial output logic
            case (current_state)
                S_IDLE: tx_serial <= 1'b1;
                S_START_BIT: tx_serial <= 1'b0;
                S_DATA_BITS: tx_serial <= data_reg[bit_counter-1]; // Send LSB first after start bit
                S_STOP_BIT: tx_serial <= 1'b1;
                default: tx_serial <= 1'b1;
            endcase
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            S_IDLE: begin
                if (tx_start) begin
                    next_state = S_START_BIT;
                end
            end
            S_START_BIT: begin
                if (clk_counter == CLKS_PER_BIT - 1) begin
                    next_state = S_DATA_BITS;
                end
            end
            S_DATA_BITS: begin
                if (clk_counter == CLKS_PER_BIT - 1) begin
                    if (bit_counter == 8) begin // 8 data bits sent (bit_counter goes 1 to 8)
                        next_state = S_STOP_BIT;
                    end
                end
            end
            S_STOP_BIT: begin
                if (clk_counter == CLKS_PER_BIT - 1) begin
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end
endmodule

