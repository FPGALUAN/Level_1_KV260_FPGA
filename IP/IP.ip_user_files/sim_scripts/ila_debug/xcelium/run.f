-makelib xcelium_lib/xpm -sv \
  "/opt/xilinx/Vivado/2022.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "/opt/xilinx/Vivado/2022.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
-endlib
-makelib xcelium_lib/xpm \
  "/opt/xilinx/Vivado/2022.2/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  "../../../../IP.gen/sources_1/ip/ila_debug/sim/ila_debug.v" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  glbl.v
-endlib

