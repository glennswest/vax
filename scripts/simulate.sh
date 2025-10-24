#!/bin/bash
# GHDL simulation script for VAX CPU

set -e

SIM_DIR="./sim_build"
RTL_DIR="../rtl"
TB_DIR="../sim/tb"

echo "VAX-11/780 VHDL Simulation"
echo "=========================="

# Create simulation directory
mkdir -p $SIM_DIR
cd $SIM_DIR

# Compile source files in order
echo "Compiling VHDL sources..."

# Package first
ghdl -a --std=08 $RTL_DIR/vax_pkg.vhd

# CPU components
ghdl -a --std=08 $RTL_DIR/cpu/vax_alu.vhd
ghdl -a --std=08 $RTL_DIR/cpu/vax_cpu.vhd

# MMU
ghdl -a --std=08 $RTL_DIR/mmu/vax_mmu.vhd

# Memory
ghdl -a --std=08 $RTL_DIR/memory/memory_controller.vhd

# I/O
ghdl -a --std=08 $RTL_DIR/io/tty_uart.vhd
ghdl -a --std=08 $RTL_DIR/io/pcie_interface.vhd

# Bus
ghdl -a --std=08 $RTL_DIR/bus/massbus_controller.vhd
ghdl -a --std=08 $RTL_DIR/bus/unibus_controller.vhd

# Top level
ghdl -a --std=08 $RTL_DIR/vax_top.vhd

# Testbench
ghdl -a --std=08 $TB_DIR/tb_vax_cpu.vhd

echo "Elaborating testbench..."
ghdl -e --std=08 tb_vax_cpu

echo "Running simulation..."
ghdl -r --std=08 tb_vax_cpu --wave=vax_cpu.ghw --stop-time=1us

echo ""
echo "Simulation complete. Waveform saved to: $SIM_DIR/vax_cpu.ghw"
echo "View with: gtkwave vax_cpu.ghw"
