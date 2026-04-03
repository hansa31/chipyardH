#!/bin/bash
#
# batch_resnet50_only.sh
#
# Runs ONLY resnet50_v1-linux (ImageNet, 25 batches) on every design bitstream.
# Based on batch_inference_v2.sh — same boot/reset/sudo/logging infrastructure,
# but the expect script only executes the single resnet50 test per design.
#
# All terminal output is tee'd to a timestamped log file on this host in real-time.
#
# Usage:
#   bash fpga/scripts/batch_resnet50_only.sh   (will prompt for sudo password once)

set -euo pipefail

# ── Prevent host sleep / suspend ──────────────────────────────────────────
if [[ -z "${INHIBIT_ACTIVE:-}" ]]; then
    if command -v systemd-inhibit &>/dev/null; then
        echo "Holding sleep/suspend lock via systemd-inhibit..."
        exec env INHIBIT_ACTIVE=1 systemd-inhibit \
            --what=sleep:idle:handle-lid-switch \
            --who="batch_resnet50_only.sh" \
            --why="FPGA resnet50-only benchmark in progress" \
            "$0" "$@"
    else
        echo "WARNING: systemd-inhibit not found — machine may sleep mid-run."
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHIPYARD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Real-time log file on this host (tee to terminal + file simultaneously) ─
LOGFILE="$SCRIPT_DIR/resnet50_only_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Logging to: $LOGFILE"

BATCH_DIR="$CHIPYARD_ROOT/fpga/approx_batch_20260315_013001"
VIVADO_SETTINGS="/tools/Xilinx/Vivado/2024.1/settings64.sh"
EXPECT_SCRIPT="$SCRIPT_DIR/run_soc_resnet50_only.expect"

# ── Cache sudo credentials once — user types password here and nowhere else ─
echo "Sudo password required once to grant serial-port and JTAG access:"
sudo -v
( while true; do sleep 240; sudo -n true 2>/dev/null || true; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; exit' INT TERM EXIT

# ── Dependency checks ─────────────────────────────────────────────────────
for dep in expect picocom; do
    if ! command -v "$dep" &>/dev/null; then
        echo "$dep not found — installing..."
        sudo apt-get update -q && sudo apt-get install -y "$dep"
    fi
done

# ── Source Vivado environment ─────────────────────────────────────────────
if [[ ! -f "$VIVADO_SETTINGS" ]]; then
    echo "ERROR: Vivado settings not found: $VIVADO_SETTINGS"
    exit 1
fi
# shellcheck source=/dev/null
source "$VIVADO_SETTINGS"

# ── JTAG / Vivado cable driver permissions ────────────────────────────────
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
        echo "Cable drivers installed. Replug the FPGA USB cable if already connected."
    else
        echo "ERROR: Could not find Xilinx install_drivers script at:"
        echo "  $INSTALL_DRIVERS"
        echo "Add yourself to 'dialout' and replug the cable, then retry."
        exit 1
    fi
fi

# ── Sanity checks ─────────────────────────────────────────────────────────
if [[ ! -d "$BATCH_DIR" ]]; then
    echo "ERROR: Batch directory not found: $BATCH_DIR"
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
echo "  ResNet50-Only Benchmark Runner"
echo "  Batch dir : $BATCH_DIR"
echo "  Bitstreams: $TOTAL"
echo "  Log file  : $LOGFILE"
echo "  Test      : resnet50_v1-linux (ImageNet, 25 batches)"
echo "  Stop at   : [Images 1-100] window line"
echo "=========================================="

# ── Main loop ─────────────────────────────────────────────────────────────
n=0
FAILED=()

for bitfile in "${BITSTREAMS[@]}"; do
    n=$((n + 1))
    bitname="$(basename "$bitfile" .bit)"
    host_ts="$(date +%Y%m%d_%H%M%S)"

    echo ""
    echo "------------------------------------------"
    echo "  [$n/$TOTAL] $bitname  (host ts: $host_ts)"
    echo "------------------------------------------"

    if ! expect "$EXPECT_SCRIPT" "$bitname" "$bitfile" "$host_ts"; then
        echo "ERROR: resnet50_v1 failed for $bitname — skipping."
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
echo "  Full log: $LOGFILE"
echo "=========================================="
