vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib -64 -incr -mfcu  \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/arty_a7/artix7_pll.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/src_v/ddr3_axi.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/src_v/ddr3_axi_pmem.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/src_v/ddr3_axi_retime.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/src_v/ddr3_core.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/src_v/phy/xc7/ddr3_dfi_phy.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/src_v/ddr3_dfi_seq.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/arty_a7/reset_gen.v" \
"../../../ULTRA_EMBEDDED_SIMPLE.srcs/sources_1/imports/arty_a7/topv1.v" \


vlog -work xil_defaultlib \
"glbl.v"

