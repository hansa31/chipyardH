#!/bin/bash
#
# batch_inference_v2.sh
#
# Revised batch inference runner — incorporates all fixes from BATCH_INFERENCE_NOTES.md:
#
#   Fix 1: No 3-hour global timeout. Each test waits for its specific output pattern.
#   Fix 2: SoC wall clock is set via 'date -s' before benchmarks run (no epoch timestamps).
#   Fix 3: sudo password entered once at start; credentials cached for entire batch.
#   Fix 4: Step 1 Vivado programming removed — the expect script's reset loop handles it.
#
# What runs and how long:
#   SKIPPED : resnet50_cifar10_stream, mobilenet_cifar10_stream  (already collected)
#   resnet50_v1     — stopped after [Images 1-100] window line (appears after batch 25)
#   mobilenet_v1    — stopped after [Images 1-100] window line (appears after batch 25)
#   bert-tiny-sst2  — all 100 examples; captures full result if done under 15 min,
#                     otherwise last printed accuracy line is taken (15-min cap)
#
# All terminal output is tee'd to a timestamped log file on this host in real-time.
#
# Usage:
#   bash fpga/scripts/batch_inference_v2.sh   (will prompt for sudo password once)

set -euo pipefail

# ── Prevent host sleep / suspend ──────────────────────────────────────────
if [[ -z "${INHIBIT_ACTIVE:-}" ]]; then
    if command -v systemd-inhibit &>/dev/null; then
        echo "Holding sleep/suspend lock via systemd-inhibit..."
        exec env INHIBIT_ACTIVE=1 systemd-inhibit \
            --what=sleep:idle:handle-lid-switch \
            --who="batch_inference_v2.sh" \
            --why="FPGA batch inference benchmark in progress" \
            "$0" "$@"
    else
        echo "WARNING: systemd-inhibit not found — machine may sleep mid-run."
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHIPYARD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Real-time log file on this host (tee to terminal + file simultaneously) ─
LOGFILE="$SCRIPT_DIR/batch_v2_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Logging to: $LOGFILE"

BATCH_DIR="$CHIPYARD_ROOT/fpga/approx_batch_20260315_013001"
VIVADO_SETTINGS="/tools/Xilinx/Vivado/2024.1/settings64.sh"
EXPECT_SCRIPT="$SCRIPT_DIR/run_soc_inference_v2.expect"

# ── Cache sudo credentials once — user types password here and nowhere else ─
# The expect script uses 'sudo -n' (non-interactive) throughout, relying on
# this cache. The keepalive refreshes it every 4 min for the whole batch.
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
echo "  Batch Inference Benchmark Runner v2"
echo "  Batch dir : $BATCH_DIR"
echo "  Bitstreams: $TOTAL"
echo "  Log file  : $LOGFILE"
echo "  Skipping  : resnet50_cifar10, mobilenet_cifar10 (already collected)"
echo "  ImageNet  : resnet50_v1, mobilenet_v1  -> stop at [Images 1-100] (after batch 25)"
echo "  Transformer: bert-tiny-sst2            -> all 100 examples (15 min cap)"
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

    # Fix 4: No Step 1 Vivado call. The expect script programs and resets the FPGA.
    # Pass the host timestamp so the expect script can set the SoC wall clock (Fix 2).
    if ! expect "$EXPECT_SCRIPT" "$bitname" "$bitfile" "$host_ts"; then
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
echo "  Full log: $LOGFILE"
echo "=========================================="
