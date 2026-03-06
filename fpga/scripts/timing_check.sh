#!/bin/bash
# =============================================================================
# timing_check.sh — Fast synthesis-only timing check for Genesys2 FPGA
# =============================================================================
# Runs Chisel elaboration + Vivado synthesis (NO implementation or bitstream)
# and reports WNS, utilization, and estimated max clock frequency.
#
# This is ~2-5x faster than a full bitstream build since it skips
# placement, routing, and bitstream generation.
#
# Usage:
#   ./timing_check.sh                          # defaults: GemminiRocketGENESYS2Config @ 50MHz
#   ./timing_check.sh <CONFIG>                 # custom config, e.g. RocketGENESYS2Config
#   ./timing_check.sh <CONFIG> <FREQ_MHZ>     # custom config + freq override
#
# Examples:
#   ./timing_check.sh GemminiRocketGENESYS2Config
#   ./timing_check.sh GemminiRocketGENESYS2Config 75
#   ./timing_check.sh RocketGENESYS2Config 100
#
# The frequency override only affects the target constraint for THIS run.
# To change the actual SoC frequency, edit WithFPGAFrequency() in Configs.scala.
#
# Output:
#   - Post-synthesis timing summary (WNS)
#   - Post-synthesis utilization
#   - Estimated max achievable frequency
#   - All reports saved in generated-src/.../obj/report/
# =============================================================================

set -e

# ── Configuration ─────────────────────────────────────────────────────────────
chipyard_root="$HOME/Desktop/chipyard"
CONFIG="${1:-GemminiRocketGENESYS2Config}"
FREQ_OVERRIDE="${2:-}"    # optional: override target frequency for timing analysis

MODEL="GENESYS2FPGATestHarness"
CONFIG_PACKAGE="chipyard.fpga.genesys2"
MODEL_PACKAGE="chipyard.fpga.genesys2"
SUB_PROJECT="genesys2"
BOARD="genesys2"

generated_dir="$chipyard_root/fpga/generated-src/$MODEL_PACKAGE.$MODEL.$CONFIG"
report_dir="$generated_dir/obj/report"

# ── Environment setup ─────────────────────────────────────────────────────────
cd "$chipyard_root"
source env.sh

# Source Vivado (skip if already in PATH)
if ! command -v vivado &>/dev/null; then
    if [[ -f /tools/Xilinx/Vivado/2024.1/settings64.sh ]]; then
        source /tools/Xilinx/Vivado/2024.1/settings64.sh
    else
        echo "ERROR: Vivado not found in PATH. Source settings64.sh first."
        exit 1
    fi
fi

echo "==================================================================="
echo " TIMING CHECK (synthesis-only)"
echo "==================================================================="
echo " Config:     $CONFIG"
echo " Board:      $BOARD"
echo " Reports:    $report_dir"
if [[ -n "$FREQ_OVERRIDE" ]]; then
    echo " Freq override: ${FREQ_OVERRIDE} MHz (constraint only, not SoC)"
fi
echo "==================================================================="
echo ""

# ── Build sdboot (required for elaboration) ──────────────────────────────────
# Read the PBUS_CLK from the config frequency. Default to 50MHz if not overridden.
# The sdboot build just needs a reasonable value for UART baud calculation.
PBUS_CLK=${FREQ_OVERRIDE:-50}000000
echo "Building sdboot with PBUS_CLK=${PBUS_CLK}..."
make -C fpga/src/main/resources/genesys2/sdboot PBUS_CLK=$PBUS_CLK bin

# ── Run synthesis only ────────────────────────────────────────────────────────
START_TIME=$(date +%s)

cd "$chipyard_root/fpga"

echo ""
echo "Running Chisel elaboration + Vivado synthesis..."
echo "(This skips implementation and bitstream — much faster)"
echo ""

# Use the synth-only target which calls synth-report.tcl
make SUB_PROJECT=$SUB_PROJECT CONFIG=$CONFIG synth-only -j$(nproc)

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

echo ""
echo "==================================================================="
echo " SYNTHESIS COMPLETE (${ELAPSED_MIN}m ${ELAPSED_SEC}s)"
echo "==================================================================="
echo ""

# ── Extract and display results ───────────────────────────────────────────────
TIMING_RPT="$report_dir/post_synth_timing_summary.rpt"
UTIL_RPT="$report_dir/post_synth_utilization.rpt"

if [[ ! -f "$TIMING_RPT" ]]; then
    echo "WARNING: Timing report not found at $TIMING_RPT"
    echo "Check Vivado logs in $generated_dir for errors."
    exit 1
