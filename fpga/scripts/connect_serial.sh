#!/bin/bash

# Serial connection script for FPGA
# This script handles common serial communication issues

#install dependencies if not present
if ! command -v picocom &> /dev/null
then
    echo "picocom could not be found, installing..."
    sudo apt update
    sudo apt install -y picocom
fi

DEVICE="/dev/ttyUSB0"
BAUDRATE="115200"

echo "FPGA Serial Connection Script"
echo "============================="

# Check if device exists
if [ ! -e "$DEVICE" ]; then
    echo "Error: $DEVICE not found!"
    echo "Available tty devices:"
    ls -la /dev/ttyUSB* 2>/dev/null || echo "No ttyUSB devices found"
    exit 1
fi

# Kill any existing processes using the device
echo "Killing any existing processes using $DEVICE..."
sudo fuser -k $DEVICE 2>/dev/null || true
pkill -f "screen.*ttyUSB" 2>/dev/null || true
pkill -f "picocom.*ttyUSB" 2>/dev/null || true

# Wait a moment
sleep 1

# Reset the device
echo "Resetting serial device..."
stty -F $DEVICE $BAUDRATE raw -echo 2>/dev/null || true

# Check if user has permission to access the device; use sudo if not
SUDO_PREFIX=""
if [ ! -r "$DEVICE" ] || [ ! -w "$DEVICE" ]; then
    echo "Warning: No read/write access to $DEVICE."
    echo "Tip: To avoid needing sudo, add yourself to the dialout group:"
    echo "  sudo usermod -aG dialout $USER"
    echo "  (then log out and back in)"
    echo ""
    echo "Using sudo for this session..."
    SUDO_PREFIX="sudo"
fi

echo "Connecting to $DEVICE at $BAUDRATE baud..."
echo "Choose connection method:"
echo "1) picocom (recommended)"
echo "2) screen"
echo "3) minicom"
read -p "Enter choice (1-3): " choice
read -p "Enable logging to file? (y/N): " logchoice
LOG_ENABLED=0
LOGFILE=""
if [[ "$logchoice" =~ ^[Yy]$ ]]; then
    LOG_ENABLED=1
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    LOGFILE="$(pwd)/serial-${TIMESTAMP}.log"
    echo "Logging enabled -> $LOGFILE"
fi

case $choice in
    1)
        echo "Starting picocom... (Ctrl+A, Ctrl+X to exit)"
        if [ $LOG_ENABLED -eq 1 ]; then
            echo "Starting picocom wrapped with script to log to $LOGFILE"
            script -q -c "$SUDO_PREFIX picocom -b $BAUDRATE $DEVICE" "$LOGFILE"
        else
            $SUDO_PREFIX picocom -b $BAUDRATE $DEVICE
        fi
        ;;
    2)
        echo "Starting screen... (Ctrl+A, K to exit)"
        if [ $LOG_ENABLED -eq 1 ]; then
            # screen's logfile naming varies; wrap screen with 'script' to capture its session to our logfile
            echo "Starting screen with session logging to $LOGFILE (wrapped with script)"
            # -q: quiet, -c: command to run, then logfile path
            script -q -c "$SUDO_PREFIX screen $DEVICE $BAUDRATE" "$LOGFILE"
        else
            $SUDO_PREFIX screen $DEVICE $BAUDRATE
        fi
        ;;
    3)
        echo "Starting minicom..."
        if command -v minicom &> /dev/null; then
            if [ $LOG_ENABLED -eq 1 ]; then
                echo "Starting minicom with capture to $LOGFILE"
                $SUDO_PREFIX minicom -D $DEVICE -b $BAUDRATE -C "$LOGFILE"
            else
                $SUDO_PREFIX minicom -D $DEVICE -b $BAUDRATE
            fi
        else
            echo "minicom not installed. Install with: sudo apt install minicom"
        fi
        ;;
    *)
        echo "Invalid choice. Using picocom..."
        if [ $LOG_ENABLED -eq 1 ]; then
            echo "Starting picocom wrapped with script to log to $LOGFILE"
            script -q -c "$SUDO_PREFIX picocom -b $BAUDRATE $DEVICE" "$LOGFILE"
        else
            $SUDO_PREFIX picocom -b $BAUDRATE $DEVICE
        fi
        ;;
esac