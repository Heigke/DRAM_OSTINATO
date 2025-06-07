`timescale 1ns/1ps
// ========================================================================
//  Testbench for UART-Debug V2 design
// ========================================================================

module tb_uart_debug;

    //---------------------------------------------------------------------
    // 100-MHz clock
    //---------------------------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;                 // 10-ns period → 100 MHz

    //---------------------------------------------------------------------
    // DUT wiring
    //---------------------------------------------------------------------
    reg  uart_rx = 1;                     // line idle = 1
    wire uart_tx;
    wire [3:0] leds;
    
    // Reset signal
    wire rst;

    top dut (
        .clk100mhz (clk),
        .uart_rx_i (uart_rx),
        .uart_tx_o (uart_tx),
        .led       (leds)
    );
    
    // Access internal signals for debugging
    assign rst = dut.rst;

    //---------------------------------------------------------------------
    // Byte transmitter (8-N-1, 115200 baud)
    //---------------------------------------------------------------------
    localparam real BAUD_PERIOD = 1000000000.0/115200.0; // in ns
    localparam integer BIT_TIME = 8680;     // 8680 ns

    task automatic uart_send_byte (input [7:0] b);
        integer k;
        begin
            $display("  [%0t] Sending byte: 0x%02X ('%c')", $time, b, b);
            uart_rx = 0;                #(BIT_TIME);           // start bit
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx = b[k];         #(BIT_TIME);           // data bits
            end
            uart_rx = 1;                #(BIT_TIME);           // stop bit
        end
    endtask

    //---------------------------------------------------------------------
    // Perfect monitor: reuse rtl uart_rx on uart_tx line
    //---------------------------------------------------------------------
    wire mon_stb;
    wire [7:0] mon_data;

    uart_rx #(
        .CLK_HZ   (100_000_000),
        .BAUDRATE (115200)
    ) MON (
        .clk_i  (clk),
        .rst_i  (1'b0),
        .rx_i   (uart_tx),
        .stb_o  (mon_stb),
        .data_o (mon_data)
    );

    // Monitor for debugging
    always @(posedge clk) begin
        if (dut.u_dbg.rx_stb) begin
            $display("  [%0t] DUT RX received: 0x%02X ('%c')", $time, dut.u_dbg.rx_data, dut.u_dbg.rx_data);
        end
        if (dut.u_dbg.tx_stb) begin
            $display("  [%0t] DUT TX sending: 0x%02X ('%c')", $time, dut.u_dbg.tx_data, dut.u_dbg.tx_data);
        end
    end

    integer mon_fp;
    
    initial mon_fp = $fopen("tb_uart_output.txt", "w");

    // Output monitor
    always @(posedge clk) if (mon_stb) begin
        $display("  [%0t] Monitor RX: 0x%02X ('%c')", $time, mon_data, mon_data);
        if (mon_data == 8'h0D || mon_data == 8'h0A) begin
            $write("\n");
            $fwrite(mon_fp, "\n");
        end else begin
            $write("%c", mon_data);
            $fwrite(mon_fp, "%c", mon_data);
        end
    end

    //---------------------------------------------------------------------
    // Debug state monitor - for V2 signals
    //---------------------------------------------------------------------
    reg [2:0] prev_tx_state = 0;
    always @(posedge clk) begin
        if (dut.u_dbg.tx_state != prev_tx_state) begin
            $display("  [%0t] TX state changed from %d to %d", 
                $time, prev_tx_state, dut.u_dbg.tx_state);
            prev_tx_state <= dut.u_dbg.tx_state;
        end
    end
    
    // Monitor command ready pulses
    always @(posedge clk) begin
        if (dut.u_dbg.cmd_status_rdy)
            $display("  [%0t] Command ready: STATUS", $time);
        if (dut.u_dbg.cmd_read_rdy)
            $display("  [%0t] Command ready: READ addr=0x%08X", $time, dut.u_dbg.cmd_addr);
        if (dut.u_dbg.cmd_write_rdy)
            $display("  [%0t] Command ready: WRITE addr=0x%08X data=0x%08X", 
                $time, dut.u_dbg.cmd_addr, dut.u_dbg.cmd_data);
        if (dut.u_dbg.cmd_time_rdy)
            $display("  [%0t] Command ready: SET TIME cfg=0x%08X", $time, dut.u_dbg.timing_cfg);
        if (dut.u_dbg.cmd_get_time_rdy)
            $display("  [%0t] Command ready: GET TIME", $time);
    end

    //---------------------------------------------------------------------
    // Stimulus
    //---------------------------------------------------------------------
    initial begin
        $display("\n=== UART Debug V2 Testbench Starting ===");
        $display("Bit time = %0d ns", BIT_TIME);
        
        uart_rx = 1;
        #100_000;  // 100us initial wait

        // Wait for reset to complete
        $display("\n[%0t] Waiting for reset...", $time);
        wait(rst == 0);
        $display("[%0t] Reset complete", $time);
        #100_000;

        // ?\r - Status query
        $display("\n[%0t] ---- Sending: ?\\r ----", $time);
        uart_send_byte("?");
        #10_000;
        uart_send_byte(8'h0D);
        #1_000_000;  // Wait 1ms for response

        // t\r - Time query
        $display("\n[%0t] ---- Sending: t\\r ----", $time);
        uart_send_byte("t");
        #10_000;
        uart_send_byte(8'h0D);
        #1_000_000;

        // T01020304\r - Set timing
        $display("\n[%0t] ---- Sending: T01020304\\r ----", $time);
        uart_send_byte("T");
        #10_000;
        uart_send_byte("0"); #10_000; uart_send_byte("1"); #10_000;
        uart_send_byte("0"); #10_000; uart_send_byte("2"); #10_000;
        uart_send_byte("0"); #10_000; uart_send_byte("3"); #10_000;
        uart_send_byte("0"); #10_000; uart_send_byte("4"); #10_000;
        uart_send_byte(8'h0D);
        #1_000_000;

        // RAAAAAAAA\r - Read command
        $display("\n[%0t] ---- Sending: RAAAAAAAA\\r ----", $time);
        uart_send_byte("R");
        #10_000;
        repeat(8) begin
            uart_send_byte("A"); 
            #10_000;
        end
        uart_send_byte(8'h0D);
        #1_000_000;

        // W12345678 89ABCDEF\r - Write command
        $display("\n[%0t] ---- Sending: W12345678 89ABCDEF\\r ----", $time);
        uart_send_byte("W");
        #10_000;
        uart_send_byte("1"); #10_000; uart_send_byte("2"); #10_000; 
        uart_send_byte("3"); #10_000; uart_send_byte("4"); #10_000;
        uart_send_byte("5"); #10_000; uart_send_byte("6"); #10_000; 
        uart_send_byte("7"); #10_000; uart_send_byte("8"); #10_000;
        uart_send_byte(" ");
        #10_000;
        uart_send_byte("8"); #10_000; uart_send_byte("9"); #10_000; 
        uart_send_byte("A"); #10_000; uart_send_byte("B"); #10_000;
        uart_send_byte("C"); #10_000; uart_send_byte("D"); #10_000; 
        uart_send_byte("E"); #10_000; uart_send_byte("F"); #10_000;
        uart_send_byte(8'h0D);
        #1_000_000;

        // Multiple quick t\r commands
        $display("\n[%0t] ---- Sending: five quick t\\r ----", $time);
        repeat (5) begin
            uart_send_byte("t");
            #10_000;
            uart_send_byte(8'h0D);
            #500_000;  // 500us between commands
        end

        #1_000_000;
        $display("\n[%0t] ---- TB finished ----", $time);
        $display("=== Test Summary ===");
        $display("Check tb_uart_output.txt for captured output");
        $fclose(mon_fp);
        $finish;
    end

    //---------------------------------------------------------------------
    // Timeout watchdog
    //---------------------------------------------------------------------
    initial begin
        #20_000_000;  // 20ms timeout
        $display("\n[%0t] ERROR: Testbench timeout!", $time);
        $finish;
    end

    //---------------------------------------------------------------------
    // Wave dump
    //---------------------------------------------------------------------
    initial begin
        $dumpfile("uart_debug.vcd");
        $dumpvars(0, tb_uart_debug);
        // Dump internal signals for debugging
        $dumpvars(0, dut.u_dbg);
    end

endmodule