fi

echo "── TIMING SUMMARY ────────────────────────────────────────────────"
echo ""

# Extract WNS (Worst Negative Slack) from the timing summary
# Look for the "Design Timing Summary" table
WNS=$(grep -A 2 "Design Timing Summary" "$TIMING_RPT" | grep -oP '[-]?\d+\.\d+' | head -1 || true)

if [[ -z "$WNS" ]]; then
    # Alternative extraction: look for WNS directly
    WNS=$(grep -i "WNS" "$TIMING_RPT" | grep -oP '[-]?\d+\.\d+' | head -1 || true)
fi

# Extract the clock period from the timing report
PERIOD=$(grep -i "clk_out1_genesys2_sys_clock_mmcm\|sys_clk\|clock_period\|Requirement" "$TIMING_RPT" | grep -oP '\d+\.\d+' | head -1 || true)

if [[ -n "$WNS" ]]; then
    echo "  Worst Negative Slack (WNS): ${WNS} ns"
    
    if [[ -n "$PERIOD" ]]; then
        echo "  Clock Period (target):      ${PERIOD} ns"
        
        # Calculate estimated max frequency
        # Max period = target_period - WNS (if WNS positive, we have headroom)
        # Max freq = 1000 / (period - WNS)
        MAX_FREQ=$(echo "scale=1; 1000 / ($PERIOD - $WNS)" | bc 2>/dev/null || true)
        CURR_FREQ=$(echo "scale=1; 1000 / $PERIOD" | bc 2>/dev/null || true)
        
        echo "  Current target frequency:   ${CURR_FREQ} MHz"
        
        if [[ -n "$MAX_FREQ" ]]; then
            echo "  Estimated max frequency:    ${MAX_FREQ} MHz (post-synthesis estimate)"
            echo ""
            echo "  NOTE: Post-synthesis timing is optimistic. Real timing after"
            echo "  place+route is typically 10-20% worse. Safe target:"
            SAFE_FREQ=$(echo "scale=1; $MAX_FREQ * 0.85" | bc 2>/dev/null || true)
            echo "    Conservative estimate:    ~${SAFE_FREQ} MHz"
        fi
    fi
    
    # Check if timing is met
    IS_NEGATIVE=$(echo "$WNS < 0" | bc 2>/dev/null || true)
    echo ""
    if [[ "$IS_NEGATIVE" == "1" ]]; then
        echo "  *** TIMING NOT MET — WNS is negative ***"
        echo "  The design cannot run at the target frequency."
        echo "  Reduce WithFPGAFrequency() in Configs.scala and retry."
    else
        echo "  ✓ TIMING MET — design meets target frequency constraint"
    fi
else
    echo "  Could not extract WNS automatically."
    echo "  Check the full report manually:"
    echo "    $TIMING_RPT"
fi

echo ""
echo "── UTILIZATION SUMMARY ─────────────────────────────────────────"
echo ""

if [[ -f "$UTIL_RPT" ]]; then
    # Extract key utilization numbers (LUTs, FFs, BRAMs, DSPs)
    grep -E "CLB LUTs|CLB Registers|Block RAM|DSPs|Slice LUTs|Slice Registers" "$UTIL_RPT" | head -8 || true
else
    echo "  Utilization report not found."
fi

echo ""
echo "── REPORT FILES ───────────────────────────────────────────────"
echo ""
if [[ -d "$report_dir" ]]; then
    ls -la "$report_dir"/ 2>/dev/null || true
fi

echo ""
echo "── FULL TIMING REPORT (first 50 lines) ──────────────────────"
echo ""
head -50 "$TIMING_RPT" 2>/dev/null || true

echo ""
echo "==================================================================="
echo " WHAT TO DO NEXT"
echo "==================================================================="
echo ""
echo " If timing met with good slack:"
echo "   → Increase WithFPGAFrequency() and re-run this script"
echo ""
echo " If timing met with little slack:"
echo "   → Build full bitstream: ./generate_bitstream.sh"
echo ""
echo " If timing NOT met:"
echo "   → Decrease WithFPGAFrequency() in:"
echo "     fpga/src/main/scala/genesys2/Configs.scala"
echo "   → Or reduce Gemmini mesh/scratchpad size in:"
echo "     generators/gemmini/src/main/scala/gemmini/CustomConfigs.scala"
echo ""
echo " Full reports: $report_dir"
echo "==================================================================="
