#!/bin/bash -f
# ****************************************************************************
# Vivado (TM) v2022.2.2 (64-bit)
#
# Filename    : compile.sh
# Simulator   : Xilinx Vivado Simulator
# Description : Script for compiling the simulation design source files
#
# Generated by Vivado on Tue May 06 14:58:22 JST 2025
# SW Build 3788238 on Tue Feb 21 19:59:23 MST 2023
#
# IP Build 3783773 on Tue Feb 21 23:41:56 MST 2023
#
# usage: compile.sh
#
# ****************************************************************************
set -Eeuo pipefail
# compile Verilog/System Verilog design sources
echo "xvlog --incr --relax -prj Matrix_Vector_Multiplication_tb_vlog.prj"
xvlog --incr --relax -prj Matrix_Vector_Multiplication_tb_vlog.prj 2>&1 | tee compile.log

echo "Waiting for jobs to finish..."
echo "No pending jobs, compilation finished."
