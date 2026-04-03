# program_bitstream_batch.tcl
#
# Programs a bitstream into the Genesys2 (xc7k325t) once via JTAG.
# The reset (reprogram) loop runs later in run_soc_benchmark.expect,
# after picocom is connected so the boot sequence is visible on UART.
#
# Called by batch_benchmark.sh:
#   vivado -mode batch -nolog -nojournal \
#          -source program_bitstream_batch.tcl \
#          -tclargs <path/to/bitstream.bit>

set bitfile [lindex $argv 0]

if {$bitfile eq ""} {
    puts "ERROR: No bitstream file provided."
    puts "Usage: vivado -mode batch -source program_bitstream_batch.tcl -tclargs <path.bit>"
    exit 1
}

if {![file exists $bitfile]} {
    puts "ERROR: Bitstream file not found: $bitfile"
    exit 1
}

puts "INFO: Bitstream : $bitfile"

# ── Open hardware manager and connect ─────────────────────────────────────
open_hw_manager

# Connect to hw_server — no flags lets Vivado auto-start one if not running,
# or attach to an existing instance. -url and -allow_non_jtag both cause
# problems: the former fails when no server is up, the latter can spawn a
# second conflicting server on some Vivado versions.
connect_hw_server

# List available targets for diagnostics before trying to open the specific one
set available_targets [get_hw_targets]
puts "INFO: Available targets: $available_targets"

set target_path "localhost:3121/xilinx_tcf/Digilent/200300BD5193B"
if {[lsearch $available_targets $target_path] < 0} {
    puts "ERROR: Target not found: $target_path"
    puts "       Available: $available_targets"
    puts "       Check the USB cable and board power."
    exit 1
}
open_hw_target $target_path

# Locate the xc7k325t device — use a wildcard so minor name variations (e.g.
# a different index suffix from Vivado) don't break the script.
set device [lindex [get_hw_devices *xc7k325t*] 0]
if {$device eq ""} {
    puts "ERROR: No xc7k325t device found in JTAG chain."
    puts "       Connected devices: [get_hw_devices]"
    puts "       Check the USB cable and make sure the board is powered on."
    exit 1
}
puts "INFO: Using device : $device"
current_hw_device $device

# ── Initial load ──────────────────────────────────────────────────────────
set_property PROGRAM.FILE $bitfile $device
puts "INFO: Programming bitstream..."
program_hw_devices $device
refresh_hw_device $device
puts "INFO: Bitstream loaded. Picocom will connect and trigger the reset."

# ── Clean disconnect ──────────────────────────────────────────────────────
close_hw_target
disconnect_hw_server
close_hw_manager
