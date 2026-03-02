#!/bin/bash
# Opens the post-route checkpoint in the Vivado GUI so you can inspect
# timing, utilization, schematic/block diagrams, device view, etc.
#
# The Chipyard FPGA flow runs in non-project (TCL) mode, so the .xpr file
# has no run results.  This script loads the post-route .dcp checkpoint
# directly and generates all reports inside the GUI.

set -e

chipyard_root="$HOME/Desktop/chipyard"
CONFIG="RocketGENESYS2Config"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# source vivado settings
source /tools/Xilinx/Vivado/2024.1/settings64.sh

DCP="$chipyard_root/fpga/generated-src/chipyard.fpga.genesys2.GENESYS2FPGATestHarness.$CONFIG/obj/post_route.dcp"

if [ ! -f "$DCP" ]; then
    echo "ERROR: Checkpoint not found: $DCP"
    echo "       Have you built the bitstream for $CONFIG yet?"
    exit 1
fi

echo "Opening post-route checkpoint in Vivado GUI..."
echo "  DCP:  $DCP"
echo "  TCL:  $SCRIPT_DIR/open_checkpoint.tcl"
echo ""
echo "Vivado will load the checkpoint and generate reports automatically."
echo "Once open you have full access to: Schematic, Device view, Timing, Utilization, DRC, Power."
echo ""

vivado -mode gui -source "$SCRIPT_DIR/open_checkpoint.tcl" &
