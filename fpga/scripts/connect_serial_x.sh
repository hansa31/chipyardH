#!/bin/bash

# Serial connection script for FPGA (fixed version)
# Addresses baud rate mismatch when FPGA actual clock != declared clock
#
# The SiFive UART divisor is calculated as: floor(declared_freq / 115200)
# If the actual MMCM output differs from the declared frequency,
# the real baud rate will differ from 115200.
#
# Formula: actual_baud = actual_clock_hz / divisor

# Install dependencies if not present
if ! command -v picocom &> /dev/null; then
    echo "picocom could not be found, installing..."
    sudo apt update
    sudo apt install -y picocom
fi

echo "FPGA Serial Connection Script (fixed)"
echo "======================================"

# Auto-detect device: prefer ttyUSB1 (UART channel), fall back to ttyUSB0
if [ -e "/dev/ttyUSB1" ]; then
    DEVICE="/dev/ttyUSB1"
    echo "Found /dev/ttyUSB1 (UART channel)"
elif [ -e "/dev/ttyUSB0" ]; then
    DEVICE="/dev/ttyUSB0"
    echo "Using /dev/ttyUSB0"
else
    echo "Error: No ttyUSB devices found!"
    ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  None"
    exit 1
fi

# ---- Baud Rate Selection ----
# Your config: WithFPGAFrequency(35) -> divisor = floor(35000000/115200) = 303
# If actual clock != 35 MHz, the real baud = actual_clock / 303
#
# Common scenarios:
#   Actual 35.0 MHz -> baud 115512 (0.3% error, OK)
#   Actual 33.3 MHz -> baud 110010 (4.5% error, BAD)
#   Actual 50.0 MHz -> baud 165017 (43% error, VERY BAD)
#
DIVISOR=303
echo ""
echo "UART divisor from HW: $DIVISOR (based on declared 35MHz clock)"
echo ""
echo "Select baud rate:"
echo "  1) 115200  - standard (works if actual clock ≈ 35 MHz)"
echo "  2) Auto-calc from actual clock frequency (you enter the MHz)"
echo "  3) Enter custom baud rate"
read -p "Choice [1-3, default=1]: " baud_choice

case $baud_choice in
    2)
        read -p "Enter actual FPGA clock in MHz (e.g. 33.333): " actual_mhz
        # Calculate: actual_baud = actual_clock / divisor
        BAUDRATE=$(python3 -c "print(int(round(${actual_mhz} * 1e6 / ${DIVISOR})))")
        echo "Calculated baud rate: $BAUDRATE"
        echo "(actual_clock=${actual_mhz}MHz / divisor=${DIVISOR} = ${BAUDRATE})"
        ;;
    3)
        read -p "Enter baud rate: " BAUDRATE
        ;;
    *)
        BAUDRATE="115200"
        ;;
esac

echo ""

# Kill any existing processes using the device
sudo fuser -k $DEVICE 2>/dev/null || true
pkill -f "picocom.*ttyUSB" 2>/dev/null || true
sleep 1

# Check permissions
SUDO_PREFIX=""
if [ ! -r "$DEVICE" ] || [ ! -w "$DEVICE" ]; then
    echo "Using sudo (tip: sudo usermod -aG dialout $USER)"
    SUDO_PREFIX="sudo"
fi

# picocom flags:
#   --flow n       : disable hardware flow control
#   --imap lfcrlf  : map received LF to CR+LF
#   --omap crlf    : map outgoing CR to CR+LF
PICOCOM_OPTS="--flow n --imap lfcrlf --omap crlf"

echo "Connecting to $DEVICE at $BAUDRATE baud..."
echo "Options: $PICOCOM_OPTS"
echo "Exit: Ctrl+A, Ctrl+X"
echo ""

$SUDO_PREFIX picocom -b $BAUDRATE $PICOCOM_OPTS $DEVICE
