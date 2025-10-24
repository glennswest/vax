# Vivado Build Script for VAX-11/780 FPGA Implementation
# This script sets up the Vivado project and runs synthesis

# Set project name and directory
set project_name "vax_fpga"
set project_dir "./build"
set rtl_dir "../rtl"

# Create project
create_project $project_name $project_dir -part xc7k325tffg900-2 -force

# Set project properties
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

# Add source files
add_files [glob $rtl_dir/*.vhd]
add_files [glob $rtl_dir/cpu/*.vhd]
add_files [glob $rtl_dir/mmu/*.vhd]
add_files [glob $rtl_dir/memory/*.vhd]
add_files [glob $rtl_dir/bus/*.vhd]
add_files [glob $rtl_dir/io/*.vhd]

# Set top module
set_property top vax_top [current_fileset]

# Add constraint files if they exist
set constraint_files [glob -nocomplain ../constraints/*.xdc]
if {[llength $constraint_files] > 0} {
    add_files -fileset constrs_1 $constraint_files
}

puts "Project setup complete. Ready for synthesis."
puts ""
puts "To run synthesis:"
puts "  launch_runs synth_1"
puts ""
puts "To add Xilinx IP cores:"
puts "  - MIG (Memory Interface Generator) for DDR4/DDR5"
puts "  - PCIe IP core"
puts ""
puts "Use Vivado IP Catalog to configure these cores."
