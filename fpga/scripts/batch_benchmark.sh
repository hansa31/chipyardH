#!/bin/bash
#
# batch_benchmark.sh
#
# For every bitstream in the batch directory:
#   1. Programs the FPGA and resets 5 times (Vivado TCL)
#   2. Waits for BusyBox Linux to boot over UART
#   3. Runs /Test/run_mlp_benchmarks.sh on the SoC
#   4. Saves mlp_bench_results.csv to /Test/<bitstream_name>_<timestamp>/ on the SD card
#
# Usage:
#   bash fpga/scripts/batch_benchmark.sh
#
# From the chipyard root, or run it directly — paths are resolved from the
# script's own location regardless of working directory.

set -euo pipefail

# ── Prevent host sleep / suspend for the entire batch run ─────────────────
# If the machine suspends mid-run, USB drops (JTAG + UART both lost) and the
# script fails. systemd-inhibit holds a lock that blocks sleep, suspend, and
# lid-close for as long as this script is running — same mechanism as VLC.
# The INHIBIT_ACTIVE guard stops infinite re-exec.
if [[ -z "${INHIBIT_ACTIVE:-}" ]]; then
    if command -v systemd-inhibit &>/dev/null; then
        echo "Holding sleep/suspend lock via systemd-inhibit..."
        exec env INHIBIT_ACTIVE=1 systemd-inhibit \
            --what=sleep:idle:handle-lid-switch \
            --who="batch_benchmark.sh" \
            --why="FPGA batch benchmark in progress" \
            "$0" "$@"
    else
        echo "WARNING: systemd-inhibit not found — machine may sleep mid-run."
        echo "         Consider running: sudo apt-get install systemd"
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHIPYARD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BATCH_DIR="$CHIPYARD_ROOT/fpga/approx_batch_20260315_013001"
VIVADO_SETTINGS="/tools/Xilinx/Vivado/2024.1/settings64.sh"
TCL_SCRIPT="$SCRIPT_DIR/program_bitstream_batch.tcl"
EXPECT_SCRIPT="$SCRIPT_DIR/run_soc_benchmark.expect"

# ── Dependency checks ─────────────────────────────────────────────────────
if ! command -v expect &>/dev/null; then
    echo "expect not found — installing..."
    sudo apt-get update -q && sudo apt-get install -y expect
fi

if ! command -v picocom &>/dev/null; then
    echo "picocom not found — installing..."
    sudo apt-get update -q && sudo apt-get install -y picocom
fi

# ── Cache sudo credentials for the whole batch run ────────────────────────
# Ask for the password once here. A background keepalive refreshes the
# credential every 4 minutes so no subsequent command ever prompts again
# (picocom, fuser, stty, pkill inside the expect script all use sudo).
# Vivado itself is intentionally NOT run with sudo — it needs ~/.Xilinx for
# license resolution and breaks under root.
echo "Sudo credentials are needed for serial port access (picocom, fuser, stty)."
sudo -v
( while true; do sleep 240; sudo -n -v 2>/dev/null || true; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# ── Source Vivado environment ─────────────────────────────────────────────
if [[ ! -f "$VIVADO_SETTINGS" ]]; then
    echo "ERROR: Vivado settings not found: $VIVADO_SETTINGS"
    exit 1
fi
# shellcheck source=/dev/null
source "$VIVADO_SETTINGS"

# ── JTAG / Vivado cable driver permissions ────────────────────────────────
# Vivado must NOT be run with sudo (breaks license paths and ~/.Xilinx config).
# Instead, Xilinx provides an install_drivers script that installs udev rules
# so the current user can access JTAG devices without elevated privileges.
VIVADO_ROOT="$(dirname "$(dirname "$VIVADO_SETTINGS")")"
INSTALL_DRIVERS="$VIVADO_ROOT/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers"
UDEV_RULE="/etc/udev/rules.d/52-xilinx-digilent-usb.rules"

if [[ ! -f "$UDEV_RULE" ]]; then
    echo "WARNING: Xilinx JTAG udev rules not found."
    if [[ -x "$INSTALL_DRIVERS" ]]; then
        echo "Installing Xilinx cable drivers (requires sudo)..."
        sudo "$INSTALL_DRIVERS"
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        echo "Cable drivers installed. Replug the FPGA USB cable if it is already connected."
    else
        echo "ERROR: Could not find Xilinx install_drivers script at:"
        echo "  $INSTALL_DRIVERS"
        echo "Run it manually, or add yourself to the 'dialout' group and replug the cable."
        echo "  sudo usermod -aG dialout \$USER  (then log out and back in)"
        exit 1
    fi
fi

if ! groups | grep -qw dialout; then
    echo "WARNING: User '$USER' is not in the 'dialout' group."
    echo "  This may cause JTAG or serial access issues."
    echo "  Fix: sudo usermod -aG dialout \$USER  (then log out and back in)"
fi

# ── Sanity checks ─────────────────────────────────────────────────────────
if [[ ! -d "$BATCH_DIR" ]]; then
    echo "ERROR: Batch directory not found: $BATCH_DIR"
    exit 1
fi

if [[ ! -f "$TCL_SCRIPT" ]]; then
    echo "ERROR: TCL script not found: $TCL_SCRIPT"
    exit 1
fi

if [[ ! -f "$EXPECT_SCRIPT" ]]; then
    echo "ERROR: expect script not found: $EXPECT_SCRIPT"
    exit 1
fi

mapfile -t BITSTREAMS < <(ls "$BATCH_DIR"/*.bit 2>/dev/null | sort)
TOTAL=${#BITSTREAMS[@]}

if [[ $TOTAL -eq 0 ]]; then
    echo "ERROR: No .bit files found in $BATCH_DIR"
    exit 1
fi

echo "=========================================="
echo "  Batch Benchmark Runner"
echo "  Batch dir : $BATCH_DIR"
echo "  Bitstreams: $TOTAL"
echo "=========================================="

# ── Main loop ─────────────────────────────────────────────────────────────
n=0
FAILED=()

for bitfile in "${BITSTREAMS[@]}"; do
    n=$((n + 1))
    bitname="$(basename "$bitfile" .bit)"

    echo ""
    echo "------------------------------------------"
    echo "  [$n/$TOTAL] $bitname"
    echo "------------------------------------------"

    # Step 1: Program FPGA + 5 resets
    echo "[1/2] Programming FPGA + 5 resets..."
    if ! vivado -mode batch -nolog -nojournal \
                -source "$TCL_SCRIPT" \
                -tclargs "$bitfile"; then
        echo "ERROR: Vivado failed for $bitname — skipping."
        FAILED+=("$bitname")
        continue
    fi

    # Step 2: UART automation — wait for Linux, run benchmarks, save CSV
    echo "[2/2] Waiting for Linux boot + running benchmarks..."
    if ! expect "$EXPECT_SCRIPT" "$bitname" "$bitfile"; then
        echo "ERROR: Benchmark step failed for $bitname — skipping."
        FAILED+=("$bitname")
        continue
    fi

    echo "  OK: $bitname"
done

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Batch complete: $((TOTAL - ${#FAILED[@]}))/$TOTAL succeeded."
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  Failed:"
    for f in "${FAILED[@]}"; do
        echo "    - $f"
    done
fi
echo "=========================================="
