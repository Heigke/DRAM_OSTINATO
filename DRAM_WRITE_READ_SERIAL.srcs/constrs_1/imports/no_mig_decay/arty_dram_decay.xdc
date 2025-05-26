# Arty A7-100T Constraints for DDR3 DRAM Decay Test
# Save as: arty_dram_decay.xdc

## System Clock (100MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK100MHZ]

## Switches
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]

## LEDs
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { LED[0] }] 
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { LED[1] }]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { LED[2] }]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }]

## UART
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in }]

## DDR3 Memory
## Memory address lines
set_property -dict { PACKAGE_PIN R2 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[0]}]
set_property -dict { PACKAGE_PIN M6 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[1]}]
set_property -dict { PACKAGE_PIN N4 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[2]}]
set_property -dict { PACKAGE_PIN T1 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[3]}]
set_property -dict { PACKAGE_PIN N6 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[4]}]
set_property -dict { PACKAGE_PIN R7 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[5]}]
set_property -dict { PACKAGE_PIN V6 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[6]}]
set_property -dict { PACKAGE_PIN U7 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[7]}]
set_property -dict { PACKAGE_PIN R8 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[8]}]
set_property -dict { PACKAGE_PIN V7 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[9]}]
set_property -dict { PACKAGE_PIN R6 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[10]}]
set_property -dict { PACKAGE_PIN U6 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[11]}]
set_property -dict { PACKAGE_PIN T6 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[12]}]
set_property -dict { PACKAGE_PIN T8 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_addr[13]}]
set_property -dict { PACKAGE_PIN R1 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_ba[0]}]
set_property -dict { PACKAGE_PIN P4 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_ba[1]}]
set_property -dict { PACKAGE_PIN P2 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_ba[2]}]

## Clock lines
set_property -dict { PACKAGE_PIN U9 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_ck_p}]
set_property -dict { PACKAGE_PIN V9 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_ck_n}]

# Create DDR3 clock constraint after the port is defined
create_clock -period 5.000 -name ddr3_clk [get_ports ddr3_ck_p]

## Data mask
set_property -dict { PACKAGE_PIN L1 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_dm[0]}]
set_property -dict { PACKAGE_PIN U1 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_dm[1]}]

## Data (DQ) lines
set_property -dict { PACKAGE_PIN K5 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[0]}]
set_property -dict { PACKAGE_PIN L3 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[1]}]
set_property -dict { PACKAGE_PIN K3 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[2]}]
set_property -dict { PACKAGE_PIN L6 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[3]}]
set_property -dict { PACKAGE_PIN M3 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[4]}]
set_property -dict { PACKAGE_PIN M1 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[5]}]
set_property -dict { PACKAGE_PIN L4 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[6]}]
set_property -dict { PACKAGE_PIN M2 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[7]}]
set_property -dict { PACKAGE_PIN V4 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[8]}]
set_property -dict { PACKAGE_PIN T5 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[9]}]
set_property -dict { PACKAGE_PIN U4 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[10]}]
set_property -dict { PACKAGE_PIN V5 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[11]}]
set_property -dict { PACKAGE_PIN V1 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[12]}]
set_property -dict { PACKAGE_PIN T3 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[13]}]
set_property -dict { PACKAGE_PIN U3 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[14]}]
set_property -dict { PACKAGE_PIN R3 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dq[15]}]

## DQS
set_property -dict { PACKAGE_PIN N2 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dqs_p[0]}]
set_property -dict { PACKAGE_PIN U2 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dqs_p[1]}]
set_property -dict { PACKAGE_PIN N1 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dqs_n[0]}]
set_property -dict { PACKAGE_PIN V2 IOSTANDARD SSTL135 SLEW FAST IN_TERM UNTUNED_SPLIT_50 } [get_ports {ddr3_dqs_n[1]}]

## Command wires
set_property -dict { PACKAGE_PIN K6 IOSTANDARD SSTL135 SLEW FAST } [get_ports ddr3_reset_n]
set_property -dict { PACKAGE_PIN N5 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_cke[0]}]
set_property -dict { PACKAGE_PIN U8 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_cs_n[0]}]
set_property -dict { PACKAGE_PIN P3 IOSTANDARD SSTL135 SLEW FAST } [get_ports ddr3_ras_n]
set_property -dict { PACKAGE_PIN M4 IOSTANDARD SSTL135 SLEW FAST } [get_ports ddr3_cas_n]
set_property -dict { PACKAGE_PIN P5 IOSTANDARD SSTL135 SLEW FAST } [get_ports ddr3_we_n]
set_property -dict { PACKAGE_PIN R5 IOSTANDARD SSTL135 SLEW FAST } [get_ports {ddr3_odt[0]}]

## Internal VREF
set_property INTERNAL_VREF 0.675 [get_iobanks 34]

# False paths for asynchronous signals
set_false_path -to [get_ports LED[*]]
set_false_path -from [get_ports sw[*]]