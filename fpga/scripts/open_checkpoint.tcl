# open_checkpoint.tcl
# Loads the post-route checkpoint into Vivado and generates all reports
# so you get the full GUI experience (schematic, device view, timing, etc.)

set chipyard_root $::env(HOME)/Desktop/chipyard
set config "RocketGENESYS2Config"
set gen_dir "$chipyard_root/fpga/generated-src/chipyard.fpga.genesys2.GENESYS2FPGATestHarness.$config"
set dcp "$gen_dir/obj/post_route.dcp"

# Open the fully-routed checkpoint — this is equivalent to "Open Implemented Design"
open_checkpoint $dcp

# Generate reports so they appear in the GUI's Reports tab
report_timing_summary -delay_type min_max -max_paths 10 -name timing_summary_1
report_utilization -name utilization_1
report_clock_utilization -name clock_utilization_1
report_drc -name drc_1
report_power -name power_1

puts "=============================================="
puts "Checkpoint loaded successfully."
puts "You now have access to:"
puts "  - Schematic:     Window -> Schematic"
puts "  - Device view:   Window -> Device"
puts "  - Timing:        see 'timing_summary_1' in the Reports tab"
puts "  - Utilization:   see 'utilization_1' in the Reports tab"
puts "  - DRC:           see 'drc_1' in the Reports tab"
puts "  - Power:         see 'power_1' in the Reports tab"
puts "=============================================="
