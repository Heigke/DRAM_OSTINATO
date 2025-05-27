// ddr3_decay_test_top.sv
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
    output logic        ddr3_reset_n_o, // To DDR3 chip (active LOW)
    output logic        ddr3_we_n_o
);

    // --- Clocking and Reset Logic ---
    logic clk_phy_sys;
    logic clk_phy_ddr;
    logic clk_phy_ddr90;
    logic clk_idelay_ref;
    logic mmcm_locked;
    
    logic sys_rst_fsm_phy;
    logic rst_for_uart;

    // Corrected MMCM instance using the template from Vivado
    // Ensure 'clk_wiz_0' is the component name of your generated IP.
    clk_wiz_0 u_clk_wiz ( // u_clk_wiz is the instance name
        // Clock out ports
        .clk_phy_sys(clk_phy_sys),         // Output from MMCM connected to your logic signal
        .clk_phy_ddr(clk_phy_ddr),         // Output from MMCM
        .clk_phy_ddr90(clk_phy_ddr90),     // Output from MMCM
        .clk_idelay_ref(clk_idelay_ref),   // Output from MMCM
        // Status and control signals
        .reset(reset_btn_i),             // Input to MMCM (use the board's reset button directly)
        .locked(mmcm_locked),            // Output from MMCM connected to your logic signal
       // Clock in ports
        .clk_in1(clk100mhz_i)            // Input to MMCM
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
    localparam CAS_LATENCY_C = 6;

    logic [14:0] dfi_address_s;
    logic [2:0]  dfi_bank_s;
    logic        dfi_cas_n_s, dfi_cke_s, dfi_cs_n_s, dfi_odt_s, dfi_ras_n_s;
    logic        dfi_reset_n_s, dfi_we_n_s, dfi_wrdata_en_s, dfi_rddata_en_s;
    logic [31:0] dfi_wrdata_s, dfi_rddata_r;
    logic [3:0]  dfi_wrdata_mask_s;
    logic        dfi_rddata_valid_r;
    logic [1:0]  dfi_rddata_dnv_r;

    ddr3_dfi_phy #( .REFCLK_FREQUENCY(200), .DQS_TAP_DELAY_INIT(15), .DQ_TAP_DELAY_INIT(1),
                   .TPHY_RDLAT(TPHY_RDLAT_C), .TPHY_WRLAT(TPHY_WRLAT_C), .TPHY_WRDATA(0) )
    u_ddr3_phy_inst (
        .clk_i(clk_phy_sys), .clk_ddr_i(clk_phy_ddr), .clk_ddr90_i(clk_phy_ddr90), .clk_ref_i(clk_idelay_ref),
        .rst_i(sys_rst_fsm_phy), .cfg_valid_i(1'b0), .cfg_i(32'b0),
        .dfi_address_i(dfi_address_s), .dfi_bank_i(dfi_bank_s), .dfi_cas_n_i(dfi_cas_n_s),
        .dfi_cke_i(dfi_cke_s), .dfi_cs_n_i(dfi_cs_n_s), .dfi_odt_i(dfi_odt_s),
        .dfi_ras_n_i(dfi_ras_n_s), .dfi_reset_n_i(dfi_reset_n_s), .dfi_we_n_i(dfi_we_n_s),
        .dfi_wrdata_i(dfi_wrdata_s), .dfi_wrdata_en_i(dfi_wrdata_en_s), .dfi_wrdata_mask_i(dfi_wrdata_mask_s),
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
        S_INIT_CMD_PREA, S_INIT_CMD_EMR2, S_INIT_CMD_EMR3, S_INIT_CMD_EMR1, S_INIT_CMD_MR0_DLL_RESET, S_INIT_CMD_ZQCL, S_INIT_CMD_MR0_FINAL, S_INIT_WAIT_DLL_ZQ,
        S_ACT_WR, S_WR_CMD, S_WR_DATA_WAIT, S_DECAY_WAIT_PERIOD,
        S_ACT_RD, S_RD_CMD, S_RD_DATA_WAIT, S_RD_DATA_CAPTURE,
        S_UART_SETUP_CHAR, S_UART_WAIT_TX_DONE, S_DONE
    } state_t;
    state_t current_state_q, next_state_s;

    localparam T_INIT_200US_CYCLES = 24'd40_000;
    localparam T_STAB_500US_CYCLES = 24'd100_000;
    localparam T_ZQINIT_CYCLES     = 24'd512;
    localparam T_DECAY_10MS_CYCLES = 24'd2_000_000;
    localparam T_RP_CYCLES   = 24'd3;
    localparam T_RCD_CYCLES  = 24'd3;
    localparam TOTAL_RD_LAT_CYCLES = TPHY_RDLAT_C + CAS_LATENCY_C + 3;

    logic [23:0] timer_q, timer_s;
    logic [14:0] test_addr_row_s;
    logic [14:0] test_addr_col_s;
    logic [2:0]  test_bank_s;
    logic [31:0] data_to_write_q, data_read_q;
    logic        data_match_r;

    logic uart_tx_start_from_fsm_s;
    logic [7:0] uart_tx_data_from_fsm_s;
    logic uart_tx_busy_to_fsm_r;
    logic uart_tx_done_to_fsm_r;

    typedef enum logic [1:0] {UART_MSG_NONE, UART_MSG_WR_DATA, UART_MSG_RD_DATA, UART_MSG_RESULT} uart_msg_type_t;
    uart_msg_type_t uart_current_msg_q, uart_current_msg_s;
    logic [3:0] uart_char_idx_q, uart_char_idx_s;

    logic start_cmd_edge_s;
    logic start_btn_phy_sync_0, start_btn_phy_sync_1, start_btn_phy_prev_q;

    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            start_btn_phy_sync_0 <= 1'b0; start_btn_phy_sync_1 <= 1'b0; start_btn_phy_prev_q <= 1'b0;
        end else begin
            start_btn_phy_sync_0 <= start_btn_i; start_btn_phy_sync_1 <= start_btn_phy_sync_0; start_btn_phy_prev_q <= start_btn_phy_sync_1;
        end
    end
    assign start_cmd_edge_s = start_btn_phy_sync_1 & ~start_btn_phy_prev_q;

    always_ff @(posedge clk_phy_sys or posedge sys_rst_fsm_phy) begin
        if (sys_rst_fsm_phy) begin
            current_state_q    <= S_IDLE;
            timer_q            <= 24'd0;
            data_to_write_q    <= 32'hCAFEF00D;
            data_read_q        <= 32'd0;
            status_led0_o      <= 1'b0; status_led1_o <= 1'b0; status_led2_o <= 1'b0;
            uart_char_idx_q    <= 4'd0;
            uart_current_msg_q <= UART_MSG_NONE;
        end else begin
            current_state_q    <= next_state_s;
            timer_q            <= timer_s;
            uart_char_idx_q    <= uart_char_idx_s;
            uart_current_msg_q <= uart_current_msg_s;
            if (next_state_s == S_RD_DATA_CAPTURE) begin data_read_q <= dfi_rddata_r; end
            status_led0_o <= (current_state_q != S_IDLE && current_state_q != S_DONE);
            if (current_state_q == S_DONE) begin
                status_led1_o <= data_match_r; status_led2_o <= ~data_match_r;
            end else if (next_state_s == S_IDLE) begin
                 status_led1_o <= 1'b0; status_led2_o <= 1'b0;
            end
        end
    end

    always_comb begin
        // Declare temporary variables local to this always_comb block
        logic current_msg_done_s; // <<< MOVED DECLARATION HERE

        // Default assignments
        next_state_s    = current_state_q;
        timer_s         = timer_q;
        data_match_r    = (data_to_write_q == data_read_q);
        uart_char_idx_s = uart_char_idx_q;
        uart_current_msg_s = uart_current_msg_q;
        uart_tx_start_from_fsm_s = 1'b0;
        uart_tx_data_from_fsm_s  = 8'hx; // Default to 'x' for undriven data

        current_msg_done_s = 1'b0; // Default value for the local variable

        dfi_address_s     = 15'd0; dfi_bank_s = 3'd0; dfi_cas_n_s = 1'b1;
        dfi_cke_s         = 1'b1; dfi_cs_n_s = 1'b1; dfi_odt_s = 1'b0;
        dfi_ras_n_s       = 1'b1; dfi_reset_n_s = 1'b1; dfi_we_n_s = 1'b1;
        dfi_wrdata_s      = 32'd0; dfi_wrdata_en_s = 1'b0; dfi_wrdata_mask_s = 4'hF;
        dfi_rddata_en_s   = 1'b0;

        test_addr_row_s = 15'h001A; test_addr_col_s = 15'h000F; test_bank_s = 3'b001;

        case (current_state_q)
            S_IDLE: begin
                dfi_cke_s = 1'b0; dfi_reset_n_s = 1'b0;
                if (start_cmd_edge_s) begin
                    next_state_s = S_INIT_START_RESET; timer_s = 24'd0;
                end
            end
            S_INIT_START_RESET: begin
                dfi_cke_s = 1'b0; dfi_reset_n_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= 10) begin
                    next_state_s = S_INIT_WAIT_POWER_ON; timer_s = 24'd0;
                end
            end
            S_INIT_WAIT_POWER_ON: begin
                dfi_cke_s = 1'b0; dfi_reset_n_s = 1'b1;
                timer_s = timer_q + 1;
                if (timer_q >= T_INIT_200US_CYCLES) begin
                    next_state_s = S_INIT_CKE_HIGH_WAIT; timer_s = 24'd0;
                end
            end
            S_INIT_CKE_HIGH_WAIT: begin
                dfi_cke_s = 1'b1; dfi_cs_n_s = 1'b0; // NOP
                timer_s = timer_q + 1;
                if (timer_q >= T_STAB_500US_CYCLES) begin
                    next_state_s = S_INIT_CMD_PREA; timer_s = 24'd0;
                end
            end
            S_INIT_CMD_PREA: begin
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0400; /*A10=1*/
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b0; // PREA
                timer_s = timer_q + 1; 
                if (timer_q >= T_RP_CYCLES) begin // Wait tRP
                    next_state_s = S_INIT_CMD_EMR2;
                    // timer_s will be reset by next state if it needs to count from 0
                    // For immediate MRS, no timer reset is needed here.
                end
            end
            S_INIT_CMD_EMR2: begin
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0000; /* RTT_WR: Off by default for simplicity */ dfi_bank_s = 3'b010; // EMR2
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                next_state_s = S_INIT_CMD_EMR3;
            end
            S_INIT_CMD_EMR3: begin
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0000; dfi_bank_s = 3'b011; // EMR3
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                next_state_s = S_INIT_CMD_EMR1;
            end
            S_INIT_CMD_EMR1: begin // RTT_NOM=RZQ/6 (A2=1, A6=1), DLL Enable (A0=0)
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'b000000001000100; dfi_bank_s = 3'b001; // EMR1
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                next_state_s = S_INIT_CMD_MR0_DLL_RESET;
            end
            S_INIT_CMD_MR0_DLL_RESET: begin // CL=6 (A6-A4=010), BL=8 (A1-A0=00), DLL Reset (A8=1)
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'b0000_1_0_010_0_0_00_0; dfi_bank_s = 3'b000; // MR0
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                next_state_s = S_INIT_CMD_ZQCL;
            end
            S_INIT_CMD_ZQCL: begin
                dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0400; /*A10=1 for ZQCL*/
                dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // ZQCL (NOP with CS low, A10 high)
                next_state_s = S_INIT_CMD_MR0_FINAL; timer_s = 24'd0;
            end
             S_INIT_CMD_MR0_FINAL: begin
                timer_s = timer_q + 1; // Count for tMRD (min MRS to MRS delay)
                if (timer_q >= 2) begin // Example: 2 cycles for tMRD
                    dfi_cs_n_s = 1'b0; dfi_address_s = 15'b0000_0_0_010_0_0_00_0; /* CL=6, DLL_Reset=0 */ dfi_bank_s = 3'b000; // MR0
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // MRS
                    next_state_s = S_INIT_WAIT_DLL_ZQ; timer_s = 24'd0;
                end else begin // Still in the ZQCL command part of the previous state, or just entered this state
                    // Hold previous command (ZQCL) or ensure stable prior to MRS
                    dfi_cs_n_s = 1'b0; dfi_address_s = 15'h0400; 
                    dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; 
                end
            end
            S_INIT_WAIT_DLL_ZQ: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_ZQINIT_CYCLES) begin
                    next_state_s = S_ACT_WR; timer_s = 24'd0;
                end
            end
            S_ACT_WR: begin
                dfi_cs_n_s = 1'b0; dfi_address_s = test_addr_row_s; dfi_bank_s = test_bank_s;
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // ACT
                next_state_s = S_WR_CMD; timer_s = 24'd0;
            end
            S_WR_CMD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = test_addr_col_s; dfi_bank_s = test_bank_s;
                    dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b0; // WR
                    dfi_wrdata_s = data_to_write_q; dfi_wrdata_mask_s = 4'h0; dfi_wrdata_en_s = 1'b1;
                    dfi_odt_s = 1'b1;
                    next_state_s = S_WR_DATA_WAIT; timer_s = 24'd0;
                end else begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = test_addr_row_s; dfi_bank_s = test_bank_s;
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // Keep ACT active
                end
            end
            S_WR_DATA_WAIT: begin
                dfi_wrdata_en_s = 1'b0; dfi_odt_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TPHY_WRLAT_C + 4) begin // BL=8 -> 4 DFI data phases
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
                dfi_cs_n_s = 1'b0; dfi_address_s = test_addr_row_s; dfi_bank_s = test_bank_s;
                dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // ACT
                next_state_s = S_RD_CMD; timer_s = 24'd0;
            end
            S_RD_CMD: begin
                timer_s = timer_q + 1;
                if (timer_q >= T_RCD_CYCLES) begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = test_addr_col_s; dfi_bank_s = test_bank_s;
                    dfi_ras_n_s = 1'b1; dfi_cas_n_s = 1'b0; dfi_we_n_s = 1'b1; // RD
                    dfi_rddata_en_s = 1'b1;
                    next_state_s = S_RD_DATA_WAIT; timer_s = 24'd0;
                end else begin
                    dfi_cs_n_s = 1'b0; dfi_address_s = test_addr_row_s; dfi_bank_s = test_bank_s;
                    dfi_ras_n_s = 1'b0; dfi_cas_n_s = 1'b1; dfi_we_n_s = 1'b1; // Keep ACT active
                end
            end
            S_RD_DATA_WAIT: begin
                dfi_rddata_en_s = 1'b0;
                timer_s = timer_q + 1;
                if (timer_q >= TOTAL_RD_LAT_CYCLES - 1 ) begin
                    if (dfi_rddata_valid_r) begin
                        next_state_s = S_RD_DATA_CAPTURE; timer_s = 24'd0;
                    end else if (timer_q >= TOTAL_RD_LAT_CYCLES + 10) begin // Timeout
                        $display("%t: Read data valid timeout!", $time);
                        uart_current_msg_s = UART_MSG_WR_DATA;
                        uart_char_idx_s    = 4'd0;
                        next_state_s       = S_UART_SETUP_CHAR;
                        timer_s            = 24'd0;
                    end
                end
            end
            S_RD_DATA_CAPTURE: begin
                uart_current_msg_s = UART_MSG_WR_DATA;
                uart_char_idx_s    = 4'd0;
                next_state_s       = S_UART_SETUP_CHAR;
                // timer_s not reset here, should be 0 from previous transition if valid
            end

            S_UART_SETUP_CHAR: begin
                logic [7:0] char_to_send_s; 
                logic last_char_for_msg_s; // To know if this is the last char of the current message part
                last_char_for_msg_s = 1'b0; // Default

                case(uart_current_msg_q)
                    UART_MSG_WR_DATA: begin // "W: <HHHHHHHH> " (12 chars total)
                        case(uart_char_idx_q) // uart_char_idx_q from 0 to 11
                            0: char_to_send_s = "W";
                            1: char_to_send_s = ":";
                            2: char_to_send_s = " ";
                            3,4,5,6,7,8,9,10: begin // Hex data_to_write_q (8 chars, idx 3 to 10)
                                logic [3:0] nibble; // Index for nibble from 7 down to 0
                                nibble = (data_to_write_q >> ( ( (10-uart_char_idx_q)) * 4) ) & 4'hF;
                                if (nibble < 10) char_to_send_s = nibble + "0"; else char_to_send_s = nibble - 10 + "A";
                            end
                            11: begin char_to_send_s = " "; last_char_for_msg_s = 1'b1; end
                            default: begin char_to_send_s = "?"; last_char_for_msg_s = 1'b1; end // Should not happen
                        endcase
                    end
                    UART_MSG_RD_DATA: begin // "R: <HHHHHHHH> " (12 chars total)
                         case(uart_char_idx_q) // uart_char_idx_q from 0 to 11
                            0: char_to_send_s = "R";
                            1: char_to_send_s = ":";
                            2: char_to_send_s = " ";
                            3,4,5,6,7,8,9,10: begin // Hex data_read_q (8 chars, idx 3 to 10)
                                logic [3:0] nibble; // Index for nibble from 7 down to 0
                                nibble = (data_read_q >> ( ( (10-uart_char_idx_q)) * 4) ) & 4'hF;
                                if (nibble < 10) char_to_send_s = nibble + "0"; else char_to_send_s = nibble - 10 + "A";
                            end
                            11: begin char_to_send_s = " "; last_char_for_msg_s = 1'b1; end
                            default: begin char_to_send_s = "?"; last_char_for_msg_s = 1'b1; end
                        endcase
                    end
                    UART_MSG_RESULT: begin // "- M/F \n" (5 chars total)
                        case(uart_char_idx_q) // uart_char_idx_q from 0 to 4
                            0: char_to_send_s = "-";
                            1: char_to_send_s = " ";
                            2: char_to_send_s = data_match_r ? "M" : "F";
                            3: char_to_send_s = " ";
                            4: begin char_to_send_s = "\n"; last_char_for_msg_s = 1'b1; end
                            default: begin char_to_send_s = "?"; last_char_for_msg_s = 1'b1; end
                        endcase
                    end
                    default: begin char_to_send_s = "E"; last_char_for_msg_s = 1'b1; end // Error case
                endcase

                if (!uart_tx_busy_to_fsm_r) begin
                    uart_tx_data_from_fsm_s = char_to_send_s;
                    uart_tx_start_from_fsm_s = 1'b1; // Pulse to start UART TX
                    // Pass last_char_for_msg_s to the wait state, or re-evaluate it there.
                    // For now, next state will handle advancing char_idx or message type.
                    next_state_s = S_UART_WAIT_TX_DONE;
                end
                // else, stay in S_UART_SETUP_CHAR and retry sending when UART not busy
            end

            S_UART_WAIT_TX_DONE: begin
                uart_tx_start_from_fsm_s = 1'b0; // Ensure start is a pulse, de-assert after one cycle
                if (uart_tx_done_to_fsm_r) begin // Current char has been sent
                    uart_char_idx_s = uart_char_idx_q + 1; // Tentatively advance char index

                    // Check if the character *just sent* (indexed by uart_char_idx_q) was the last of its message
                    case(uart_current_msg_q)
                        UART_MSG_WR_DATA: current_msg_done_s = (uart_char_idx_q == 11);
                        UART_MSG_RD_DATA: current_msg_done_s = (uart_char_idx_q == 11);
                        UART_MSG_RESULT:  current_msg_done_s = (uart_char_idx_q == 4);
                        default:          current_msg_done_s = 1'b1; // Should not happen, end msg
                    endcase

                    if (current_msg_done_s) begin
                        uart_char_idx_s = 4'd0; // Reset char index for the *next* message
                        case(uart_current_msg_q) // Determine *next* message type
                            UART_MSG_WR_DATA: uart_current_msg_s = UART_MSG_RD_DATA;
                            UART_MSG_RD_DATA: uart_current_msg_s = UART_MSG_RESULT;
                            UART_MSG_RESULT:  uart_current_msg_s = UART_MSG_NONE; // All messages sent
                            default:          uart_current_msg_s = UART_MSG_NONE;
                        endcase
                        
                        if (uart_current_msg_q == UART_MSG_RESULT) begin // If we just finished sending the "RESULT" message
                            next_state_s = S_DONE;
                        end else begin
                            next_state_s = S_UART_SETUP_CHAR; // Go setup the first char of the new message type
                        end
                    end else begin // More characters in the current message type
                        // uart_char_idx_s was already incremented above
                        next_state_s = S_UART_SETUP_CHAR; // Go setup the next char of the current message
                    end
                end
                // else, stay in S_UART_WAIT_TX_DONE, waiting for uart_tx_done_to_fsm_r
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

    uart_tx u_uart_tx_inst (
        .clk(clk100mhz_i), .rst(rst_for_uart),
        .tx_start(uart_tx_start_from_fsm_s), .tx_data(uart_tx_data_from_fsm_s),
        .tx_serial(uart_txd_o), .tx_busy(uart_tx_busy_to_fsm_r), .tx_done(uart_tx_done_to_fsm_r)
    );
    assign status_led3_o = uart_tx_busy_to_fsm_r;

endmodule
