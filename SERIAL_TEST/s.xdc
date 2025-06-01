## Arty-A7 USB-UART 115 200-baud self-test

# PC → FPGA  (FTDI U0_TXD)
set_property PACKAGE_PIN A9  [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]

# FPGA → PC  (FTDI U0_RXD)
set_property PACKAGE_PIN D10 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]

