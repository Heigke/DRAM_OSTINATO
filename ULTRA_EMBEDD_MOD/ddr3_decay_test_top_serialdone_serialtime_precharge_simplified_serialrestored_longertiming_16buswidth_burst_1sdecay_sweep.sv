// ddr3_decay_sweep_top.sv
// Enhanced DDR3 decay test with address and timing sweep capabilities
module ddr3_decay_sweep_top (
    input wire clk100mhz_i,      // Board clock 100MHz
    input wire reset_btn_i,      // Active high reset button for whole system
    input wire start_btn_i,      // Button to start the DDR3 test sequence

    // LEDs for status
    output logic status_led0_o,    // Test in progress / Idle
    output logic status_led1_o,    // Current test pass
    output logic status_led2_o,    // Current test fail
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
        S_IDLE                      = 6'd0,
        S_INIT_RESET                = 6'd1,
        S_INIT_RESET_WAIT           = 6'd2,
        S_INIT_CKE_LOW              = 6'd3,
        S_INIT_STABLE               = 6'd4,
        S_INIT_MRS2                 = 6'd5,
        S_INIT_MRS3                 = 6'd6,
        S_INIT_MRS1                 = 6'd7,
        S_INIT_MRS0                 = 6'd8,
        S_INIT_ZQCL                 = 6'd9,
        S_INIT_DONE                 = 6'd10,
        S_WRITE_ACTIVATE            = 6'd11,
        S_WRITE_ACTIVATE_WAIT       = 6'd12,
        S_WRITE_CMD                 = 6'd13,
        S_WRITE_BURST_0             = 6'd14,
        S_WRITE_BURST_1             = 6'd15,
        S_WRITE_BURST_2             = 6'd16,
        S_WRITE_BURST_3             = 6'd17,
        S_WRITE_WAIT                = 6'd18,
        S_PRECHARGE_AFTER_WRITE     = 6'd19,
        S_PRECHARGE_WAIT            = 6'd20,
        S_DECAY_WAIT                = 6'd21,
        S_READ_ACTIVATE             = 6'd22,
        S_READ_ACTIVATE_WAIT        = 6'd23,
        S_READ_CMD                  = 6'd24,
        S_READ_WAIT                 = 6'd25,
        S_READ_CAPTURE_0            = 6'd26,
        S_READ_CAPTURE_1            = 6'd27,
        S_READ_CAPTURE_2            = 6'd28,
        S_READ_CAPTURE_3            = 6'd29,
        S_READ_DONE                 = 6'd30,
        S_UART_START                = 6'd31,
        S_UART_SEND_CHAR            = 6'd32,
        S_UART_WAIT                 = 6'd33,
        S_NEXT_MEASUREMENT          = 6'd34,
        S_NEXT_ADDRESS              = 6'd35,
        S_NEXT_DECAY_TIME           = 6'd36,
        S_DONE                      = 6'd37
    } state_t;
    
    state_t current_state_q, next_state_s;

    // Timing parameters
    localparam T_RESET_US           = 24'd40_000;   // 200us @ 200MHz
    localparam T_STABLE_US          = 24'd100_000;  // 500us @ 200MHz  
    localparam T_INIT_WAIT          = 24'd1024;     // General init wait
    localparam T_MODE_REG_SET       = 24'd20;       // tMRD + margin
    localparam T_ZQINIT             = 24'd512;      // tZQINIT
    localparam T_ACTIVATE_TO_RW     = 24'd20;       // tRCD + margin
    localparam T_WRITE_TO_PRECHARGE = 24'd20;       // tWR + margin
    localparam T_PRECHARGE          = 24'd20;       // tRP + margin
    localparam T_READ_LATENCY       = TPHY_RDLAT_C + CAS_LATENCY_C + 4; // CL + PHY latency

    logic [31:0] timer_q;

    // Test pattern generation
    logic [127:0] write_data_q;  // Full burst data (8 x 16-bit)
    logic [127:0] read_data_q;   // Full burst data captured
    logic        init_done_q;
    logic [2:0]  burst_cnt_q;    // Burst counter for write/read
    logic [2:0]  read_burst_cnt_q; // Read burst counter
    
    // Sweep parameters
    logic [7:0]  decay_time_idx_q;    // Index into decay time array (0-19 for 20 steps)
    logic [9:0]  address_idx_q;       // Address sweep index
    logic [3:0]  measurement_cnt_q;   // Repeat measurement counter
    logic [31:0] decay_timer_target_q; // Current decay time in cycles
    
    // Test results
    logic        test_pass_q;
    logic [7:0]  bit_errors_q;        // Count of bit errors in current test
    
    // Address generation
    logic [13:0] current_row_q;
    logic [9:0]  current_col_q;
    logic [2:0]  current_bank_q;
    
    // Constants for sweep
    localparam MEASUREMENTS_PER_POINT = 5;
    localparam NUM_ADDRESSES = 100;      // Test 100 different addresses
    localparam NUM_DECAY_TIMES = 20;     // 20 decay times from 1ms to 1000ms
    
    // UART control
    logic uart_tx_busy;
    logic uart_tx_start;
    logic [7:0] uart_tx_data;
    logic [7:0] uart_msg_idx_q;
    logic [3:0] uart_msg_type_q;  // 0=header, 1=data, 2=newline
    logic [15:0] uart_data_word_q; // Current 16-bit word to send

    // Start button synchronization
    logic start_btn_sync, start_btn_prev, start_btn_edge;
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            start_btn_sync <= 1'b0;
            start_btn_prev <= 1'b0;
        end else begin
            start_btn_sync <= start_btn_i;
            start_btn_prev <= start_btn_sync;
        end
    end
    assign start_btn_edge = start_btn_sync & ~start_btn_prev;

    // Calculate decay time based on index (exponential sweep from 1ms to 1000ms)
    function [31:0] get_decay_time_cycles;
        input [7:0] idx;
        real base_ms;
        real exp_factor;
        real time_ms;
        begin
            // Exponential sweep: time_ms = 1 * 10^((idx/19)*3)
            // This gives us 1ms to 1000ms in 20 steps
            base_ms = 1.0;
            exp_factor = real'(idx) * 3.0 / 19.0;
            time_ms = base_ms * (10.0 ** exp_factor);
            get_decay_time_cycles = $rtoi(time_ms * 200000.0); // Convert ms to cycles at 200MHz
        end
    endfunction

    // Generate pseudo-random test pattern based on address
    function [127:0] generate_test_pattern;
        input [13:0] row;
        input [9:0] col;
        input [2:0] bank;
        logic [31:0] seed;
        begin
            seed = {row, col, bank, 5'b10101};
            // Simple LFSR-based pattern generation
            generate_test_pattern[31:0]   = seed ^ 32'hA5A5A5A5;
            generate_test_pattern[63:32]  = (seed << 1) ^ 32'h5A5A5A5A;
            generate_test_pattern[95:64]  = (seed << 2) ^ 32'hF0F0F0F0;
            generate_test_pattern[127:96] = (seed << 3) ^ 32'h0F0F0F0F;
        end
    endfunction

    // Count bit errors between write and read data
    function [7:0] count_bit_errors;
        input [127:0] expected;
        input [127:0] actual;
        integer i;
        begin
            count_bit_errors = 0;
            for (i = 0; i < 128; i = i + 1) begin
                if (expected[i] != actual[i])
                    count_bit_errors = count_bit_errors + 1;
            end
            // Cap at 255
            if (count_bit_errors > 255)
                count_bit_errors = 255;
        end
    endfunction

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q <= S_IDLE;
            timer_q <= 32'd0;
            write_data_q <= 128'd0;
            read_data_q <= 128'd0;
            init_done_q <= 1'b0;
            burst_cnt_q <= 3'd0;
            read_burst_cnt_q <= 3'd0;
            uart_msg_idx_q <= 8'd0;
            uart_msg_type_q <= 4'd0;
            decay_time_idx_q <= 8'd0;
            address_idx_q <= 10'd0;
            measurement_cnt_q <= 4'd0;
            decay_timer_target_q <= 32'd0;
            test_pass_q <= 1'b0;
            bit_errors_q <= 8'd0;
            current_row_q <= 14'd0;
            current_col_q <= 10'd0;
            current_bank_q <= 3'd0;
            uart_data_word_q <= 16'd0;
        end else begin
            current_state_q <= next_state_s;
            
            // Update timer
            if (current_state_q != next_state_s) begin
                timer_q <= 32'd0;
            end else begin
                timer_q <= timer_q + 1;
            end
            
            // Set init done flag
            if (current_state_q == S_INIT_DONE && next_state_s == S_WRITE_ACTIVATE) begin
                init_done_q <= 1'b1;
            end
            
            // Generate new address when moving to next address
            if (current_state_q == S_NEXT_ADDRESS) begin
                // Simple address generation - spread across rows/cols/banks
                current_bank_q <= address_idx_q[2:0];
                current_row_q <= {4'd0, address_idx_q[9:0]};
                current_col_q <= {address_idx_q[7:0], 2'b00}; // Word aligned
                
                // Generate test pattern for this address
                write_data_q <= generate_test_pattern(current_row_q, current_col_q, current_bank_q);
            end
            
            // Update decay timer target
            if (current_state_q == S_PRECHARGE_WAIT && next_state_s == S_DECAY_WAIT) begin
                decay_timer_target_q <= get_decay_time_cycles(decay_time_idx_q);
            end
            
            // Handle burst counter for writes
            if (current_state_q == S_WRITE_CMD) begin
                burst_cnt_q <= 3'd0;
            end else if (current_state_q >= S_WRITE_BURST_0 && current_state_q <= S_WRITE_BURST_3) begin
                burst_cnt_q <= burst_cnt_q + 1;
            end
            
            // Handle read data capture
            if (current_state_q == S_READ_CMD) begin
                read_burst_cnt_q <= 3'd0;
            end else if (dfi_rddata_valid_r && current_state_q >= S_READ_CAPTURE_0 && current_state_q <= S_READ_CAPTURE_3) begin
                // Capture 32-bit data per cycle (2 x 16-bit words)
                case (read_burst_cnt_q)
                    3'd0: read_data_q[31:0]   <= dfi_rddata_r;
                    3'd1: read_data_q[63:32]  <= dfi_rddata_r;
                    3'd2: read_data_q[95:64]  <= dfi_rddata_r;
                    3'd3: read_data_q[127:96] <= dfi_rddata_r;
                endcase
                read_burst_cnt_q <= read_burst_cnt_q + 1;
            end
            
            // Check test results
            if (current_state_q == S_READ_DONE) begin
                bit_errors_q <= count_bit_errors(write_data_q, read_data_q);
                test_pass_q <= (read_data_q == write_data_q);
            end
            
            // UART message control
            if (current_state_q == S_UART_WAIT && next_state_s == S_UART_SEND_CHAR) begin
                uart_msg_idx_q <= uart_msg_idx_q + 1;
            end else if (current_state_q != S_UART_SEND_CHAR && current_state_q != S_UART_WAIT) begin
                uart_msg_idx_q <= 8'd0;
            end
            
            // Increment counters
            if (current_state_q == S_NEXT_MEASUREMENT) begin
                measurement_cnt_q <= measurement_cnt_q + 1;
            end
            
            if (current_state_q == S_NEXT_ADDRESS) begin
                address_idx_q <= address_idx_q + 1;
                measurement_cnt_q <= 4'd0;
            end
            
            if (current_state_q == S_NEXT_DECAY_TIME) begin
                decay_time_idx_q <= decay_time_idx_q + 1;
                address_idx_q <= 10'd0;
                measurement_cnt_q <= 4'd0;
            end
            
            // Reset on idle
            if (current_state_q == S_IDLE) begin
                decay_time_idx_q <= 8'd0;
                address_idx_q <= 10'd0;
                measurement_cnt_q <= 4'd0;
                init_done_q <= 1'b0;
            end
        end
    end

    // State machine combinational logic
    always_comb begin
        // Default values
        next_state_s = current_state_q;
        uart_tx_start = 1'b0;
        uart_tx_data = 8'h00;
        
        // Default DDR3 signals (NOP)
        dfi_cs_n_s = 1'b0;  // Keep chip selected
        dfi_ras_n_s = 1'b1;
        dfi_cas_n_s = 1'b1;
        dfi_we_n_s = 1'b1;
        dfi_cke_s = 1'b1;
        dfi_reset_n_s = 1'b1;
        dfi_odt_s = 1'b0;
        dfi_address_s = 15'd0;
        dfi_bank_s = 3'd0;
        dfi_wrdata_s = 32'd0;
        dfi_wrdata_en_s = 1'b0;
        dfi_wrdata_mask_s = 4'h0;
        dfi_rddata_en_s = 1'b0;
        
        case (current_state_q)
            S_IDLE: begin
                dfi_cs_n_s = 1'b1;
                dfi_cke_s = 1'b0;
                if (start_btn_edge) begin
                    next_state_s = S_INIT_RESET;
                end
            end
            
            // Init states (same as before)
            S_INIT_RESET: begin
                dfi_reset_n_s = 1'b0;
                dfi_cke_s = 1'b0;
                next_state_s = S_INIT_RESET_WAIT;
            end
            
            S_INIT_RESET_WAIT: begin
                dfi_reset_n_s = 1'b0;
                dfi_cke_s = 1'b0;
                if (timer_q >= T_RESET_US) begin
                    next_state_s = S_INIT_CKE_LOW;
                end
            end
            
            S_INIT_CKE_LOW: begin
                dfi_reset_n_s = 1'b1;
                dfi_cke_s = 1'b0;
                if (timer_q >= T_STABLE_US) begin
                    next_state_s = S_INIT_STABLE;
                end
            end
            
            S_INIT_STABLE: begin
                dfi_cke_s = 1'b1;
                if (timer_q >= T_INIT_WAIT) begin
                    next_state_s = S_INIT_MRS2;
                end
            end
            
            S_INIT_MRS2: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b010;
                dfi_address_s = 15'd0;
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS3;
                end
            end
            
            S_INIT_MRS3: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b011;
                dfi_address_s = 15'd0;
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS1;
                end
            end
            
            S_INIT_MRS1: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b001;
                dfi_address_s = 15'b00000_00_0_01_0_00_0;
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS0;
                end
            end
            
            S_INIT_MRS0: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b000;
                // MRS0: BL=8, Sequential, CL=6, DLL Reset
                dfi_address_s = 15'b000_0_010_1_0_000_0_0_00;
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_ZQCL;
                end
            end
            
            S_INIT_ZQCL: begin
                dfi_we_n_s = 1'b0;
                dfi_address_s[10] = 1'b1;
                if (timer_q >= T_ZQINIT) begin
                    next_state_s = S_INIT_DONE;
                end
            end
            
            S_INIT_DONE: begin
                if (timer_q >= T_INIT_WAIT) begin
                    next_state_s = S_WRITE_ACTIVATE;
                end
            end
            
            // Write states with proper burst handling
            S_WRITE_ACTIVATE: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                dfi_bank_s = current_bank_q;
                dfi_address_s = {1'b0, current_row_q};
                next_state_s = S_WRITE_ACTIVATE_WAIT;
            end
            
            S_WRITE_ACTIVATE_WAIT: begin
                if (timer_q >= T_ACTIVATE_TO_RW) begin
                    next_state_s = S_WRITE_CMD;
                end
            end
            
            S_WRITE_CMD: begin
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = current_bank_q;
                dfi_address_s = {5'd0, current_col_q};
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_0;
            end
            
            // Write burst - 4 cycles for BL8 with 32-bit interface
            S_WRITE_BURST_0: begin
                dfi_wrdata_s = write_data_q[31:0];
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_1;
            end
            
            S_WRITE_BURST_1: begin
                dfi_wrdata_s = write_data_q[63:32];
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_2;
            end
            
            S_WRITE_BURST_2: begin
                dfi_wrdata_s = write_data_q[95:64];
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_BURST_3;
            end
            
            S_WRITE_BURST_3: begin
                dfi_wrdata_s = write_data_q[127:96];
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_WAIT;
            end
            
            S_WRITE_WAIT: begin
                dfi_odt_s = 1'b0;
                if (timer_q >= T_WRITE_TO_PRECHARGE) begin
                    next_state_s = S_PRECHARGE_AFTER_WRITE;
                end
            end
            
            S_PRECHARGE_AFTER_WRITE: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                dfi_address_s[10] = 1'b1; // All banks
                next_state_s = S_PRECHARGE_WAIT;
            end
            
            S_PRECHARGE_WAIT: begin
                if (timer_q >= T_PRECHARGE) begin
                    next_state_s = S_DECAY_WAIT;
                end
            end
            
            S_DECAY_WAIT: begin
                if (timer_q >= decay_timer_target_q) begin
                    next_state_s = S_READ_ACTIVATE;
                end
            end
            
            // Read states with proper burst handling
            S_READ_ACTIVATE: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                dfi_bank_s = current_bank_q;
                dfi_address_s = {1'b0, current_row_q};
                next_state_s = S_READ_ACTIVATE_WAIT;
            end
            
            S_READ_ACTIVATE_WAIT: begin
                if (timer_q >= T_ACTIVATE_TO_RW) begin
                    next_state_s = S_READ_CMD;
                end
            end
            
            S_READ_CMD: begin
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b1;
                dfi_bank_s = current_bank_q;
                dfi_address_s = {5'd0, current_col_q};
                dfi_rddata_en_s = 1'b1;
                next_state_s = S_READ_WAIT;
            end
            
            S_READ_WAIT: begin
                dfi_rddata_en_s = 1'b1;
                if (timer_q >= T_READ_LATENCY) begin
                    next_state_s = S_READ_CAPTURE_0;
                end
            end
            
            // Read capture states - wait for all burst data
            S_READ_CAPTURE_0: begin
                dfi_rddata_en_s = 1'b1;
                if (read_burst_cnt_q >= 3'd1) begin
                    next_state_s = S_READ_CAPTURE_1;
                end
            end
            
            S_READ_CAPTURE_1: begin
                dfi_rddata_en_s = 1'b1;
                if (read_burst_cnt_q >= 3'd2) begin
                    next_state_s = S_READ_CAPTURE_2;
                end
            end
            
            S_READ_CAPTURE_2: begin
                dfi_rddata_en_s = 1'b1;
                if (read_burst_cnt_q >= 3'd3) begin
                    next_state_s = S_READ_CAPTURE_3;
                end
            end
            
            S_READ_CAPTURE_3: begin
                if (read_burst_cnt_q >= 3'd4) begin
                    next_state_s = S_READ_DONE;
                end
            end
            
            S_READ_DONE: begin
                if (timer_q >= 4'd10) begin
                    next_state_s = S_UART_START;
                end
            end
            
            // UART states - send comprehensive test data
            S_UART_START: begin
                if (!uart_tx_busy) begin
                    next_state_s = S_UART_SEND_CHAR;
                end
            end
            
            S_UART_SEND_CHAR: begin
                uart_tx_start = 1'b1;
                
                // Format: "DT:xxxxx,ADDR:xxxx,MEAS:x,ERR:xxx,DATA:xxxxxxxxxxxxxxxx\r\n"
                case (uart_msg_idx_q)
                    // "DT:" - Decay time in ms
                    8'd0: uart_tx_data = "D";
                    8'd1: uart_tx_data = "T";
                    8'd2: uart_tx_data = ":";
                    8'd3: uart_tx_data = hex_to_ascii(decay_timer_target_q[31:28]);
                    8'd4: uart_tx_data = hex_to_ascii(decay_timer_target_q[27:24]);
                    8'd5: uart_tx_data = hex_to_ascii(decay_timer_target_q[23:20]);
                    8'd6: uart_tx_data = hex_to_ascii(decay_timer_target_q[19:16]);
                    8'd7: uart_tx_data = hex_to_ascii(decay_timer_target_q[15:12]);
                    8'd8: uart_tx_data = ",";
                    
                    // "ADDR:" - Address (bank, row[7:0], col[7:0])
                    8'd9:  uart_tx_data = "A";
                    8'd10: uart_tx_data = "D";
                    8'd11: uart_tx_data = "D";
                    8'd12: uart_tx_data = "R";
                    8'd13: uart_tx_data = ":";
                    8'd14: uart_tx_data = hex_to_ascii({1'b0, current_bank_q});
                    8'd15: uart_tx_data = hex_to_ascii(current_row_q[11:8]);
                    8'd16: uart_tx_data = hex_to_ascii(current_row_q[7:4]);
                    8'd17: uart_tx_data = hex_to_ascii(current_row_q[3:0]);
                    8'd18: uart_tx_data = hex_to_ascii(current_col_q[9:6]);
                    8'd19: uart_tx_data = hex_to_ascii(current_col_q[5:2]);
                    8'd20: uart_tx_data = ",";
                    
                    // "MEAS:" - Measurement number
                    8'd21: uart_tx_data = "M";
                    8'd22: uart_tx_data = "E";
                    8'd23: uart_tx_data = "A";
                    8'd24: uart_tx_data = "S";
                    8'd25: uart_tx_data = ":";
                    8'd26: uart_tx_data = hex_to_ascii(measurement_cnt_q);
                    8'd27: uart_tx_data = ",";
                    
                    // "ERR:" - Bit errors
                    8'd28: uart_tx_data = "E";
                    8'd29: uart_tx_data = "R";
                    8'd30: uart_tx_data = "R";
                    8'd31: uart_tx_data = ":";
                    8'd32: uart_tx_data = hex_to_ascii(bit_errors_q[7:4]);
                    8'd33: uart_tx_data = hex_to_ascii(bit_errors_q[3:0]);
                    8'd34: uart_tx_data = ",";
                    
                    // "PASS:" - Pass/Fail
                    8'd35: uart_tx_data = "P";
                    8'd36: uart_tx_data = "A";
                    8'd37: uart_tx_data = "S";
                    8'd38: uart_tx_data = "S";
                    8'd39: uart_tx_data = ":";
                    8'd40: uart_tx_data = test_pass_q ? "1" : "0";
                    8'd41: uart_tx_data = ",";
                    
                    // "RD:" - First 32 bits of read data
                    8'd42: uart_tx_data = "R";
                    8'd43: uart_tx_data = "D";
                    8'd44: uart_tx_data = ":";
                    8'd45: uart_tx_data = hex_to_ascii(read_data_q[31:28]);
                    8'd46: uart_tx_data = hex_to_ascii(read_data_q[27:24]);
                    8'd47: uart_tx_data = hex_to_ascii(read_data_q[23:20]);
                    8'd48: uart_tx_data = hex_to_ascii(read_data_q[19:16]);
                    8'd49: uart_tx_data = hex_to_ascii(read_data_q[15:12]);
                    8'd50: uart_tx_data = hex_to_ascii(read_data_q[11:8]);
                    8'd51: uart_tx_data = hex_to_ascii(read_data_q[7:4]);
                    8'd52: uart_tx_data = hex_to_ascii(read_data_q[3:0]);
                    
                    // Newline
                    8'd53: uart_tx_data = "\r";
                    8'd54: uart_tx_data = "\n";
                    
                    default: uart_tx_data = " ";
                endcase
                
                next_state_s = S_UART_WAIT;
            end
            
            S_UART_WAIT: begin
                if (!uart_tx_busy) begin
                    if (uart_msg_idx_q >= 8'd54) begin
                        next_state_s = S_NEXT_MEASUREMENT;
                    end else begin
                        next_state_s = S_UART_SEND_CHAR;
                    end
                end
            end
            
            S_NEXT_MEASUREMENT: begin
                if (measurement_cnt_q >= MEASUREMENTS_PER_POINT - 1) begin
                    next_state_s = S_NEXT_ADDRESS;
                end else begin
                    next_state_s = S_WRITE_ACTIVATE; // Repeat test at same address
                end
            end
            
            S_NEXT_ADDRESS: begin
                if (address_idx_q >= NUM_ADDRESSES - 1) begin
                    next_state_s = S_NEXT_DECAY_TIME;
                end else begin
                    next_state_s = S_WRITE_ACTIVATE; // Test next address
                end
            end
            
            S_NEXT_DECAY_TIME: begin
                if (decay_time_idx_q >= NUM_DECAY_TIMES - 1) begin
                    next_state_s = S_DONE;
                end else begin
                    next_state_s = S_WRITE_ACTIVATE; // Test with next decay time
                end
            end
            
            S_DONE: begin
                if (start_btn_edge) begin
                    next_state_s = S_IDLE;
                end
            end
            
            default: begin
                next_state_s = S_IDLE;
            end
        endcase
    end
    
    // LED outputs
    always_comb begin
        status_led0_o = (current_state_q != S_IDLE) && (current_state_q != S_DONE);
        status_led1_o = test_pass_q && (current_state_q >= S_READ_DONE);
        status_led2_o = ~test_pass_q && (current_state_q >= S_READ_DONE);
        status_led3_o = uart_tx_busy;
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
    uart_tx #(
        .CLKS_PER_BIT(868)
    ) u_uart_tx (
        .clk(clk100mhz_i),
        .rst(rst_for_uart),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_data),
        .tx_serial(uart_txd_o),
        .tx_busy(uart_tx_busy),
        .tx_done()
    );

    // ILA signals for debugging
    logic [5:0]  ila_state;
    logic [31:0] ila_timer;
    logic        ila_wrdata_en;
    logic [31:0] ila_wrdata;
    logic        ila_rddata_valid;
    logic [31:0] ila_rddata;
    logic [127:0] ila_captured_data;
    logic [127:0] ila_write_data;
    logic [7:0]  ila_bit_errors;
    logic [7:0]  ila_decay_idx;
    logic [9:0]  ila_addr_idx;
    logic [3:0]  ila_meas_cnt;
    logic        ila_test_pass;
    
    always_comb begin
        ila_state = current_state_q;
        ila_timer = timer_q;
        ila_wrdata_en = dfi_wrdata_en_s;
        ila_wrdata = dfi_wrdata_s;
        ila_rddata_valid = dfi_rddata_valid_r;
        ila_rddata = dfi_rddata_r;
        ila_captured_data = read_data_q;
        ila_write_data = write_data_q;
        ila_bit_errors = bit_errors_q;
        ila_decay_idx = decay_time_idx_q;
        ila_addr_idx = address_idx_q;
        ila_meas_cnt = measurement_cnt_q;
        ila_test_pass = test_pass_q;
    end

    // ILA instance
    ila_0 u_ila (
        .clk(clk_phy_sys),
        .probe0(ila_state),
        .probe1({2'd0, ila_state}),
        .probe2(ila_timer[15:0]),
        .probe3(ila_test_pass),
        .probe4({5'd0, current_bank_q}),
        .probe5(current_col_q),
        .probe6(current_bank_q),
        .probe7(ila_wrdata_en),
        .probe8(ila_wrdata),
        .probe9(ila_rddata_valid),
        .probe10(ila_rddata),
        .probe11(ila_captured_data[31:0]),
        .probe12(ila_bit_errors),
        .probe13({4'd0, ila_meas_cnt}),
        .probe14((current_state_q == S_DECAY_WAIT)),
        .probe15(ila_decay_idx)
    );

endmodule
