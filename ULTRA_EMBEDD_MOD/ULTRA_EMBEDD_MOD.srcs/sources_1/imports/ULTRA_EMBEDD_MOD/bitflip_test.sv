// ddr3_decay_sweep_top.sv
// Sweeps decay times from 1ms to 3s and reports bit statistics via UART
module ddr3_decay_sweep_top (
    input wire clk100mhz_i,      // Board clock 100MHz
    input wire reset_btn_i,      // Active high reset button
    input wire start_btn_i,      // Button to start sweep

    // LEDs for status
    output logic status_led0_o,    // Test in progress
    output logic status_led1_o,    // Currently measuring
    output logic status_led2_o,    // Sweep complete
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
    logic clk_phy_sys;      // PHY system clock (200MHz)
    logic clk_phy_ddr;      // PHY DDR clock (400MHz)
    logic clk_phy_ddr90;    // PHY DDR clock 90-deg phase (400MHz)
    logic clk_idelay_ref;   // PHY IDELAYCTRL reference clock (200MHz)
    logic mmcm_locked;
    
    logic sys_rst_fsm_phy;  // Synchronized reset for FSM and PHY
    logic rst_for_uart;     // Synchronized reset for UART

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
    localparam TPHY_RDLAT_C  = 13;  
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
        S_WRITE_DATA                = 6'd14,
        S_WRITE_WAIT                = 6'd15,
        S_PRECHARGE_AFTER_WRITE     = 6'd16,
        S_PRECHARGE_WAIT            = 6'd17,
        S_DECAY_WAIT                = 6'd18,
        S_READ_ACTIVATE             = 6'd19,
        S_READ_ACTIVATE_WAIT        = 6'd20,
        S_READ_CMD                  = 6'd21,
        S_READ_DATA                 = 6'd22,
        S_READ_DONE                 = 6'd23,
        S_UART_START                = 6'd24,
        S_UART_SEND_CHAR            = 6'd25,
        S_UART_WAIT                 = 6'd26,
        S_NEXT_MEASUREMENT          = 6'd27,
        S_SWEEP_DONE                = 6'd28
    } state_t;
    
    state_t current_state_q, next_state_s;

    // Timing parameters
    localparam T_RESET_US           = 24'd40_000;   // 200us @ 200MHz
    localparam T_STABLE_US          = 24'd100_000;  // 500us @ 200MHz  
    localparam T_INIT_WAIT          = 24'd1024;     
    localparam T_MODE_REG_SET       = 24'd20;       
    localparam T_ZQINIT             = 24'd512;      
    localparam T_ACTIVATE_TO_RW     = 24'd20;       
    localparam T_WRITE_TO_PRECHARGE = 24'd30;       
    localparam T_PRECHARGE          = 24'd20;       

    // Decay time sweep parameters (in 200MHz cycles)
    localparam T_1MS   = 28'd200_000;      // 1ms
    localparam T_10MS  = 28'd2_000_000;    // 10ms
    localparam T_100MS = 28'd20_000_000;   // 100ms
    localparam T_500MS = 28'd100_000_000;  // 500ms
    localparam T_1S    = 28'd200_000_000;  // 1s
    localparam T_2S    = 28'd400_000_000;  // 2s (using 28 bits)
    localparam T_3S    = 28'd600_000_000;  // 3s (using 28 bits)

    // Registers
    logic [27:0] timer_q;
    logic [27:0] decay_time_q;       // Current decay time setting
    logic [127:0] write_data_q;      // All ones pattern
    logic [127:0] read_data_q;       // Read back data
    logic        init_done_q;
    logic [2:0]  write_burst_cnt_q;
    logic [3:0]  write_delay_cnt_q;
    logic [1:0]  rd_beat_cnt_q;
    logic [2:0]  rddata_en_cnt_q;
    logic [2:0]  rd_lat_cnt_q;
    logic        rd_window_open_q;
    
    // Measurement counters
    logic [7:0]  ones_count_q;       // Count of '1' bits read back
    logic [7:0]  zeros_count_q;      // Count of '0' bits read back
    logic [2:0]  measurement_idx_q;  // Which decay time we're testing
    logic [3:0]  repeat_count_q;     // Repeat counter for each decay time
    
    // UART control
    logic uart_tx_busy;
    logic uart_tx_start;
    logic [7:0] uart_tx_data;
    logic [5:0] uart_msg_idx_q;
    
    // Fixed test address and pattern
    localparam TEST_ROW  = 14'h0000;
    localparam TEST_COL  = 10'h000;   
    localparam TEST_BANK = 3'b000;
    localparam [127:0] ALL_ONES_PATTERN = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    
    // Number of measurements per decay time
    localparam MEASUREMENTS_PER_TIME = 4'd5;

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

    // Read burst done signal
    logic read_burst_done;
    assign read_burst_done = dfi_rddata_valid_r && (rd_beat_cnt_q == 2'd3);

    // 16-bit half-word swap functions
    function automatic [31:0] swap16(input [31:0] w);
        swap16 = {w[15:0], w[31:16]};
    endfunction

    function automatic [31:0] unswap16(input [31:0] w);
        unswap16 = {w[15:0], w[31:16]};
    endfunction

    // Bit counting function
    function automatic [7:0] count_ones(input [127:0] data);
        integer i;
        count_ones = 8'd0;
        for (i = 0; i < 128; i = i + 1) begin
            count_ones = count_ones + data[i];
        end
    endfunction

    // Get current decay time based on measurement index
    function automatic [27:0] get_decay_time(input [2:0] idx);
        case (idx)
            3'd0: get_decay_time = T_1MS;
            3'd1: get_decay_time = T_10MS;
            3'd2: get_decay_time = T_100MS;
            3'd3: get_decay_time = T_500MS;
            3'd4: get_decay_time = T_1S;
            3'd5: get_decay_time = T_2S;
            3'd6: get_decay_time = T_3S;
            default: get_decay_time = T_1MS;
        endcase
    endfunction

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q <= S_IDLE;
            timer_q <= 28'd0;
            write_data_q <= ALL_ONES_PATTERN;
            read_data_q <= 128'd0;
            init_done_q <= 1'b0;
            write_burst_cnt_q <= 3'd0;
            write_delay_cnt_q <= 4'd0;
            rd_beat_cnt_q <= 2'd0;
            rddata_en_cnt_q <= 3'd0;
            rd_lat_cnt_q <= 3'd0;
            rd_window_open_q <= 1'b0;
            uart_msg_idx_q <= 6'd0;
            ones_count_q <= 8'd0;
            zeros_count_q <= 8'd0;
            measurement_idx_q <= 3'd0;
            repeat_count_q <= 4'd0;
            decay_time_q <= T_1MS;
        end else begin
            current_state_q <= next_state_s;
            
            // Update timer
            if (current_state_q != next_state_s) begin
                timer_q <= 28'd0;
            end else begin
                timer_q <= timer_q + 1;
            end
            
            // Set init done flag
            if (current_state_q == S_INIT_DONE && next_state_s == S_WRITE_ACTIVATE) begin
                init_done_q <= 1'b1;
            end
            
            // Reset on idle
            if (current_state_q == S_IDLE) begin
                init_done_q <= 1'b0;
                write_burst_cnt_q <= 3'd0;
                write_delay_cnt_q <= 4'd0;
                rd_beat_cnt_q <= 2'd0;
                rddata_en_cnt_q <= 3'd0;
                rd_lat_cnt_q <= 3'd0;
                rd_window_open_q <= 1'b0;
                read_data_q <= 128'd0;
                measurement_idx_q <= 3'd0;
                repeat_count_q <= 4'd0;
                decay_time_q <= T_1MS;
            end
            
            // Update decay time when starting new measurement
            if (current_state_q == S_WRITE_ACTIVATE && timer_q == 0) begin
                decay_time_q <= get_decay_time(measurement_idx_q);
            end
            
            // Write delay counter and burst control
            if (current_state_q == S_WRITE_CMD) begin
                write_delay_cnt_q <= 4'd0;
                write_burst_cnt_q <= 3'd0;
            end else if (current_state_q == S_WRITE_DATA) begin
                if (write_delay_cnt_q < TPHY_WRLAT_C) begin
                    write_delay_cnt_q <= write_delay_cnt_q + 1;
                end else if (write_burst_cnt_q < 3'd3) begin
                    write_burst_cnt_q <= write_burst_cnt_q + 1;
                end
            end
            
            // Read latency and window management
            if (current_state_q == S_READ_CMD) begin
                rd_lat_cnt_q <= TPHY_RDLAT_C - 1;
                rddata_en_cnt_q <= 3'd0;
                rd_window_open_q <= 1'b0;
            end else if (current_state_q == S_READ_DATA) begin
                if (!rd_window_open_q) begin
                    if (rd_lat_cnt_q != 0) begin
                        rd_lat_cnt_q <= rd_lat_cnt_q - 1;
                    end else begin
                        rddata_en_cnt_q <= 3'd4;
                        rd_window_open_q <= 1'b1;
                    end
                end else if (rddata_en_cnt_q != 0) begin
                    rddata_en_cnt_q <= rddata_en_cnt_q - 1;
                end
            end
            
            // Clear window logic when leaving READ_DATA
            if (current_state_q == S_READ_DATA && read_burst_done) begin
                rddata_en_cnt_q <= 3'd0;
            end
            
            // Read beat counter
            if (current_state_q != S_READ_DATA) begin
                rd_beat_cnt_q <= 2'd0;
            end else if (dfi_rddata_valid_r) begin
                case (rd_beat_cnt_q)
                    2'd0: read_data_q[127:96] <= unswap16(dfi_rddata_r);
                    2'd1: read_data_q[95:64]  <= unswap16(dfi_rddata_r);
                    2'd2: read_data_q[63:32]  <= unswap16(dfi_rddata_r);
                    2'd3: read_data_q[31:0]   <= unswap16(dfi_rddata_r);
                endcase
                rd_beat_cnt_q <= rd_beat_cnt_q + 1;
            end
            
            // Count bits when read is done
            if (current_state_q == S_READ_DATA && next_state_s == S_READ_DONE) begin
                ones_count_q <= count_ones(read_data_q);
                zeros_count_q <= 8'd128 - count_ones(read_data_q);
            end
            
            // UART message control
            if (current_state_q == S_READ_DONE && next_state_s == S_UART_START) begin
                uart_msg_idx_q <= 6'd0;
            end else if (current_state_q == S_UART_WAIT && next_state_s == S_UART_SEND_CHAR) begin
                uart_msg_idx_q <= uart_msg_idx_q + 1;
            end
            
            // Update measurement counters
            if (current_state_q == S_UART_WAIT && next_state_s == S_NEXT_MEASUREMENT) begin
                uart_msg_idx_q <= 6'd0;
                if (repeat_count_q < MEASUREMENTS_PER_TIME - 1) begin
                    repeat_count_q <= repeat_count_q + 1;
                end else begin
                    repeat_count_q <= 4'd0;
                    if (measurement_idx_q < 3'd6) begin
                        measurement_idx_q <= measurement_idx_q + 1;
                    end
                end
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
        dfi_cs_n_s = 1'b0;
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
        dfi_rddata_en_s = (rddata_en_cnt_q != 0);
        
        case (current_state_q)
            S_IDLE: begin
                dfi_cs_n_s = 1'b1;
                dfi_cke_s = 1'b0;
                if (start_btn_edge) begin
                    next_state_s = S_INIT_RESET;
                end
            end
            
            // Init sequence (same as before)
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
            
            // Write sequence
            S_WRITE_ACTIVATE: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                dfi_bank_s = TEST_BANK;
                dfi_address_s = {1'b0, TEST_ROW};
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
                dfi_bank_s = TEST_BANK;
                dfi_address_s = {5'd0, TEST_COL};
                next_state_s = S_WRITE_DATA;
            end
            
            S_WRITE_DATA: begin
                dfi_odt_s = 1'b1;
                
                if (write_delay_cnt_q >= TPHY_WRLAT_C && write_burst_cnt_q < 3'd4) begin
                    dfi_wrdata_en_s = 1'b1;
                    dfi_wrdata_mask_s = 4'h0;
                    
                    case (write_burst_cnt_q)
                        3'd0: dfi_wrdata_s = swap16(write_data_q[127:96]);
                        3'd1: dfi_wrdata_s = swap16(write_data_q[95:64]);
                        3'd2: dfi_wrdata_s = swap16(write_data_q[63:32]);
                        3'd3: dfi_wrdata_s = swap16(write_data_q[31:0]);
                        default: dfi_wrdata_s = 32'd0;
                    endcase
                end
                
                if (write_burst_cnt_q == 3'd3 && write_delay_cnt_q >= TPHY_WRLAT_C) begin
                    next_state_s = S_WRITE_WAIT;
                end
            end
            
            S_WRITE_WAIT: begin
                if (timer_q >= T_WRITE_TO_PRECHARGE) begin
                    next_state_s = S_PRECHARGE_AFTER_WRITE;
                end
            end
            
            S_PRECHARGE_AFTER_WRITE: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                dfi_address_s[10] = 1'b1;
                next_state_s = S_PRECHARGE_WAIT;
            end
            
            S_PRECHARGE_WAIT: begin
                if (timer_q >= T_PRECHARGE) begin
                    next_state_s = S_DECAY_WAIT;
                end
            end
            
            S_DECAY_WAIT: begin
                // Wait for the current decay time setting
                if (timer_q >= decay_time_q) begin
                    next_state_s = S_READ_ACTIVATE;
                end
            end
            
            // Read sequence
            S_READ_ACTIVATE: begin
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b1;
                dfi_bank_s = TEST_BANK;
                dfi_address_s = {1'b0, TEST_ROW};
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
                dfi_bank_s = TEST_BANK;
                dfi_address_s = {5'd0, TEST_COL};
                next_state_s = S_READ_DATA;
            end
            
            S_READ_DATA: begin
                if (read_burst_done) begin
                    next_state_s = S_READ_DONE;
                end
            end
            
            S_READ_DONE: begin
                if (timer_q >= 4'd10) begin
                    next_state_s = S_UART_START;
                end
            end
            
            // UART states - send measurement results
            S_UART_START: begin
                if (!uart_tx_busy) begin
                    next_state_s = S_UART_SEND_CHAR;
                end
            end
            
            S_UART_SEND_CHAR: begin
                uart_tx_start = 1'b1;
                
                // Format: "T<time_idx>,R<repeat>,O<ones>,Z<zeros>\r\n"
                case (uart_msg_idx_q)
                    6'd0: uart_tx_data = "T";
                    6'd1: uart_tx_data = "0" + measurement_idx_q;
                    6'd2: uart_tx_data = ",";
                    6'd3: uart_tx_data = "R";
                    6'd4: uart_tx_data = "0" + repeat_count_q;
                    6'd5: uart_tx_data = ",";
                    6'd6: uart_tx_data = "O";
                    6'd7: uart_tx_data = hex_to_ascii(ones_count_q[7:4]);
                    6'd8: uart_tx_data = hex_to_ascii(ones_count_q[3:0]);
                    6'd9: uart_tx_data = ",";
                    6'd10: uart_tx_data = "Z";
                    6'd11: uart_tx_data = hex_to_ascii(zeros_count_q[7:4]);
                    6'd12: uart_tx_data = hex_to_ascii(zeros_count_q[3:0]);
                    6'd13: uart_tx_data = "\r";
                    6'd14: uart_tx_data = "\n";
                    default: uart_tx_data = " ";
                endcase
                
                next_state_s = S_UART_WAIT;
            end
            
            S_UART_WAIT: begin
                if (!uart_tx_busy) begin
                    if (uart_msg_idx_q >= 6'd14) begin
                        next_state_s = S_NEXT_MEASUREMENT;
                    end else begin
                        next_state_s = S_UART_SEND_CHAR;
                    end
                end
            end
            
            S_NEXT_MEASUREMENT: begin
                if (repeat_count_q < MEASUREMENTS_PER_TIME - 1) begin
                    // More measurements at this decay time
                    next_state_s = S_WRITE_ACTIVATE;
                end else if (measurement_idx_q < 3'd6) begin
                    // Move to next decay time
                    next_state_s = S_WRITE_ACTIVATE;
                end else begin
                    // All measurements complete
                    next_state_s = S_SWEEP_DONE;
                end
            end
            
            S_SWEEP_DONE: begin
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
        status_led0_o = (current_state_q != S_IDLE) && (current_state_q != S_SWEEP_DONE);
        status_led1_o = (current_state_q >= S_WRITE_ACTIVATE) && (current_state_q <= S_READ_DONE);
        status_led2_o = (current_state_q == S_SWEEP_DONE);
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
        .CLKS_PER_BIT(868)  // 115200 baud at 100MHz
    ) u_uart_tx (
        .clk(clk100mhz_i),
        .rst(rst_for_uart),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_data),
        .tx_serial(uart_txd_o),
        .tx_busy(uart_tx_busy),
        .tx_done()
    );

endmodule
