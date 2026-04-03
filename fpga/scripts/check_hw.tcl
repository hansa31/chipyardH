# check_hw.tcl
#
# Quick diagnostic — run this before the batch to verify Vivado can see
# the Genesys2 and that all hw path strings are correct.
#
# Usage:
#   vivado -mode batch -nolog -nojournal -source fpga/scripts/check_hw.tcl

open_hw_manager
connect_hw_server

puts ""
puts "── hw_targets ────────────────────────────────────"
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: No targets found — check USB cable and board power."
    close_hw_manager
    exit 1
}
foreach t $targets { puts "  $t" }

puts ""
puts "── Opening target ────────────────────────────────"
set target [lindex $targets 0]
puts "  Using: $target"
open_hw_target $target

puts ""
puts "── hw_devices ────────────────────────────────────"
set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "ERROR: No devices found in JTAG chain."
    close_hw_target
    close_hw_manager
    exit 1
}
foreach d $devices { puts "  $d" }

puts ""
puts "── Device properties ─────────────────────────────"
set device [lindex $devices 0]
current_hw_device $device
puts "  NAME        : [get_property NAME        $device]"
puts "  PART        : [get_property PART        $device]"
puts "  JTAG_STATUS : [get_property JTAG_STATUS $device]"

puts ""
puts "All checks passed."
puts "Copy the target path above into program_bitstream_batch.tcl if it differs."

close_hw_target
disconnect_hw_server
close_hw_manager
