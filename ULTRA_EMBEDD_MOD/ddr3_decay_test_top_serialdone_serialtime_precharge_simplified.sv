// ddr3_decay_test_top.sv
// Fixed version with proper state transitions and enhanced debugging
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
        S_IDLE                      = 6'h00,
        S_INIT_RESET                = 6'h01,
        S_INIT_RESET_WAIT           = 6'h02,
        S_INIT_CKE_LOW              = 6'h03,
        S_INIT_STABLE               = 6'h04,
        S_INIT_MRS2                 = 6'h05,
        S_INIT_MRS3                 = 6'h06,
        S_INIT_MRS1                 = 6'h07,
        S_INIT_MRS0                 = 6'h08,
        S_INIT_ZQCL                 = 6'h09,
        S_INIT_WAIT                 = 6'h0A,
        S_WRITE_ACTIVATE            = 6'h0B,
        S_WRITE_ACTIVATE_WAIT       = 6'h0C,
        S_WRITE_CMD                 = 6'h0D,
        S_WRITE_WAIT                = 6'h0E,
        S_PRECHARGE_AFTER_WRITE     = 6'h0F,
        S_PRECHARGE_WAIT            = 6'h10,
        S_DECAY_WAIT                = 6'h11,
        S_READ_ACTIVATE             = 6'h12,
        S_READ_ACTIVATE_WAIT        = 6'h13,
        S_READ_CMD                  = 6'h14,
        S_READ_WAIT                 = 6'h15,
        S_READ_CAPTURE              = 6'h16,
        S_UART_WRITE_MSG            = 6'h17,
        S_UART_READ_MSG             = 6'h18,
        S_UART_RESULT_MSG           = 6'h19,
        S_UART_CHAR                 = 6'h1A,
        S_UART_WAIT                 = 6'h1B,
        S_DONE                      = 6'h1C
    } state_t;
    
    state_t current_state_q, next_state_s;

    // Fixed timing parameters
    localparam T_RESET_US           = 24'd40_000;   // 200us @ 200MHz
    localparam T_STABLE_US          = 24'd100_000;  // 500us @ 200MHz  
    localparam T_INIT_WAIT          = 24'd1024;     // General init wait
    localparam T_MODE_REG_SET       = 24'd20;       // tMRD + margin
    localparam T_ZQINIT             = 24'd512;      // tZQINIT
    localparam T_ACTIVATE_TO_RW     = 24'd15;       // tRCD
    localparam T_WRITE_RECOVERY     = 24'd15;       // tWR
    localparam T_PRECHARGE          = 24'd15;       // tRP
    localparam T_READ_LATENCY       = TPHY_RDLAT_C + CAS_LATENCY_C + 5;
    localparam T_DECAY_MS           = 24'd200_000;  // 1ms @ 200MHz (start small)

    logic [23:0] timer_q;
    logic [31:0] write_data_q;
    logic [31:0] read_data_q;
    logic        init_done_q;
    
    // Test pattern with alternating bits for better visibility
    localparam TEST_PATTERN = 32'hA5A5_5A5A;
    
    // Fixed test address
    localparam TEST_ROW  = 14'h0000;  // Row 0
    localparam TEST_COL  = 10'h000;   // Column 0  
    localparam TEST_BANK = 3'b000;    // Bank 0

    // Debug counters
    logic [7:0] init_step_q;
    logic [7:0] state_transition_count_q;
    
    // ILA signals - Enhanced debugging
    logic [5:0]  ila_state;
    logic [5:0]  ila_next_state;
    logic [23:0] ila_timer;
    logic        ila_cmd_valid;
    logic [2:0]  ila_cmd_type;
    logic [14:0] ila_address;
    logic [2:0]  ila_bank;
    logic        ila_write_en;
    logic [31:0] ila_write_data;
    logic        ila_read_valid;
    logic [31:0] ila_read_data;
    logic [31:0] ila_captured_data;
    logic        ila_init_done;
    logic [7:0]  ila_init_step;
    logic        ila_decay_active;
    logic [7:0]  ila_state_count;
    
    // Connect ILA probes
    always_comb begin
        ila_state = current_state_q;
        ila_next_state = next_state_s;
        ila_timer = timer_q;
        ila_cmd_valid = ~dfi_cs_n_s;
        ila_cmd_type = {dfi_ras_n_s, dfi_cas_n_s, dfi_we_n_s};
        ila_address = dfi_address_s;
        ila_bank = dfi_bank_s;
        ila_write_en = dfi_wrdata_en_s;
        ila_write_data = dfi_wrdata_s;
        ila_read_valid = dfi_rddata_valid_r;
        ila_read_data = dfi_rddata_r;
        ila_captured_data = read_data_q;
        ila_init_done = init_done_q;
        ila_init_step = init_step_q;
        ila_decay_active = (current_state_q == S_DECAY_WAIT);
        ila_state_count = state_transition_count_q;
    end

    // Enhanced ILA instance
    ila_0 u_ila (
        .clk(clk_phy_sys),
        .probe0(ila_state),            // 6 bits - Current state
        .probe1(ila_next_state),       // 6 bits - Next state  
        .probe2(ila_timer[15:0]),      // 16 bits - Timer lower
        .probe3(ila_cmd_valid),        // 1 bit - Command valid
        .probe4(ila_cmd_type),         // 3 bits - Command type
        .probe5(ila_address[9:0]),     // 10 bits - Address lower
        .probe6(ila_bank),             // 3 bits - Bank
        .probe7(ila_write_en),         // 1 bit - Write enable
        .probe8(ila_write_data),       // 32 bits - Write data
        .probe9(ila_read_valid),       // 1 bit - Read valid
        .probe10(ila_read_data),       // 32 bits - Read data
        .probe11(ila_captured_data),   // 32 bits - Captured data
        .probe12(ila_init_done),       // 1 bit - Init done flag
        .probe13(ila_init_step),       // 8 bits - Init step counter
        .probe14(ila_decay_active),    // 1 bit - In decay period
        .probe15(ila_state_count)      // 8 bits - State transitions
    );

    // Synchronize start button
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

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q <= S_IDLE;
            timer_q <= 24'd0;
            write_data_q <= TEST_PATTERN;
            read_data_q <= 32'd0;
            init_done_q <= 1'b0;
            init_step_q <= 8'd0;
            state_transition_count_q <= 8'd0;
        end else begin
            current_state_q <= next_state_s;
            
            // Update timer
            if (current_state_q != next_state_s) begin
                timer_q <= 24'd0;
                state_transition_count_q <= state_transition_count_q + 1;
            end else begin
                timer_q <= timer_q + 1;
            end
            
            // Track initialization progress
            if (current_state_q >= S_INIT_MRS2 && current_state_q <= S_INIT_WAIT) begin
                if (current_state_q != next_state_s)
                    init_step_q <= init_step_q + 1;
            end
            
            // Set init done flag
            if (current_state_q == S_INIT_WAIT && next_state_s == S_WRITE_ACTIVATE) begin
                init_done_q <= 1'b1;
            end
            
            // Capture read data
            if (current_state_q == S_READ_WAIT && dfi_rddata_valid_r) begin
                read_data_q <= dfi_rddata_r;
            end
        end
    end

    // State machine combinational logic - Simplified and fixed
    always_comb begin
        // Default values
        next_state_s = current_state_q;
        
        // Default DDR3 signals (NOP)
        dfi_cs_n_s = 1'b0;  // Keep chip selected during operation
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
                dfi_cs_n_s = 1'b1;  // Deselect in idle
                dfi_cke_s = 1'b0;
                if (start_btn_edge) begin
                    next_state_s = S_INIT_RESET;
                end
            end
            
            S_INIT_RESET: begin
                dfi_reset_n_s = 1'b0;  // Assert reset
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
                dfi_reset_n_s = 1'b1;  // Release reset
                dfi_cke_s = 1'b0;      // Keep CKE low
                if (timer_q >= T_STABLE_US) begin
                    next_state_s = S_INIT_STABLE;
                end
            end
            
            S_INIT_STABLE: begin
                dfi_cke_s = 1'b1;  // Enable clock
                if (timer_q >= T_INIT_WAIT) begin
                    next_state_s = S_INIT_MRS2;
                end
            end
            
            S_INIT_MRS2: begin
                // Load Mode Register 2
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b010;
                dfi_address_s = 15'd0;  // Normal operation
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS3;
                end
            end
            
            S_INIT_MRS3: begin
                // Load Mode Register 3
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
                // Load Mode Register 1
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b001;
                dfi_address_s = 15'b00000_00_0_01_0_00_0;  // DLL Enable, Drive RZQ/6
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_MRS0;
                end
            end
            
            S_INIT_MRS0: begin
                // Load Mode Register 0 - DLL Reset
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = 3'b000;
                dfi_address_s = {2'b00, 3'b010, 1'b1, 4'b0010, 3'b000, 1'b0}; // CL=6, BL=8, DLL Reset
                if (timer_q >= T_MODE_REG_SET) begin
                    next_state_s = S_INIT_ZQCL;
                end
            end
            
            S_INIT_ZQCL: begin
                // ZQ Calibration Long
                dfi_we_n_s = 1'b0;
                dfi_address_s[10] = 1'b1;  // A10=1 for ZQCL
                if (timer_q >= T_ZQINIT) begin
                    next_state_s = S_INIT_WAIT;
                end
            end
            
            S_INIT_WAIT: begin
                // Wait for DLL lock and general settling
                if (timer_q >= T_INIT_WAIT) begin
                    next_state_s = S_WRITE_ACTIVATE;
                end
            end
            
            S_WRITE_ACTIVATE: begin
                // Activate command for write
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
                // Write command
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b0;
                dfi_bank_s = TEST_BANK;
                dfi_address_s = {5'd0, TEST_COL};
                dfi_wrdata_s = write_data_q;
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;  // Write all bytes
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_WAIT;
            end
            
            S_WRITE_WAIT: begin
                if (timer_q >= T_WRITE_RECOVERY) begin
                    next_state_s = S_PRECHARGE_AFTER_WRITE;
                end
            end
            
            S_PRECHARGE_AFTER_WRITE: begin
                // Precharge all banks
                dfi_ras_n_s = 1'b0;
                dfi_cas_n_s = 1'b1;
                dfi_we_n_s = 1'b0;
                dfi_address_s[10] = 1'b1;  // A10=1 for all banks
                next_state_s = S_PRECHARGE_WAIT;
            end
            
            S_PRECHARGE_WAIT: begin
                if (timer_q >= T_PRECHARGE) begin
                    next_state_s = S_DECAY_WAIT;
                end
            end
            
            S_DECAY_WAIT: begin
                // Wait for decay - no refresh!
                if (timer_q >= T_DECAY_MS) begin
                    next_state_s = S_READ_ACTIVATE;
                end
            end
            
            S_READ_ACTIVATE: begin
                // Activate for read
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
                // Read command
                dfi_ras_n_s = 1'b1;
                dfi_cas_n_s = 1'b0;
                dfi_we_n_s = 1'b1;
                dfi_bank_s = TEST_BANK;
                dfi_address_s = {5'd0, TEST_COL};
                dfi_rddata_en_s = 1'b1;
                next_state_s = S_READ_WAIT;
            end
            
            S_READ_WAIT: begin
                if (dfi_rddata_valid_r || timer_q >= T_READ_LATENCY) begin
                    next_state_s = S_READ_CAPTURE;
                end
            end
            
            S_READ_CAPTURE: begin
                next_state_s = S_DONE;
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
        status_led1_o = (current_state_q == S_DONE) && (read_data_q == write_data_q);
        status_led2_o = (current_state_q == S_DONE) && (read_data_q != write_data_q);
        status_led3_o = init_done_q;
    end

    // Simple UART output for results (simplified for now)
    uart_tx #(
        .CLKS_PER_BIT(868)
    ) u_uart_tx (
        .clk(clk100mhz_i),
        .rst(rst_for_uart),
        .tx_start(1'b0),
        .tx_data(8'h00),
        .tx_serial(uart_txd_o),
        .tx_busy(),
        .tx_done()
    );

endmodule
