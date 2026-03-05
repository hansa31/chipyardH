# Genesys2 FPGA Bitstream — Quick-Start Guide

> Build a RISC-V SoC bitstream for the **Digilent Genesys2** (Xilinx Kintex-7) board using Chipyard.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Chipyard** | Fully initialised (`build-setup.sh` completed, submodules fetched) |
| **Conda environment** | `source env.sh` in the Chipyard root |
| **Vivado 2024.1** (or compatible) | Installed at `/tools/Xilinx/Vivado/2024.1` (adjust path if different) |
| **picocom** | For serial console (`sudo apt install picocom`) |
| **dtc** *(optional)* | Device-tree compiler, to convert DTS → DTB |

---

## Available Configs

Defined in `fpga/src/main/scala/genesys2/Configs.scala`:

| Config class | Description | Clock (MHz) |
|---|---|---|
| `RocketGENESYS2Config` | Single Rocket core | 80 |
| `BoomGENESYS2Config` | BOOM (out-of-order) core | 50 |
| `SmallNVDLARocketGENESYS2Config` | Rocket + small NVDLA accelerator | 100 |
| `LargeNVDLARocketGENESYS2Config` | Rocket + large NVDLA accelerator | 100 |
| `FFTRocketGENESYS2Config` | Rocket + FFT generator | 100 |
| `TESTSDGENESYS2Config` | Debug / SD-card testing | 50 |

> **Tip:** To change the system clock, prepend `new WithFPGAFrequency(<MHz>)` in your config chain.

---

## Step-by-Step: Generate a Bitstream

All commands assume you start from the **Chipyard root** directory.

### 1. Activate the environment

```bash
cd ~/Desktop/chipyard
source env.sh
source /tools/Xilinx/Vivado/2024.1/settings64.sh
```

### 2. Build the zero-stage bootloader (sdboot)

The bootloader is the first code the CPU executes after reset. It initialises clocks, UART, and then loads the next stage from the SD card.

```bash
cd fpga/src/main/resources/genesys2/sdboot
make clean
make PBUS_CLK=80000000      # match your config's peripheral-bus freq (Hz)
```

> For configs running at 100 MHz, use `PBUS_CLK=100000000`. For 50 MHz, use `PBUS_CLK=50000000`.

### 3. Build the bitstream

```bash
cd ~/Desktop/chipyard/fpga
make clean
make CONFIG=RocketGENESYS2Config bitstream -j$(nproc)
```

Replace `RocketGENESYS2Config` with any config from the table above.

Vivado synthesis + implementation will run in batch mode. This takes **30 min – 2+ hours** depending on the design and machine.

The output bitstream lands in:

```
fpga/generated-src/chipyard.fpga.genesys2.GENESYS2FPGATestHarness.<CONFIG>/obj/*.bit
```

### 4. Copy the outputs

```bash
CONFIG=RocketGENESYS2Config
GEN_DIR=fpga/generated-src/chipyard.fpga.genesys2.GENESYS2FPGATestHarness.$CONFIG

mkdir -p fpga/bitstream_copy fpga/dts_copy
cp $GEN_DIR/obj/*.bit        fpga/bitstream_copy/$CONFIG.bit
cp $GEN_DIR/*.dts            fpga/dts_copy/$CONFIG.dts

# (optional) compile device-tree to binary
dtc -I dts -O dtb -o fpga/dts_copy/$CONFIG.dtb fpga/dts_copy/$CONFIG.dts
```

### 5. Program the FPGA

**Option A — Script (opens Vivado GUI):**

```bash
bash fpga/scripts/program_fpga.sh
```

**Option B — Vivado Hardware Manager manually:**

1. Open Vivado → *Hardware Manager* → *Open Target* → *Auto Connect*
2. *Program Device* → select `fpga/bitstream_copy/<CONFIG>.bit`

### 6. Connect via serial console

```bash
bash fpga/scripts/connect_serial.sh
```

Defaults: `/dev/ttyUSB0` at **115200 baud**. Exit picocom with `Ctrl-A` then `Ctrl-X`.

---

## One-Liner (automated script)

A convenience script wraps steps 1–4:

```bash
bash fpga/scripts/generate_bitstream.sh
```

Edit the `CONFIG` and `PBUS_CLK` variables at the top of the script to match your desired config.

---

## Directory Layout

```
fpga/
├── Makefile                        # Top-level FPGA build (make bitstream)
├── bitstream_copy/                 # Copied .bit files
├── dts_copy/                       # Copied .dts / .dtb files
├── generated-src/                  # Vivado project & outputs per config
├── scripts/
│   ├── generate_bitstream.sh       # End-to-end build script
│   ├── program_fpga.sh             # Program board via Vivado GUI
│   └── connect_serial.sh           # Open serial console (picocom)
└── src/main/
    ├── resources/genesys2/sdboot/  # Zero-stage bootloader source
    └── scala/genesys2/
        ├── Configs.scala           # All Genesys2 FPGA configs
        ├── TestHarness.scala       # Top-level harness (clocks, DDR, UART, SPI)
        └── HarnessBinders.scala    # IO binders (UART, SPI, DDR, JTAG)
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Failed to build bootrom` | Ensure `PBUS_CLK` matches the peripheral-bus frequency of your config |
| Vivado not found | `source /tools/Xilinx/Vivado/2024.1/settings64.sh` (adjust path) |
| `/dev/ttyUSB0` not found | Check USB cable; try `ls /dev/ttyUSB*` and update `connect_serial.sh` |
| Timing violations | Lower the clock with `WithFPGAFrequency` or use a simpler config |
| Out of memory during build | Reduce `-j` parallelism or add swap space |
