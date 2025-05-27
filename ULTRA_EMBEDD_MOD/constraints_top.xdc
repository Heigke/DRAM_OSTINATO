# arty_a7_100_decay_test.xdc
# Constraints for DDR3 Decay Test on Arty A7-100T

# Board Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.CONFIG.CCLKPIN PULLNONE [current_design]
set_property CONFIG_MODE SPIx1 [current_design] # Arty A7 uses SPI flash for configuration
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR NO [current_design] # Check based on flash size if needed
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design] # Arty default is x1, can be x4

## System Clock (100MHz)
# Matches: input wire clk100mhz_i
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk100mhz_i]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk100mhz_i]

## Buttons
# Matches: input wire reset_btn_i
# Matches: input wire start_btn_i
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports reset_btn_i]     ; # BTN1 on Arty board
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports start_btn_i]     ; # BTN0 on Arty board

## LEDs for status
# Matches: output logic status_led0_o, status_led1_o, status_led2_o, status_led3_o
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports status_led0_o]    ; # LED4 on schematic (LD0)
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports status_led1_o]    ; # LED5 on schematic (LD1)
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports status_led2_o]    ; # LED6 on schematic (LD2)
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports status_led3_o]   ; # LED7 on schematic (LD3)

## UART
# Matches: output logic uart_txd_o
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_txd_o]      ; # USB-UART TXD

## DDR3L SDRAM Interface
## Port names must match ddr3_decay_test_top.sv

# Address and Bank Address Lines
# Matches: output logic [13:0] ddr3_addr_o
# Matches: output logic [2:0]  ddr3_ba_o
set_property -dict {PACKAGE_PIN R2 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[0]}]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[1]}]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[2]}]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[3]}]
set_property -dict {PACKAGE_PIN N6 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[4]}]
set_property -dict {PACKAGE_PIN R7 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[5]}]
set_property -dict {PACKAGE_PIN V6 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[6]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[7]}]
set_property -dict {PACKAGE_PIN R8 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[8]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[9]}]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[10]}]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[11]}]
set_property -dict {PACKAGE_PIN T6 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[12]}]
set_property -dict {PACKAGE_PIN T8 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_addr_o[13]}]

set_property -dict {PACKAGE_PIN R1 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_ba_o[0]}]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_ba_o[1]}]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_ba_o[2]}]

# Control Signals
# Matches: ddr3_cas_n_o, ddr3_cke_o[0], ddr3_cs_n_o[0], ddr3_odt_o[0], ddr3_ras_n_o, ddr3_reset_n_o, ddr3_we_n_o
set_property -dict {PACKAGE_PIN M4 IOSTANDARD SSTL135 SLEW FAST} [get_ports ddr3_cas_n_o]
set_property -dict {PACKAGE_PIN N5 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_cke_o[0]}]  ; # Note [0] as port is [0:0]
set_property -dict {PACKAGE_PIN U8 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_cs_n_o[0]}] ; # Note [0]
set_property -dict {PACKAGE_PIN R5 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_odt_o[0]}]  ; # Note [0]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD SSTL135 SLEW FAST} [get_ports ddr3_ras_n_o]
set_property -dict {PACKAGE_PIN K6 IOSTANDARD SSTL135 SLEW FAST} [get_ports ddr3_reset_n_o]   ; # Physical DDR_Memory_RESET_N
set_property -dict {PACKAGE_PIN P5 IOSTANDARD SSTL135 SLEW FAST} [get_ports ddr3_we_n_o]

# DDR3 Clock
# Matches: ddr3_ck_p_o[0], ddr3_ck_n_o[0]
set_property -dict {PACKAGE_PIN U9 IOSTANDARD DIFF_SSTL135 SLEW FAST} [get_ports {ddr3_ck_p_o[0]}] ; # Note [0]
set_property -dict {PACKAGE_PIN V9 IOSTANDARD DIFF_SSTL135 SLEW FAST} [get_ports {ddr3_ck_n_o[0]}] ; # Note [0]
# It's good practice to create a clock constraint for the DDR3 clock output if Vivado doesn't infer it well,
# but often the tools handle generated clocks from an MMCM properly.
# create_clock -period 5.000 [get_ports {ddr3_ck_p_o[0]}] ; # Example for 200MHz memory clock (400MHz DDR)

# Data Mask (DM)
# Matches: ddr3_dm_o[1:0]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_dm_o[0]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD SSTL135 SLEW FAST} [get_ports {ddr3_dm_o[1]}]

# Data Strobe (DQS)
# Matches: ddr3_dqs_p_io[1:0], ddr3_dqs_n_io[1:0]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD DIFF_SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dqs_p_io[0]}]
set_property -dict {PACKAGE_PIN N1 IOSTANDARD DIFF_SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dqs_n_io[0]}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD DIFF_SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dqs_p_io[1]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD DIFF_SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dqs_n_io[1]}]
# set_property DRIVE 12 [get_ports {ddr3_dqs_p_io[*]}] ; # Optional: Explicit drive strength
# set_property DRIVE 12 [get_ports {ddr3_dqs_n_io[*]}] ; # Optional

# Data (DQ)
# Matches: ddr3_dq_io[15:0]
set_property -dict {PACKAGE_PIN K5 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[0]}]
set_property -dict {PACKAGE_PIN L3 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[1]}]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[2]}]
set_property -dict {PACKAGE_PIN L6 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[3]}]
set_property -dict {PACKAGE_PIN M3 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[4]}]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[5]}]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[6]}]
set_property -dict {PACKAGE_PIN M2 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[7]}]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[8]}]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[9]}]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[10]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[11]}]
set_property -dict {PACKAGE_PIN V1 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[12]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[13]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[14]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD SSTL135_T_DCI SLEW FAST} [get_ports {ddr3_dq_io[15]}]
# set_property DRIVE 12 [get_ports {ddr3_dq_io[*]}] ; # Optional: Explicit drive strength

# DCI (Digitally Controlled Impedance) Settings for Bank 34 (DDR3 Bank)
# This assumes the VRP pin for bank 34 is connected to 240 Ohms on the Arty board.
set_property DCI_CASCADE {32 34} [get_iobanks 34] ; # Check Arty A7 docs if bank 32 is also used/relevant for DCI cascading

# Internal VREF for Bank 34 (DDR3 Bank)
set_property INTERNAL_VREF 0.675 [get_iobanks 34]

# False paths for asynchronous button inputs if not synchronized before use (our top module does sync)
# set_false_path -from [get_ports start_btn_i]
# set_false_path -from [get_ports reset_btn_i]
