`timescale 1ns/1ps

module tb_uart_debug;

    reg clk = 0;
    reg rst = 1;

    // UART lines
    reg  uart_rx = 1;     // Idle = 1
    wire uart_tx;
    wire [3:0] leds;

    // Clock gen: 100MHz
    always #5 clk = ~clk; // 10ns period

    // Instantiate DUT (your top)
    top dut (
        .clk100mhz   (clk),
        .uart_rx_i   (uart_rx),
        .uart_tx_o   (uart_tx),
        .led         (leds)
    );

    // Simple reset
    initial begin
        rst = 1;
        #100;
        rst = 0;
    end

    // UART send task (8-N-1, LSB first)
    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            // Start bit
            uart_rx = 0; #(8680); // 1/115200 ≈ 8.68us (86.8*100ns ticks)
            // Data bits
            for (i=0; i<8; i=i+1) begin
                uart_rx = data[i];
                #(8680);
            end
            // Stop bit
            uart_rx = 1; #(8680);
        end
    endtask

    // Send a string over UART
    task uart_send_string(input string s);
        integer i;
        begin
            for (i=0; i<$size(s); i=i+1)
                uart_send_byte(s[i]);
        end
    endtask

    // Capture TX output (for debugging)
    initial begin
        $dumpfile("uart_debug.vcd");
        $dumpvars(0, tb_uart_debug);
    end

    // Test sequence
    initial begin
        uart_rx = 1; // idle
        #200_000;    // Wait some time after reset

        // Send "?\r"
        uart_send_byte("?");
        uart_send_byte(8'h0d); // CR

        #100_000; // Wait

        // Send "t\r"
        uart_send_byte("t");
        uart_send_byte(8'h0d);

        #100_000;

        // Send "RAAAAAAAA\r"
        uart_send_byte("R");
        repeat (8) uart_send_byte("A");
        uart_send_byte(8'h0d);

        #100_000;

        // Send "W12345678 89ABCDEF\r"
        uart_send_byte("W");
        uart_send_byte("1"); uart_send_byte("2"); uart_send_byte("3"); uart_send_byte("4");
        uart_send_byte("5"); uart_send_byte("6"); uart_send_byte("7"); uart_send_byte("8");
        uart_send_byte(" ");
        uart_send_byte("8"); uart_send_byte("9"); uart_send_byte("A"); uart_send_byte("B");
        uart_send_byte("C"); uart_send_byte("D"); uart_send_byte("E"); uart_send_byte("F");
        uart_send_byte(8'h0d);

        #200_000;

        $finish;
    end

endmodule

