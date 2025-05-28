// ddr3_decay_test_top.sv
// Corrected version with improved timing and debugging
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
        S_READ_WAIT                 = 6'd22,
        S_READ_CAPTURE              = 6'd23,
        S_UART_START                = 6'd24,
        S_UART_SEND_CHAR            = 6'd25,
        S_UART_WAIT                 = 6'd26,
        S_DONE                      = 6'd27
    } state_t;
    
    state_t current_state_q, next_state_s;

    // Timing parameters (adjusted for better reliability)
    localparam T_RESET_US           = 24'd40_000;   // 200us @ 200MHz
    localparam T_STABLE_US          = 24'd100_000;  // 500us @ 200MHz  
    localparam T_INIT_WAIT          = 24'd1024;     // General init wait
    localparam T_MODE_REG_SET       = 24'd20;       // tMRD + margin
    localparam T_ZQINIT             = 24'd512;      // tZQINIT
    localparam T_ACTIVATE_TO_RW     = 24'd20;       // tRCD + margin (was 15)
    localparam T_WRITE_TO_PRECHARGE = 24'd20;       // tWR + margin (was 15)
    localparam T_PRECHARGE          = 24'd20;       // tRP + margin (was 15)
    localparam T_READ_LATENCY       = TPHY_RDLAT_C + CAS_LATENCY_C + 10; // Added margin
    localparam T_DECAY_MS           = 24'd200_000;  // 1ms @ 200MHz
    localparam T_WRITE_DATA_CYCLES  = 24'd4;        // Time for write data to be sent
    localparam T_BURST_LENGTH       = 24'd4;        // BL8 requires 4 cycles for 32-bit interface

    logic [23:0] timer_q;
    logic [31:0] write_data_q;
    logic [31:0] read_data_q;
    logic        init_done_q;
    logic        read_data_captured_q;
    logic [1:0] read_count_q; // Or whatever bit-width you actually use.

    // Test pattern - use different values for upper and lower 16 bits
    // This will help us see what's actually being written/read
    localparam TEST_PATTERN = 32'h1234_5678;  // Distinctive upper/lower halves
    
    // Fixed test address
    localparam TEST_ROW  = 14'h0000;
    localparam TEST_COL  = 10'h000;   
    localparam TEST_BANK = 3'b000;

    // UART control
    logic uart_tx_busy;
    logic uart_tx_start;
    logic [7:0] uart_tx_data;
    logic [3:0] uart_msg_idx_q;
    logic [1:0] uart_msg_type_q; // 0=none, 1=write data, 2=read data, 3=result
    
    // ILA signals
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
        ila_init_step = 8'd0;
        ila_decay_active = (current_state_q == S_DECAY_WAIT);
        ila_state_count = 8'd0;
    end

    // ILA instance
    ila_0 u_ila (
        .clk(clk_phy_sys),
        .probe0(ila_state),            
        .probe1(ila_next_state),       
        .probe2(ila_timer[15:0]),      
        .probe3(ila_cmd_valid),        
        .probe4(ila_cmd_type),         
        .probe5(ila_address[9:0]),     
        .probe6(ila_bank),             
        .probe7(ila_write_en),         
        .probe8(ila_write_data),       
        .probe9(ila_read_valid),       
        .probe10(ila_read_data),       
        .probe11(ila_captured_data),   
        .probe12(ila_init_done),       
        .probe13(ila_init_step),       
        .probe14(ila_decay_active),    
        .probe15(ila_state_count)      
    );

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

    // State machine sequential logic
    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q <= S_IDLE;
            timer_q <= 24'd0;
            write_data_q <= TEST_PATTERN;
            read_data_q <= 32'd0;
            init_done_q <= 1'b0;
            read_data_captured_q <= 1'b0;
            read_count_q <= 2'd0;
            uart_msg_idx_q <= 4'd0;
            uart_msg_type_q <= 2'd0;
        end else begin
            current_state_q <= next_state_s;
            
            // Update timer
            if (current_state_q != next_state_s) begin
                timer_q <= 24'd0;
            end else begin
                timer_q <= timer_q + 1;
            end
            
            // Set init done flag when transitioning from init to write
            if (current_state_q == S_INIT_DONE && next_state_s == S_WRITE_ACTIVATE) begin
                init_done_q <= 1'b1;
            end
            
            // Clear init done on reset
            if (current_state_q == S_IDLE) begin
                init_done_q <= 1'b0;
                read_data_captured_q <= 1'b0;
                read_count_q <= 2'd0;
            end
            
            // Capture read data - for x16 interface, just take what we get
            if (current_state_q == S_READ_WAIT && dfi_rddata_valid_r) begin
                read_data_q <= dfi_rddata_r;
                read_data_captured_q <= 1'b1;
            end
            
            // Reset read captured flag when starting new read
            if (current_state_q == S_READ_ACTIVATE) begin
                read_data_captured_q <= 1'b0;
            end
            
            // UART message control
            if (current_state_q == S_READ_CAPTURE && next_state_s == S_UART_START) begin
                uart_msg_type_q <= 2'd1; // Start with write data message
                uart_msg_idx_q <= 4'd0;
            end else if (current_state_q == S_UART_WAIT && next_state_s == S_UART_SEND_CHAR) begin
                uart_msg_idx_q <= uart_msg_idx_q + 1;
            end else if (current_state_q == S_UART_WAIT && next_state_s == S_UART_START) begin
                // Move to next message
                uart_msg_type_q <= uart_msg_type_q + 1;
                uart_msg_idx_q <= 4'd0;
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
                // [12]=0 (DLL Reset), [11:9]=010 (CL=6), [8]=1 (DLL Reset), 
                // [7]=0 (test mode), [6:4]=0 (CL cont), [3]=0 (Sequential),
                // [2]=0 (reserved), [1:0]=00 (BL=8)
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
                dfi_wrdata_s = write_data_q;
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;  // No masking - write all bytes
                dfi_odt_s = 1'b1;
                next_state_s = S_WRITE_DATA;
            end
            
            S_WRITE_DATA: begin
                // For x16 interface, we might need to write twice
                // First write lower 16 bits, then upper 16 bits
                dfi_wrdata_s = write_data_q;
                dfi_wrdata_en_s = 1'b1;
                dfi_wrdata_mask_s = 4'h0;
                dfi_odt_s = 1'b1;
                if (timer_q >= T_WRITE_DATA_CYCLES) begin
                    next_state_s = S_WRITE_WAIT;
                end
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
                if (timer_q >= T_DECAY_MS) begin
                    next_state_s = S_READ_ACTIVATE;
                end
            end
            
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
                dfi_rddata_en_s = 1'b1;
                next_state_s = S_READ_WAIT;
            end
            
            S_READ_WAIT: begin
                // Keep read data enable active for a few cycles
                dfi_rddata_en_s = 1'b1;
                if (read_data_captured_q || timer_q >= T_READ_LATENCY) begin
                    next_state_s = S_READ_CAPTURE;
                end
            end
            
            S_READ_CAPTURE: begin
                // Add extra delay to ensure all data is captured
                if (timer_q >= T_BURST_LENGTH) begin
                    next_state_s = S_UART_START;
                end
            end
            
            S_UART_START: begin
                if (!uart_tx_busy) begin
                    next_state_s = S_UART_SEND_CHAR;
                end
            end
            
            S_UART_SEND_CHAR: begin
                uart_tx_start = 1'b1;
                
                case (uart_msg_type_q)
                    2'd1: begin // Write data message
                        case (uart_msg_idx_q)
                            4'd0: uart_tx_data = "W";
                            4'd1: uart_tx_data = ":";
                            4'd2: uart_tx_data = " ";
                            4'd3: uart_tx_data = hex_to_ascii(write_data_q[31:28]);
                            4'd4: uart_tx_data = hex_to_ascii(write_data_q[27:24]);
                            4'd5: uart_tx_data = hex_to_ascii(write_data_q[23:20]);
                            4'd6: uart_tx_data = hex_to_ascii(write_data_q[19:16]);
                            4'd7: uart_tx_data = hex_to_ascii(write_data_q[15:12]);
                            4'd8: uart_tx_data = hex_to_ascii(write_data_q[11:8]);
                            4'd9: uart_tx_data = hex_to_ascii(write_data_q[7:4]);
                            4'd10: uart_tx_data = hex_to_ascii(write_data_q[3:0]);
                            4'd11: uart_tx_data = " ";
                            default: uart_tx_data = " ";
                        endcase
                    end
                    
                    2'd2: begin // Read data message
                        case (uart_msg_idx_q)
                            4'd0: uart_tx_data = "R";
                            4'd1: uart_tx_data = ":";
                            4'd2: uart_tx_data = " ";
                            4'd3: uart_tx_data = hex_to_ascii(read_data_q[31:28]);
                            4'd4: uart_tx_data = hex_to_ascii(read_data_q[27:24]);
                            4'd5: uart_tx_data = hex_to_ascii(read_data_q[23:20]);
                            4'd6: uart_tx_data = hex_to_ascii(read_data_q[19:16]);
                            4'd7: uart_tx_data = hex_to_ascii(read_data_q[15:12]);
                            4'd8: uart_tx_data = hex_to_ascii(read_data_q[11:8]);
                            4'd9: uart_tx_data = hex_to_ascii(read_data_q[7:4]);
                            4'd10: uart_tx_data = hex_to_ascii(read_data_q[3:0]);
                            4'd11: uart_tx_data = " ";
                            default: uart_tx_data = " ";
                        endcase
                    end
                    
                    2'd3: begin // Result message with debug info
                        case (uart_msg_idx_q)
                            4'd0: uart_tx_data = "-";
                            4'd1: uart_tx_data = " ";
                            4'd2: uart_tx_data = (read_data_q == write_data_q) ? "M" : "F";
                            4'd3: uart_tx_data = " ";
                            4'd4: uart_tx_data = "L";
                            4'd5: uart_tx_data = ":";
                            4'd6: uart_tx_data = hex_to_ascii(read_data_q[15:12]);
                            4'd7: uart_tx_data = hex_to_ascii(read_data_q[11:8]);
                            4'd8: uart_tx_data = hex_to_ascii(read_data_q[7:4]);
                            4'd9: uart_tx_data = hex_to_ascii(read_data_q[3:0]);
                            4'd10: uart_tx_data = "\r";
                            4'd11: uart_tx_data = "\n";
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
                    if ((uart_msg_type_q == 2'd1 || uart_msg_type_q == 2'd2) && uart_msg_idx_q >= 4'd11) begin
                        next_state_s = S_UART_START; // Next message
                    end else if (uart_msg_type_q == 2'd3 && uart_msg_idx_q >= 4'd11) begin
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
        status_led1_o = (current_state_q == S_DONE) && (read_data_q == write_data_q);
        status_led2_o = (current_state_q == S_DONE) && (read_data_q != write_data_q);
        status_led3_o = uart_tx_busy;  // Show UART activity
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

endmodule
