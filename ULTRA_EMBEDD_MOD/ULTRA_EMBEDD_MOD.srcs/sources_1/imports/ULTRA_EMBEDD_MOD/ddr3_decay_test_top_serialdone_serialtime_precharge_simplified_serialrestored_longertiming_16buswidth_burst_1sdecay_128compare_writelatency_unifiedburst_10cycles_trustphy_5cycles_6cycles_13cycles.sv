// ddr3_decay_test_top.sv
// Final version with correct read latency (13) and one-shot read window
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
    // FIX: Update read latency to match measured 14 cycles (13 + 1 for pipeline)
    localparam TPHY_RDLAT_C  = 13;  // Measured: CL(6) + 2 PHY + 5 fabric = 13
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
        S_WRITE_DATA                = 6'd14,  // Single state for write burst
        S_WRITE_WAIT                = 6'd15,
        S_PRECHARGE_AFTER_WRITE     = 6'd16,
        S_PRECHARGE_WAIT            = 6'd17,
        S_DECAY_WAIT                = 6'd18,
        S_READ_ACTIVATE             = 6'd19,
        S_READ_ACTIVATE_WAIT        = 6'd20,
        S_READ_CMD                  = 6'd21,
        S_READ_DATA                 = 6'd22,  // Single state for read burst
        S_READ_DONE                 = 6'd23,
        S_UART_START                = 6'd24,
        S_UART_SEND_CHAR            = 6'd25,
        S_UART_WAIT                 = 6'd26,
        S_DONE                      = 6'd27
    } state_t;
    
    state_t current_state_q, next_state_s;

    // Timing parameters
    localparam T_RESET_US           = 24'd40_000;   // 200us @ 200MHz
    localparam T_STABLE_US          = 24'd100_000;  // 500us @ 200MHz  
    localparam T_INIT_WAIT          = 24'd1024;     // General init wait
    localparam T_MODE_REG_SET       = 24'd20;       // tMRD + margin
    localparam T_ZQINIT             = 24'd512;      // tZQINIT
    localparam T_ACTIVATE_TO_RW     = 24'd20;       // tRCD + margin
    localparam T_WRITE_TO_PRECHARGE = 24'd30;       // tWR + tRTP + margin
    localparam T_PRECHARGE          = 24'd20;       // tRP + margin
    localparam T_DECAY_MS           = 24'd200_000;  // 1ms @ 200MHz for testing

    // Registers
    logic [27:0] timer_q;
    logic [127:0] write_data_q;      // Full burst data (8 x 16-bit)
    logic [127:0] read_data_q;       // Full burst data captured
    logic        init_done_q;
    logic [2:0]  write_burst_cnt_q;  // Burst counter for write only
    logic [3:0]  write_delay_cnt_q;  // Counter for write latency
    logic [1:0]  rd_beat_cnt_q;      // Read beat counter (counts valid beats only)
    logic [2:0]  rddata_en_cnt_q;    // Counter for rddata_en assertion (4-3-2-1-0)
    logic [2:0]  rd_lat_cnt_q;       // Latency counter for read timing
    logic        rd_window_open_q;   // One-shot flag to ensure single read window
    logic        data_match_q;       // Result of 128-bit comparison
    logic        read_burst_done;    // Signal to exit read state
    
    // Test pattern - make it more distinctive for each word
    localparam [127:0] TEST_PATTERN = 128'h1234_5678_9ABC_DEF0_A5A5_5A5A_DEAD_BEEF;
    
    // Fixed test address
    localparam TEST_ROW  = 14'h0000;
    localparam TEST_COL  = 10'h000;   
    localparam TEST_BANK = 3'b000;

    // UART control
    logic uart_tx_busy;
    logic uart_tx_start;
    logic [7:0] uart_tx_data;
    logic [5:0] uart_msg_idx_q;
    logic [2:0] uart_msg_type_q;

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
    assign read_burst_done = dfi_rddata_valid_r && (rd_beat_cnt_q == 2'd3);

    // 16-bit half-word swap functions
    function automatic [31:0] swap16(input [31:0] w);
        swap16 = {w[15:0], w[31:16]};
    endfunction

    function automatic [31:0] unswap16(input [31:0] w);
        unswap16 = {w[15:0], w[31:16]};
    endfunction

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q <= S_IDLE;
            timer_q <= 28'd0;
            write_data_q <= TEST_PATTERN;
            read_data_q <= 128'd0;
            init_done_q <= 1'b0;
            write_burst_cnt_q <= 3'd0;
            write_delay_cnt_q <= 4'd0;
            rd_beat_cnt_q <= 2'd0;
            rddata_en_cnt_q <= 3'd0;
            rd_lat_cnt_q <= 3'd0;
            rd_window_open_q <= 1'b0;
            uart_msg_idx_q <= 6'd0;
            uart_msg_type_q <= 3'd0;
            data_match_q <= 1'b0;
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
                data_match_q <= 1'b0;
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
            
            // Read latency and window management with one-shot control
            if (current_state_q == S_READ_CMD) begin
                rd_lat_cnt_q <= TPHY_RDLAT_C - 1;  // 12 counts down to 0
                rddata_en_cnt_q <= 3'd0;
                rd_window_open_q <= 1'b0;
            end else if (current_state_q == S_READ_DATA) begin
                if (!rd_window_open_q) begin
                    // Count down latency while waiting for data
                    if (rd_lat_cnt_q != 0) begin
                        rd_lat_cnt_q <= rd_lat_cnt_q - 1;
                    end else begin
                        // Open the 4-beat window exactly once
                        rddata_en_cnt_q <= 3'd4;
                        rd_window_open_q <= 1'b1;
                    end
                end else if (rddata_en_cnt_q != 0) begin
                    // Shrink window counter
                    rddata_en_cnt_q <= rddata_en_cnt_q - 1;
                end
            end
            
            // Clear window logic when leaving READ_DATA
            if (current_state_q == S_READ_DATA && read_burst_done) begin
                rddata_en_cnt_q <= 3'd0;
            end
            
            // Read beat counter - counts only when valid data arrives
            if (current_state_q != S_READ_DATA) begin
                rd_beat_cnt_q <= 2'd0;
            end else if (dfi_rddata_valid_r) begin
                // Capture data with unswap16 to correct half-word ordering
                case (rd_beat_cnt_q)
                    2'd0: read_data_q[127:96] <= unswap16(dfi_rddata_r);
                    2'd1: read_data_q[95:64]  <= unswap16(dfi_rddata_r);
                    2'd2: read_data_q[63:32]  <= unswap16(dfi_rddata_r);
                    2'd3: read_data_q[31:0]   <= unswap16(dfi_rddata_r);
                endcase
                rd_beat_cnt_q <= rd_beat_cnt_q + 1;
            end
            
            // Perform 128-bit comparison when read is done
            if (current_state_q == S_READ_DATA && next_state_s == S_READ_DONE) begin
                data_match_q <= (read_data_q == write_data_q);
            end
            
            // UART message control
            if (current_state_q == S_READ_DONE && next_state_s == S_UART_START) begin
                uart_msg_type_q <= 3'd1;
                uart_msg_idx_q <= 6'd0;
            end else if (current_state_q == S_UART_WAIT && next_state_s == S_UART_SEND_CHAR) begin
                uart_msg_idx_q <= uart_msg_idx_q + 1;
            end else if (current_state_q == S_UART_WAIT && next_state_s == S_UART_START) begin
                uart_msg_type_q <= uart_msg_type_q + 1;
                uart_msg_idx_q <= 6'd0;
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
        // DFI rddata_en driven by counter
        dfi_rddata_en_s = (rddata_en_cnt_q != 0);
        
        case (current_state_q)
            S_IDLE: begin
                dfi_cs_n_s = 1'b1;
                dfi_cke_s = 1'b0;
                if (start_btn_edge) begin
                    next_state_s = S_INIT_RESET;
                end
            end
            
            // Init states
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
            
            // Write burst state
            S_WRITE_DATA: begin
                dfi_odt_s = 1'b1;  // Keep ODT high during write
                
                // Enable write data only for the exact burst beats
                if (write_delay_cnt_q >= TPHY_WRLAT_C && write_burst_cnt_q < 3'd4) begin
                    dfi_wrdata_en_s = 1'b1;
                    dfi_wrdata_mask_s = 4'h0;
                    
                    // Apply swap16 to correct half-word ordering
                    case (write_burst_cnt_q)
                        3'd0: dfi_wrdata_s = swap16(write_data_q[127:96]);
                        3'd1: dfi_wrdata_s = swap16(write_data_q[95:64]);
                        3'd2: dfi_wrdata_s = swap16(write_data_q[63:32]);
                        3'd3: dfi_wrdata_s = swap16(write_data_q[31:0]);
                        default: dfi_wrdata_s = 32'd0;
                    endcase
                end
                
                // Exit after 4 beats
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
                dfi_address_s[10] = 1'b1; // All banks
                next_state_s = S_PRECHARGE_WAIT;
            end
            
            S_PRECHARGE_WAIT: begin
                if (timer_q >= T_PRECHARGE) begin
                    next_state_s = S_DECAY_WAIT;
                end
            end
            
            S_DECAY_WAIT: begin
                if (timer_q >= T_DECAY_MS) begin
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
                // rddata_en is now handled by the counter
                next_state_s = S_READ_DATA;
            end
            
            // Read burst state
            S_READ_DATA: begin
                // rddata_en is handled by counter, no explicit assignment needed
                
                // Exit when all 4 beats captured
                if (read_burst_done) begin
                    next_state_s = S_READ_DONE;
                end
            end
            
            S_READ_DONE: begin
                if (timer_q >= 4'd10) begin
                    next_state_s = S_UART_START;
                end
            end
            
            // UART states - prints full 128 bits
            S_UART_START: begin
                if (!uart_tx_busy) begin
                    next_state_s = S_UART_SEND_CHAR;
                end
            end
            
            S_UART_SEND_CHAR: begin
                uart_tx_start = 1'b1;
                
                case (uart_msg_type_q)
                    3'd1: begin // Write data message
                        case (uart_msg_idx_q)
                            6'd0: uart_tx_data = "W";
                            6'd1: uart_tx_data = ":";
                            6'd2: uart_tx_data = " ";
                            // Print 128 bits as 32 hex chars
                            6'd3: uart_tx_data = hex_to_ascii(write_data_q[127:124]);
                            6'd4: uart_tx_data = hex_to_ascii(write_data_q[123:120]);
                            6'd5: uart_tx_data = hex_to_ascii(write_data_q[119:116]);
                            6'd6: uart_tx_data = hex_to_ascii(write_data_q[115:112]);
                            6'd7: uart_tx_data = hex_to_ascii(write_data_q[111:108]);
                            6'd8: uart_tx_data = hex_to_ascii(write_data_q[107:104]);
                            6'd9: uart_tx_data = hex_to_ascii(write_data_q[103:100]);
                            6'd10: uart_tx_data = hex_to_ascii(write_data_q[99:96]);
                            6'd11: uart_tx_data = hex_to_ascii(write_data_q[95:92]);
                            6'd12: uart_tx_data = hex_to_ascii(write_data_q[91:88]);
                            6'd13: uart_tx_data = hex_to_ascii(write_data_q[87:84]);
                            6'd14: uart_tx_data = hex_to_ascii(write_data_q[83:80]);
                            6'd15: uart_tx_data = hex_to_ascii(write_data_q[79:76]);
                            6'd16: uart_tx_data = hex_to_ascii(write_data_q[75:72]);
                            6'd17: uart_tx_data = hex_to_ascii(write_data_q[71:68]);
                            6'd18: uart_tx_data = hex_to_ascii(write_data_q[67:64]);
                            6'd19: uart_tx_data = hex_to_ascii(write_data_q[63:60]);
                            6'd20: uart_tx_data = hex_to_ascii(write_data_q[59:56]);
                            6'd21: uart_tx_data = hex_to_ascii(write_data_q[55:52]);
                            6'd22: uart_tx_data = hex_to_ascii(write_data_q[51:48]);
                            6'd23: uart_tx_data = hex_to_ascii(write_data_q[47:44]);
                            6'd24: uart_tx_data = hex_to_ascii(write_data_q[43:40]);
                            6'd25: uart_tx_data = hex_to_ascii(write_data_q[39:36]);
                            6'd26: uart_tx_data = hex_to_ascii(write_data_q[35:32]);
                            6'd27: uart_tx_data = hex_to_ascii(write_data_q[31:28]);
                            6'd28: uart_tx_data = hex_to_ascii(write_data_q[27:24]);
                            6'd29: uart_tx_data = hex_to_ascii(write_data_q[23:20]);
                            6'd30: uart_tx_data = hex_to_ascii(write_data_q[19:16]);
                            6'd31: uart_tx_data = hex_to_ascii(write_data_q[15:12]);
                            6'd32: uart_tx_data = hex_to_ascii(write_data_q[11:8]);
                            6'd33: uart_tx_data = hex_to_ascii(write_data_q[7:4]);
                            6'd34: uart_tx_data = hex_to_ascii(write_data_q[3:0]);
                            6'd35: uart_tx_data = " ";
                            default: uart_tx_data = " ";
                        endcase
                    end
                    
                    3'd2: begin // Read data message
                        case (uart_msg_idx_q)
                            6'd0: uart_tx_data = "R";
                            6'd1: uart_tx_data = ":";
                            6'd2: uart_tx_data = " ";
                            // Print 128 bits as 32 hex chars
                            6'd3: uart_tx_data = hex_to_ascii(read_data_q[127:124]);
                            6'd4: uart_tx_data = hex_to_ascii(read_data_q[123:120]);
                            6'd5: uart_tx_data = hex_to_ascii(read_data_q[119:116]);
                            6'd6: uart_tx_data = hex_to_ascii(read_data_q[115:112]);
                            6'd7: uart_tx_data = hex_to_ascii(read_data_q[111:108]);
                            6'd8: uart_tx_data = hex_to_ascii(read_data_q[107:104]);
                            6'd9: uart_tx_data = hex_to_ascii(read_data_q[103:100]);
                            6'd10: uart_tx_data = hex_to_ascii(read_data_q[99:96]);
                            6'd11: uart_tx_data = hex_to_ascii(read_data_q[95:92]);
                            6'd12: uart_tx_data = hex_to_ascii(read_data_q[91:88]);
                            6'd13: uart_tx_data = hex_to_ascii(read_data_q[87:84]);
                            6'd14: uart_tx_data = hex_to_ascii(read_data_q[83:80]);
                            6'd15: uart_tx_data = hex_to_ascii(read_data_q[79:76]);
                            6'd16: uart_tx_data = hex_to_ascii(read_data_q[75:72]);
                            6'd17: uart_tx_data = hex_to_ascii(read_data_q[71:68]);
                            6'd18: uart_tx_data = hex_to_ascii(read_data_q[67:64]);
                            6'd19: uart_tx_data = hex_to_ascii(read_data_q[63:60]);
                            6'd20: uart_tx_data = hex_to_ascii(read_data_q[59:56]);
                            6'd21: uart_tx_data = hex_to_ascii(read_data_q[55:52]);
                            6'd22: uart_tx_data = hex_to_ascii(read_data_q[51:48]);
                            6'd23: uart_tx_data = hex_to_ascii(read_data_q[47:44]);
                            6'd24: uart_tx_data = hex_to_ascii(read_data_q[43:40]);
                            6'd25: uart_tx_data = hex_to_ascii(read_data_q[39:36]);
                            6'd26: uart_tx_data = hex_to_ascii(read_data_q[35:32]);
                            6'd27: uart_tx_data = hex_to_ascii(read_data_q[31:28]);
                            6'd28: uart_tx_data = hex_to_ascii(read_data_q[27:24]);
                            6'd29: uart_tx_data = hex_to_ascii(read_data_q[23:20]);
                            6'd30: uart_tx_data = hex_to_ascii(read_data_q[19:16]);
                            6'd31: uart_tx_data = hex_to_ascii(read_data_q[15:12]);
                            6'd32: uart_tx_data = hex_to_ascii(read_data_q[11:8]);
                            6'd33: uart_tx_data = hex_to_ascii(read_data_q[7:4]);
                            6'd34: uart_tx_data = hex_to_ascii(read_data_q[3:0]);
                            6'd35: uart_tx_data = " ";
                            default: uart_tx_data = " ";
                        endcase
                    end
                    
                    3'd3: begin // Result message
                        case (uart_msg_idx_q)
                            6'd0: uart_tx_data = "-";
                            6'd1: uart_tx_data = " ";
                            6'd2: uart_tx_data = "M";
                            6'd3: uart_tx_data = "A";
                            6'd4: uart_tx_data = "T";
                            6'd5: uart_tx_data = "C";
                            6'd6: uart_tx_data = "H";
                            6'd7: uart_tx_data = " ";
                            6'd8: uart_tx_data = data_match_q ? "O" : "E";
                            6'd9: uart_tx_data = data_match_q ? "K" : "R";
                            6'd10: uart_tx_data = data_match_q ? " " : "R";
                            6'd11: uart_tx_data = "\r";
                            6'd12: uart_tx_data = "\n";
                            default: uart_tx_data = " ";
                        endcase
                    end
                    
                    default: uart_tx_data = " ";
                endcase
                
                next_state_s = S_UART_WAIT;
            end
            
            S_UART_WAIT: begin
                if (!uart_tx_busy) begin
                    // Check if message complete
                    if ((uart_msg_type_q == 3'd1 || uart_msg_type_q == 3'd2) && uart_msg_idx_q >= 6'd35) begin
                        next_state_s = S_UART_START; // Next message
                    end else if (uart_msg_type_q == 3'd3 && uart_msg_idx_q >= 6'd12) begin
                        next_state_s = S_DONE; // All done
                    end else begin
                        next_state_s = S_UART_SEND_CHAR; // Next character
                    end
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
        status_led1_o = (current_state_q == S_DONE) && data_match_q;
        status_led2_o = (current_state_q == S_DONE) && !data_match_q;
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

    // Enhanced ILA signals for debugging
    logic [5:0]  ila_state;
    logic [23:0] ila_timer;
    logic        ila_wrdata_en;
    logic [31:0] ila_wrdata;
    logic        ila_rddata_valid;
    logic [31:0] ila_rddata;
    logic [127:0] ila_write_pattern;
    logic [127:0] ila_captured_data;  
    logic [2:0]  ila_write_burst_cnt;
    logic [1:0]  ila_rd_beat_cnt;
    logic        ila_cmd_valid;
    logic [2:0]  ila_cmd_type;
    logic        ila_data_match;
    logic [3:0]  ila_write_delay_cnt;
    logic        ila_write_cmd_pulse;
    logic        ila_read_cmd_pulse;
    logic        ila_read_burst_done;
    logic        ila_rddata_en;
    logic [2:0]  ila_rd_lat_cnt;
    logic [2:0]  ila_rddata_en_cnt;
    logic        ila_rd_window_open;
    
    always_comb begin
        ila_state = current_state_q;
        ila_timer = timer_q[23:0];
        ila_wrdata_en = dfi_wrdata_en_s;
        ila_wrdata = dfi_wrdata_s;
        ila_rddata_valid = dfi_rddata_valid_r;
        ila_rddata = dfi_rddata_r;
        ila_write_pattern = write_data_q;
        ila_captured_data = read_data_q;
        ila_write_burst_cnt = write_burst_cnt_q;
        ila_rd_beat_cnt = rd_beat_cnt_q;
        ila_cmd_valid = ~dfi_cs_n_s;
        ila_cmd_type = {dfi_ras_n_s, dfi_cas_n_s, dfi_we_n_s};
        ila_data_match = data_match_q;
        ila_write_delay_cnt = write_delay_cnt_q;
        ila_write_cmd_pulse = (current_state_q == S_WRITE_CMD);
        ila_read_cmd_pulse = (current_state_q == S_READ_CMD);
        ila_read_burst_done = read_burst_done;
        ila_rddata_en = dfi_rddata_en_s;
        ila_rd_lat_cnt = rd_lat_cnt_q;
        ila_rddata_en_cnt = rddata_en_cnt_q;
        ila_rd_window_open = rd_window_open_q;
    end

    // ILA instance with window open flag added
    ila_0 u_ila (
        .clk(clk_phy_sys),
        .probe0(ila_state),                    
        .probe1({2'd0, ila_state}),            
        .probe2(ila_timer[15:0]),              
        .probe3(ila_cmd_valid),                
        .probe4(ila_cmd_type),                 
        .probe5(dfi_address_s[9:0]),           
        .probe6(dfi_bank_s),                   
        .probe7(ila_wrdata_en),                
        .probe8(ila_wrdata),                   
        .probe9(ila_rddata_valid),             
        .probe10(ila_rddata),                  
        .probe11(ila_captured_data[31:0]),     
        .probe12(init_done_q),                 
        .probe13({ila_data_match, ila_write_delay_cnt, ila_write_burst_cnt}), 
        .probe14({1'b0, ila_rd_window_open, ila_rd_beat_cnt, ila_rddata_valid, ila_write_cmd_pulse, ila_read_cmd_pulse, ila_read_burst_done}),
        .probe15({6'd0, ila_rd_beat_cnt}),
        .probe16(ila_rddata_en),
        .probe17(ila_rd_lat_cnt),
        .probe18(ila_rddata_en_cnt)
    );

endmodule
