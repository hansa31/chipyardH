# reset_fpga.tcl
#
# Reprograms the FPGA — used as a software reset after picocom is already
# connected to the UART, so the Linux boot sequence is visible on the terminal.
# Called by run_soc_benchmark.expect up to 5 times until Linux boots.
#
# Usage:
#   vivado -mode batch -nolog -nojournal -source reset_fpga.tcl -tclargs <path.bit>

set bitfile [lindex $argv 0]

if {$bitfile eq ""} {
    puts "ERROR: No bitstream file provided."
    exit 1
}
if {![file exists $bitfile]} {
    puts "ERROR: Bitstream file not found: $bitfile"
    exit 1
}

open_hw_manager
connect_hw_server

set available_targets [get_hw_targets]
set target_path "localhost:3121/xilinx_tcf/Digilent/200300BD5193B"
if {[lsearch $available_targets $target_path] < 0} {
    puts "ERROR: Target not found: $target_path"
    puts "       Available: $available_targets"
    exit 1
}
open_hw_target $target_path

set device [lindex [get_hw_devices *xc7k325t*] 0]
if {$device eq ""} {
    puts "ERROR: No xc7k325t device found."
    exit 1
}
current_hw_device $device

set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device

close_hw_target
disconnect_hw_server
close_hw_manager
