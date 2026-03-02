# program_fpga.tcl
# Opens Vivado Hardware Manager GUI for interactive FPGA programming.
# Automatically connects to the board and lets you select bitstream & memory part.

# Open Hardware Manager
open_hw_manager

# Try to connect to a local hw_server (start one if not already running)
connect_hw_server -allow_non_jtag

# Auto-detect the FPGA target
open_hw_target

puts ""
puts "=============================================="
puts "Hardware Manager is connected."
puts ""
puts "Your bitstreams are in:"
puts "  $::env(HOME)/Desktop/chipyard/fpga/bitstream_copy/"
puts ""
puts "To program the FPGA (volatile / SRAM):"
puts "  1. Right-click the device (xc7k325t) -> Program Device"
puts "  2. Browse to the .bit file"
puts "  3. Click Program"
puts ""
puts "To program SPI Flash (non-volatile / persistent):"
puts "  1. Right-click the device (xc7k325t) -> Add Configuration Memory Device"
puts "  2. Select the flash part: s25fl256sxxxxxx0-spi-x1_x2_x4"
puts "     (Spansion S25FL256S — the flash on Genesys2)"
puts "  3. When prompted, provide the .bin or .mcs file"
puts "     (You'll need to generate it first — see instructions below)"
puts "  4. Click Program"
puts ""
puts "To generate .mcs for SPI Flash (run in Vivado TCL console):"
puts "  write_cfgmem -format mcs -interface spix4 -size 32 \\"
puts "    -loadbit \"up 0x0 /path/to/your.bit\" \\"
puts "    -file /path/to/output.mcs -force"
puts "=============================================="
