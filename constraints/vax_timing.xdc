# VAX-11/780 FPGA Timing Constraints
# Template for Xilinx Kintex-7 or UltraScale+

# Main system clock (100 MHz)
create_clock -period 10.000 -name sys_clk [get_ports clk]

# DDR4 clock (300 MHz)
create_clock -period 3.333 -name ddr_clk [get_ports ddr_clk]

# PCIe clock (250 MHz for Gen3)
create_clock -period 4.000 -name pcie_clk [get_ports pcie_clk]

# Clock domain crossings
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks ddr_clk] \
    -group [get_clocks pcie_clk]

# Input delays
set_input_delay -clock sys_clk -min 1.0 [get_ports rst]
set_input_delay -clock sys_clk -max 3.0 [get_ports rst]

# Output delays
set_output_delay -clock sys_clk -min 1.0 [get_ports led_*]
set_output_delay -clock sys_clk -max 3.0 [get_ports led_*]

# UART timing (if not using FPGA pin constraints)
set_output_delay -clock sys_clk 2.0 [get_ports uart_tx]
set_input_delay -clock sys_clk 2.0 [get_ports uart_rx]

# False paths for reset
set_false_path -from [get_ports rst]

# Multi-cycle paths (if needed for complex CPU operations)
# Uncomment and adjust as needed:
# set_multicycle_path -setup 2 -from [get_cells cpu_inst/*] -to [get_cells mmu_inst/*]
# set_multicycle_path -hold 1 -from [get_cells cpu_inst/*] -to [get_cells mmu_inst/*]
