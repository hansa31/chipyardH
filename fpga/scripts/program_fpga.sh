#!/bin/bash
# Opens Vivado Hardware Manager GUI to program the Genesys2 FPGA board.
# Connects to the board automatically and lets you select the bitstream
# and memory part interactively.

set -e

chipyard_root="$HOME/Desktop/chipyard"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BITSTREAM_DIR="$chipyard_root/fpga/bitstream_copy"

# source vivado settings
source /tools/Xilinx/Vivado/2024.1/settings64.sh

echo "==========================================="
echo "Available bitstreams:"
echo "==========================================="
ls -1 "$BITSTREAM_DIR"/*.bit 2>/dev/null | while read f; do
    echo "  $(basename "$f")"
done
echo ""
echo "Opening Vivado Hardware Manager..."
echo "The GUI will connect to the board automatically."
echo "==========================================="
echo ""

vivado -mode gui -source "$SCRIPT_DIR/program_fpga.tcl" &
