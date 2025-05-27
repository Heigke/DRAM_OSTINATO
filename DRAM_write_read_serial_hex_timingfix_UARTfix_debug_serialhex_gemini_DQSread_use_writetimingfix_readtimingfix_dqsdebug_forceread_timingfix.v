`timescale 1ns / 1ps

module dram_simple (
    // System
    input  wire        CLK100MHZ,
    input  wire [3:0]  sw,
    output wire [3:0]  LED,

    // UART
    output wire        uart_txd_in,

    // DDR3 interface
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_cas_n,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [1:0]  ddr3_dm,
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_n,
    inout  wire [1:0]  ddr3_dqs_p,
    output wire [0:0]  ddr3_odt,
    output wire        ddr3_ras_n,
    output wire        ddr3_reset_n,
    output wire        ddr3_we_n
);

    // State machine
    localparam RESET     = 0;
    localparam INIT_NOP  = 1;
    localparam INIT_MRS2 = 2;
    localparam INIT_MRS3 = 3;
    localparam INIT_MRS1 = 4;
    localparam INIT_MRS0 = 5;
    localparam INIT_ZQCL = 6;
    localparam IDLE      = 7;
    localparam ACTIVATE  = 8;
    localparam WRITE     = 9;
    localparam READ      = 10;
    localparam PRECHARGE = 11;

    reg [3:0] state = RESET;
    reg [19:0] delay_cnt = 0;

    // DDR3 clock generation (200MHz from 100MHz)
    reg clk_ddr = 0;
    always @(posedge CLK100MHZ) clk_ddr <= ~clk_ddr;

    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) ddr_ck_p_inst (
        .Q(ddr3_ck_p), .C(clk_ddr), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) ddr_ck_n_inst (
        .Q(ddr3_ck_n), .C(clk_ddr), .CE(1'b1), .D1(1'b0), .D2(1'b1), .R(1'b0), .S(1'b0));

    // Control signals
    reg        reset_n = 0;
    reg        cke = 0;
    reg        cs_n = 1;
    reg        ras_n = 1;
    reg        cas_n = 1;
    reg        we_n = 1;
    reg [13:0] addr = 0;
    reg [2:0]  ba = 0;
    reg        odt = 0;

    // Data signals
    reg [15:0] dq_out = 0;  // Data to be driven onto DQ bus (from FPGA logic to IOBUF)
    reg        dq_oe = 0;   // Output enable for DQ buffers
    reg [1:0]  dqs_out = 0; // Data to be driven onto DQS bus (from FPGA logic to IOBUFDS)
                            // Note: original logic primarily uses dqs_out[0]
    reg        dqs_oe = 0;  // Output enable for DQS buffers
    reg [1:0]  dm = 0;

    // Simple read/write interface
    reg        cmd_valid = 0;
    reg        cmd_write = 0;
    reg [26:0] cmd_addr = 0;
    reg [15:0] cmd_data = 0;
    wire [15:0] read_data; // Data read from DQ bus (from IOBUF to FPGA logic)
                           // Original: wire [15:0] read_data = ddr3_dq; (This direct assignment is removed)
    reg [15:0] captured_read_data = 16'hDEAD;
    reg [15:0] last_write_data = 16'hBEEF;
	reg [15:0] captured_read_data_posedge = 16'hDEAD;
	reg [15:0] captured_read_data_negedge = 16'hDEAD;
	reg dqs_capture_en = 0;

    // MANUAL ADD
    reg [4:0] read_capture_delay = 0;
    reg capture_read_now = 0;
    // MANUAL add
    
    // Operation complete signals from DDR domain
    reg        write_complete_ddr = 0;
    reg        read_complete_ddr = 0;
     reg dqs0_toggled = 0;
     // Add these declarations near the other signal declarations (around line 80)
reg [15:0] read_data_prev = 0;
reg [2:0] read_stable_cnt = 0;
     wire [15:0] dq_tristate;
     reg [7:0] read_data_change_cnt = 0;
     // Similar logic for DQS1 (upper byte) - ADD THESE
reg [15:0] read_data_prev_upper = 0;
reg [2:0] read_stable_cnt_upper = 0;
assign dq_tristate = {16{!dq_oe}};  // 1 means input mode

    reg dqs1_toggled = 0;
    reg [15:0] read_data_raw = 0;
    reg [15:0] write_data_ddr = 0;
    reg [15:0] read_data_ddr = 0;

    // Synchronized to 100MHz domain
    reg [1:0]  write_complete_sync = 0;
    reg [1:0]  read_complete_sync = 0;
    reg        write_complete = 0;
    reg        read_complete = 0;
    reg [15:0] write_data_sync = 0;
    reg [15:0] read_data_sync = 0;

    // UART signals
    reg        uart_send = 0;
    reg [7:0]  uart_data = 0;
    wire       uart_busy;
    wire       uart_done;

    // UART message control
    reg        send_hex_value = 0;
    reg [15:0] hex_value_to_send = 0;
    reg        hex_is_write = 0;

    // Switch handling
    reg [3:0] sw_sync = 0;
    reg [3:0] sw_prev = 0;

    always @(posedge CLK100MHZ) begin
        sw_sync <= sw;
        sw_prev <= sw_sync;
    end

    wire sw0_pressed = sw_sync[0] && !sw_prev[0];
    wire sw1_pressed = sw_sync[1] && !sw_prev[1];
    wire sw2_pressed = sw_sync[2] && !sw_prev[2];
    wire sw3_pressed = sw_sync[3] && !sw_prev[3];

    // Test pattern counter
    reg [3:0] pattern_cnt = 0;
reg [7:0] hex_timeout = 0;

    // Clock domain crossing - DDR to 100MHz
    always @(posedge CLK100MHZ) begin
        // Synchronize completion signals
        write_complete_sync <= {write_complete_sync[0], write_complete_ddr};
        read_complete_sync <= {read_complete_sync[0], read_complete_ddr};

        // Edge detection
        write_complete <= write_complete_sync[0] && !write_complete_sync[1];
        read_complete <= read_complete_sync[0] && !read_complete_sync[1];

        // Capture data when complete
        if (write_complete) begin
            write_data_sync <= write_data_ddr;
        end
        if (read_complete) begin
            read_data_sync <= read_data_ddr;
        end
    end

    // UART hex sender state machine
    reg [4:0] hex_state = 0;

    // Function to convert 4-bit hex to ASCII
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 10)
                hex_to_ascii = 8'h30 + hex;  // '0'-'9'
            else
                hex_to_ascii = 8'h41 + (hex - 10);  // 'A'-'F'
        end
    endfunction

    // UART output handler - only driven from this always block
    always @(posedge CLK100MHZ) begin
    // Timeout logic
    if (hex_state != 0) begin
        hex_timeout <= hex_timeout + 1;
        if (hex_timeout == 8'hFF) begin
            hex_state <= 0;
            uart_send <= 0;
            hex_timeout <= 0;
        end
    end else begin
        hex_timeout <= 0;
    end

        case (hex_state)
            0: begin  // Idle
                uart_send <= 0;
                send_hex_value <= 0;

                if (sw2_pressed) begin  // Debug state
                    hex_value_to_send <= {12'h000, state};
                    hex_is_write <= 0;
                    hex_state <= 1;
                end
                else if (write_complete) begin
                    hex_value_to_send <= write_data_sync;
                    hex_is_write <= 1;
                    hex_state <= 1;
                end
                else if (read_complete) begin
                    hex_value_to_send <= read_data_sync;
                    hex_is_write <= 0;
                    hex_state <= 1;
                end
            end

            1: begin  // Send W/R
                if (!uart_busy) begin
                    uart_data <= hex_is_write ? 8'h57 : 8'h52;  // 'W' or 'R'
                    uart_send <= 1;
                    send_hex_value <= 1;
                    hex_state <= 2;
                end
            end

            2: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 3;
            end

            3: begin  // Send ':'
                if (!uart_busy) begin
                    uart_data <= 8'h3A;
                    uart_send <= 1;
                    hex_state <= 4;
                end
            end

            4: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 5;
            end

            // Send 4 hex digits
            5: begin
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value_to_send[15:12]);
                    uart_send <= 1;
                    hex_state <= 6;
                end
            end

            6: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 7;
            end

            7: begin
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value_to_send[11:8]);
                    uart_send <= 1;
                    hex_state <= 8;
                end
            end

            8: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 9;
            end

            9: begin
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value_to_send[7:4]);
                    uart_send <= 1;
                    hex_state <= 10;
                end
            end

            10: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 11;
            end

            11: begin
                if (!uart_busy) begin
                    uart_data <= hex_to_ascii(hex_value_to_send[3:0]);
                    uart_send <= 1;
                    hex_state <= 12;
                end
            end

            12: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 13;
            end

            13: begin  // Send newline
                if (!uart_busy) begin
                    uart_data <= 8'h0A;
                    uart_send <= 1;
                    hex_state <= 14;
                end
            end

            14: begin
                uart_send <= 0;
                if (!uart_busy) hex_state <= 0;
            end

            default: hex_state <= 0;
        endcase
    end

    // Output assignments (for control signals)
    assign ddr3_reset_n = reset_n;
    assign ddr3_cke = cke;
    assign ddr3_cs_n = cs_n;
    assign ddr3_ras_n = ras_n;
    assign ddr3_cas_n = cas_n;
    assign ddr3_we_n = we_n;
    assign ddr3_addr = addr;
    assign ddr3_ba = ba;
    assign ddr3_odt = odt;
    assign ddr3_dm = dm;

    // --- MODIFIED SECTION FOR I/O BUFFERS ---
    // Original bidirectional data assignments are removed:
    // assign ddr3_dq = dq_oe ? dq_out : 16'bz;
    // assign ddr3_dqs_p = dqs_oe ? {2{dqs_out[0]}} : 2'bz;
    // assign ddr3_dqs_n = dqs_oe ? {2{~dqs_out[0]}} : 2'bz;

    // Instantiate IOBUF for each DQ bit
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : dq_iob_loop
           IOBUF #(
    .IOSTANDARD("SSTL135"),
    .IBUF_LOW_PWR("FALSE"),
    .SLEW("FAST")
) dq_iobuf_inst (
    .O(read_data[i]),
    .IO(ddr3_dq[i]),
    .I(dq_out[i]),
    .T(!dq_oe)
);

        end
    endgenerate

    // Instantiate IOBUFDS for each DQS pair
    // Dummy wires for DQS input path, as original logic doesn't use DQS for read capture timing.
    //wire dqs_p_in_dummy0;
    //wire dqs_p_in_dummy1;
    wire dqs_p_in0;  // DQS0 input from memory
    wire dqs_p_in1;  // DQS1 input from memory

    // DQS0 pair (ddr3_dqs_p[0], ddr3_dqs_n[0])
    // Driven by dqs_out[0] as per original logic
    IOBUFDS #(
    .IOSTANDARD("DIFF_SSTL135")
) dqs0_iobufds_inst (
    .O(dqs_p_in0),          // DQS input from memory
    .IO(ddr3_dqs_p[0]),
    .IOB(ddr3_dqs_n[0]),
    .I(dqs_out[0]),
    .T(!dqs_oe)
);

IOBUFDS #(
    .IOSTANDARD("DIFF_SSTL135")
) dqs1_iobufds_inst (
    .O(dqs_p_in1),          // DQS input from memory
    .IO(ddr3_dqs_p[1]),
    .IOB(ddr3_dqs_n[1]),
    .I(dqs_out[0]),
    .T(!dqs_oe)
);

    // --- END OF MODIFIED SECTION ---
    // This captures data on both edges of the DDR clock during read window
	// Capture on positive edge of DQS0
	always @(posedge dqs_p_in0) begin
    if (dqs_capture_en) begin
        if (read_data_prev[7:0] == read_data[7:0] && read_data[7:0] != 8'h00) begin
            read_stable_cnt <= read_stable_cnt + 1;
            if (read_stable_cnt == 3'd3)
                captured_read_data_posedge[7:0] <= read_data[7:0];
        end else begin
            read_stable_cnt <= 0;
            read_data_prev[7:0] <= read_data[7:0];
        end
    end
end



	// Capture on negative edge of DQS0
	always @(negedge dqs_p_in0) begin
	    if (dqs_capture_en) begin
		captured_read_data_negedge[7:0] <= read_data[7:0];
	    end
	end

	// Capture upper byte on DQS1
	always @(posedge dqs_p_in1) begin
    if (dqs_capture_en) begin
        if (read_data_prev_upper[15:8] == read_data[15:8] && read_data[15:8] != 8'h00) begin
            read_stable_cnt_upper <= read_stable_cnt_upper + 1;
            if (read_stable_cnt_upper == 3'd3)
                captured_read_data_posedge[15:8] <= read_data[15:8];
        end else begin
            read_stable_cnt_upper <= 0;
            read_data_prev_upper[15:8] <= read_data[15:8];
        end
    end
end

	always @(negedge dqs_p_in1) begin
	    if (dqs_capture_en) begin
		captured_read_data_negedge[15:8] <= read_data[15:8];
	    end
	end


    // UART instance
    uart_tx #(.CLKS_PER_BIT(868)) uart_tx_inst ( // 100MHz / 115200bps = 868.05 ~ 868
        .clk(CLK100MHZ),
        .rst(1'b0), // Assuming no explicit reset for UART in this design
        .tx_start(uart_send),
        .tx_data(uart_data),
        .tx_serial(uart_txd_in),
        .tx_busy(uart_busy),
        .tx_done(uart_done)
    );

    // DDR3 commands
    task deselect;
        begin
            cs_n <= 1; ras_n <= 1; cas_n <= 1; we_n <= 1;
        end
    endtask

    task nop;
        begin
            cs_n <= 0; ras_n <= 1; cas_n <= 1; we_n <= 1;
        end
    endtask

    task precharge_all;
        begin
            cs_n <= 0; ras_n <= 0; cas_n <= 1; we_n <= 0; addr[10] <= 1; // A10 high for Precharge All
        end
    endtask

    task load_mode(input [2:0] mr, input [13:0] value);
        begin
            cs_n <= 0; ras_n <= 0; cas_n <= 0; we_n <= 0; ba <= mr; addr <= value;
        end
    endtask

    task activate(input [2:0] bank, input [13:0] row);
        begin
            cs_n <= 0; ras_n <= 0; cas_n <= 1; we_n <= 1; ba <= bank; addr <= row;
        end
    endtask

    task write_cmd(input [2:0] bank, input [9:0] col);
        begin
            cs_n <= 0; ras_n <= 1; cas_n <= 0; we_n <= 0; ba <= bank; addr[9:0] <= col; addr[10] <= 0; // A10 low for no Auto Precharge
        end
    endtask

    task read_cmd(input [2:0] bank, input [9:0] col);
        begin
            cs_n <= 0; ras_n <= 1; cas_n <= 0; we_n <= 1; ba <= bank; addr[9:0] <= col; addr[10] <= 0; // A10 low for no Auto Precharge
        end
    endtask

    // Main DDR3 state machine - only drives DDR domain signals
    always @(posedge clk_ddr) begin
        delay_cnt <= delay_cnt + 1;

        // Clear completion flags after they've been captured
        if (write_complete_ddr) write_complete_ddr <= 0;
        if (read_complete_ddr) read_complete_ddr <= 0;

        case (state)
            RESET: begin
                reset_n <= 0; cke <= 0; deselect();
                if (delay_cnt > 20'd100000) begin // > 500us @ 200MHz DDR clock (tPW_RESET > 200us)
                    reset_n <= 1; state <= INIT_NOP; delay_cnt <= 0;
                end
            end

            INIT_NOP: begin // Wait for CKE to be stable, and NOPs
                cke <= 1; nop();
                if (delay_cnt > 20'd100000) begin // > 500us (tSTAB > 500us after reset_n high)
                    state <= INIT_MRS2; delay_cnt <= 0;
                end
            end

            INIT_MRS2: begin
                if (delay_cnt == 0) load_mode(3'd2, 14'b00000000001000);  // MR2: CWL=6 (A5A4A3=010 for CWL=6)
                else if (delay_cnt < 10) nop(); // tMRD = 4 nCK
                else begin state <= INIT_MRS3; delay_cnt <= 0; end
            end

            INIT_MRS3: begin
                if (delay_cnt == 0) load_mode(3'd3, 14'b0); // MR3: No MPR
                else if (delay_cnt < 10) nop(); // tMRD
                else begin state <= INIT_MRS1; delay_cnt <= 0; end
            end

                        INIT_MRS1: begin
		if (delay_cnt == 0) load_mode(3'd1, 14'b00000001000110); // Enable ODT RZQ/6
                else if (delay_cnt < 10) nop();
                else begin state <= INIT_MRS0; delay_cnt <= 0; end
            end


            INIT_MRS0: begin
                // Original: 14'b00010100110000
                // A12(PPD)=0, A11-9(WR)=010 (WR=6 tCK), A8(DLL_RST)=1, A7(Mode)=0,
                // A6,A4,A2(CL)=100 (CL=9 tCK), A5(RBT)=1 (Interleaved), A3(TDQS)=0, A1,A0(BL)=00 (BL8)
                if (delay_cnt == 0) load_mode(3'd0, 14'b00010100110000);
                else if (delay_cnt < 10) nop(); // tMOD = max(12nCK, 15ns) -> 12 nCK for 200MHz clock.
                else begin state <= INIT_ZQCL; delay_cnt <= 0; end
            end

            INIT_ZQCL: begin
                if (delay_cnt == 0) begin // ZQCL command
                    cs_n <= 0; ras_n <= 1; cas_n <= 1; we_n <= 0; addr[10] <= 1; // ZQCL: WE_n=0, RAS_n=1, CAS_n=1, A10=1
                end
                else if (delay_cnt < 512) nop(); // tZQinit = 512 nCK.
                else begin state <= IDLE; delay_cnt <= 0; end
            end

            IDLE: begin
                deselect(); odt <= 0; dq_oe <= 0; dqs_oe <= 0;
                if (sw_sync[0] && !cmd_valid) begin // Write command from switch
                    cmd_valid <= 1; cmd_write <= 1;
                    cmd_addr <= {3'b000, 14'h0000, 10'h000}; // Bank 0, Row 0, Col 0
                    case (pattern_cnt[1:0])
                        0: cmd_data <= 16'hA5A5;
                        1: cmd_data <= 16'h5A5A;
                        2: cmd_data <= 16'hFFFF;
                        3: cmd_data <= 16'h0000;
                    endcase
                    last_write_data <= cmd_data;
                    pattern_cnt <= pattern_cnt + 1;
                    state <= ACTIVATE; delay_cnt <= 0;
                end
                else if (sw_sync[1] && !cmd_valid) begin // Read command from switch
                    cmd_valid <= 1; cmd_write <= 0;
                    cmd_addr <= {3'b000, 14'h0000, 10'h000}; // Bank 0, Row 0, Col 0
                    state <= ACTIVATE; delay_cnt <= 0;
                end
            end

            ACTIVATE: begin // tRCD = Row to Column Delay. For CL=9, tRCD is typically also around 9 cycles.
                           // Arty A7 MT41K128M16JT-125: tRCD=13.75ns. At 200MHz (5ns/cycle), this is ~3 cycles.
                           // Your delay_cnt < 5 is okay (5*5ns = 25ns).
                if (delay_cnt == 0) activate(cmd_addr[26:24], cmd_addr[23:10]);
                else if (delay_cnt < 5) nop(); // Wait for tRCD
                else begin
                    state <= cmd_write ? WRITE : READ; delay_cnt <= 0;
                end
            end

           WRITE: begin
    if (delay_cnt == 0) begin
        write_cmd(cmd_addr[26:24], cmd_addr[9:0]);
        dm <= 2'b00;
    end
    // Start DQS preamble at CWL-1 = 6
    else if (delay_cnt == 6) begin
        dqs_oe <= 1;
        dqs_out <= 2'b00;  // DQS low (preamble)
        nop();
    end
    // Start data and DQS toggling at CWL = 7
    else if (delay_cnt == 7) begin
        dq_out <= cmd_data;
        dq_oe <= 1;
        dqs_out[0] <= 1;  // DQS starts high
        nop();
    end
    // Toggle DQS for 4 cycles (BL8 = 4 DQS cycles, 8 half-cycles)
    else if (delay_cnt >= 8 && delay_cnt <= 14) begin
        dqs_out[0] <= ~dqs_out[0];
        nop();
    end
    // End of burst
    else if (delay_cnt == 15) begin
        dq_oe <= 0;
        dqs_oe <= 0;
        write_data_ddr <= last_write_data;
        write_complete_ddr <= 1;
        nop();
    end
    else if (delay_cnt > 20) begin
        state <= PRECHARGE;
        delay_cnt <= 0;
    end
    else begin
        nop();
    end
end


          READ: begin
    if (delay_cnt == 0) begin
        read_cmd(cmd_addr[26:24], cmd_addr[9:0]);
        odt <= 1;            // Enable ODT right away for reads
        dq_oe <= 0;          // DQ input
        dqs_oe <= 0;         // DQS input
        dqs_capture_en <= 0; // Wait before capturing
        captured_read_data <= 16'hDEAD;
    end
    // ODT needs a couple cycles to take effect (tAOND ~2 cycles)
    else if (delay_cnt == 2) begin
        odt <= 1;  // Still on
        nop();
    end
    // Enable capture window *early* (CL=9, so start at 16)
    else if (delay_cnt == 16) begin
        dqs_capture_en <= 1;
        nop();
    end
    // Capture window off after burst
    else if (delay_cnt == 24) begin
        dqs_capture_en <= 0;
        // Save captured data (see next section for better capture)
        captured_read_data <= captured_read_data_posedge;
        nop();
    end
    // ODT off and latch data to output
    else if (delay_cnt == 26) begin
        odt <= 0;
        read_data_ddr <= captured_read_data;
        read_complete_ddr <= 1;
        nop();
    end
    else if (delay_cnt > 32) begin
        state <= PRECHARGE;
        delay_cnt <= 0;
    end
    else begin
        nop();
    end
end



            PRECHARGE: begin
    if (delay_cnt == 0) precharge_all();
    else if (delay_cnt < 5) nop();
    else begin
        cmd_valid <= 0; // Moved here
        state <= IDLE;
        delay_cnt <= 0;
    end
end


            default: state <= IDLE;
        endcase
    end


    // --- Debug: Monitor DQS and DQ activity ---
    always @(posedge clk_ddr) begin
        read_data_raw <= read_data;  // Capture raw read data continuously

        if (dqs_p_in0)
            dqs0_toggled <= 1;       // Latch if DQS0 ever goes high
        if (dqs_p_in1)
            dqs1_toggled <= 1;       // Latch if DQS1 ever goes high
    end
reg [15:0] read_data_any = 0;
always @(posedge clk_ddr) begin
    if (read_data != 16'h0000)
        read_data_any <= read_data;
end
// Add logic to count changes
always @(posedge clk_ddr) begin
    if (read_data != read_data_raw)
        read_data_change_cnt <= read_data_change_cnt + 1;
end

    // LED indicators
    reg [25:0] led_cnt = 0;
    always @(posedge CLK100MHZ) led_cnt <= led_cnt + 1;

    assign LED[0] = led_cnt[25];                                  // Heartbeat
    assign LED[1] = (state == IDLE);                              // In IDLE
    assign LED[2] = (captured_read_data == last_write_data);      // Data match
    assign LED[3] = (state > INIT_ZQCL && state != RESET);        // Initialized and not in reset (safer check)

    // ILA for debugging
    ila_0 ila_inst (
        .clk(CLK100MHZ),
        .probe0(state),              // 4 bits
        .probe1(sw_sync),            // 4 bits
        .probe2(cmd_valid),          // 1 bit
        .probe3(cmd_write),          // 1 bit
        .probe4(send_hex_value),     // 1 bit
        .probe5(dq_oe),              // 1 bit
        .probe6(captured_read_data), // 16 bits
        .probe7(last_write_data),    // 16 bits
        .probe8(delay_cnt[7:0]),     // 8 bits
        .probe9({ddr3_cas_n, ddr3_ras_n, ddr3_we_n, ddr3_cs_n}), // 4 bits
        .probe10(odt),               // 1 bit
        .probe11(hex_state[2:0]),     // 3 bits
            .probe12(dqs_p_in0),         // 1 bit
    .probe13(dqs_capture_en),     // 1 bit
        .probe14(read_data_change_cnt),  // <-- Add this line
                .probe15(dqs0_toggled),     // <--- Add this line
        .probe16(dqs1_toggled),     // <--- Add this line
        .probe17(read_data_raw),    // <--- Add this line (16 bits)
                .probe18(dq_tristate[0]),    // <-- Add this as a 1-bit probe (shows 1 in read state)
                        .probe19(read_data_any)     // <-- 16 bits, bump ILA probe count


    );

endmodule

