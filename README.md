# Chipyard — Genesys2 FPGA Prototype for AxSCOPE

Based on [Chipyard v1.13.0](https://github.com/ucb-bar/chipyard).

This repository is the SoC integration layer for **AxSCOPE**. It ports the Chipyard FPGA flow to the Digilent Genesys2 board (Xilinx Kintex-7 XC7K325T) and adds automated batch benchmarking scripts that program the FPGA and collect inference results unattended across a set of bitstreams.

---

## Genesys2 FPGA Porting

Chipyard v1.13.0 does not officially support the Genesys2 board. This fork integrates it using the SiFive FPGA shell overlay, following the same pattern used for supported boards.

**What was integrated:**
- UART (SiFive UART)
- JTAG (for bitstream programming and debugging)
- MicroSD card (SiFive SPI-to-MMC, for storing the SD bootloader and filesystem)

**What was added/modified:**
- Genesys2 overlay files under `fpga/` and `fpga-shells/`
- `build.sbt` updated to include the Genesys2 target
- SD bootloader (`sdboot`) build for the Genesys2 peripheral bus clock

### Building a Bitstream

After completing the standard Chipyard `build-setup.sh` and copying the Genesys2 overlay files:

```bash
chipyard_root="$HOME/chipyard"
CONFIG="Rocket90MHZ"
PBUS_CLK=90000000

# 1. Build the SD bootloader (zero-stage, embedded in ROM)
cd $chipyard_root/fpga/src/main/resources/genesys2/sdboot
make clean && make PBUS_CLK=$PBUS_CLK

# 2. Build the bitstream
cd $chipyard_root/fpga
make clean
make CONFIG=$CONFIG bitstream -j16

# 3. Collect outputs
cp generated-src/chipyard.fpga.genesys2.GENESYS2FPGATestHarness.$CONFIG/obj/*.bit bitstream_copy/$CONFIG.bit
```

The bitstream embeds the zero-stage SD bootloader. The FPGA is programmed via Vivado Hardware Manager (JTAG). For a full Linux boot, see the companion u-boot and OpenSBI repositories.

---

## Batch Benchmarking Scripts (`fpga/scripts/`)

These scripts automate running the AxSCOPE inference benchmarks across a directory of bitstreams, one after another, without any manual intervention between runs.

### Overview of the flow

```
batch_inference.sh
  └─ for each *.bit in batch directory:
       1. program_bitstream_batch.tcl   ← programs FPGA via Vivado JTAG (batch mode)
       2. run_soc_inference.expect      ← connects picocom to UART, waits for
                                           BusyBox Linux to boot, runs
                                           /Test/run_inference_benchmarks.sh on SoC,
                                           saves results to SD card
```

Results are written to `/Test/results/<timestamp>_<bitstream_name>/` on the SD card by the on-SoC runner script.

### Scripts

| Script | Purpose |
|--------|---------|
| `batch_inference.sh` | Main batch runner. Iterates over all `.bit` files in a batch directory, programs then benchmarks each one. Holds a `systemd-inhibit` lock so the host machine does not sleep mid-run. Installs `expect` and `picocom` if missing, auto-installs Xilinx JTAG udev rules if not present. |
| `batch_benchmark.sh` | Variant that runs the full suite (GEMM + MLP + CNN + Transformer benchmarks). |
| `batch_resnet50_only.sh` | Variant that runs only the ResNet-50 CIFAR-10 streaming benchmark. |
| `batch_inference_v2.sh` | Updated variant with revised expect timing for slower boot configurations. |
| `program_bitstream_batch.tcl` | Vivado Tcl script called in batch mode. Opens the hardware manager, connects to the Genesys2 (xc7k325t) via JTAG target `localhost:3121/xilinx_tcf/Digilent/...`, programs the bitstream, then cleanly disconnects. |
| `run_soc_inference.expect` | Expect script: opens `picocom` on the UART port, triggers reset, waits for BusyBox login prompt, runs the benchmark script, and captures the CSV output. |

### Usage

```bash
# Edit the BATCH_DIR variable in the script to point to your bitstream directory
# then run:
bash fpga/scripts/batch_inference.sh
```

The script will process every `.bit` file found in `BATCH_DIR`, print a per-bitstream pass/fail summary, and report any failures at the end. Sudo credentials are kept alive automatically throughout the run (needed for serial port access).

**Prerequisites:**
- Vivado 2024.1 installed at `/tools/Xilinx/Vivado/2024.1/`
- Genesys2 connected via USB-JTAG and powered on
- SD card loaded with BusyBox Linux and the AxSCOPE benchmark binaries at `/Test/`
- User in the `dialout` group (for serial port access)

---

## Repository Structure (FPGA-relevant paths)

```
chipyard/
├── fpga/
│   ├── src/main/resources/genesys2/   # Genesys2 board overlay (constraints, SDboot)
│   ├── scripts/
│   │   ├── batch_inference.sh         # Main batch benchmark runner
│   │   ├── batch_benchmark.sh         # Full suite variant
│   │   ├── batch_resnet50_only.sh     # ResNet-50 only variant
│   │   ├── batch_inference_v2.sh      # Updated timing variant
│   │   ├── program_bitstream_batch.tcl # Vivado JTAG programming script
│   │   ├── run_soc_inference.expect   # UART automation (boot + run benchmarks)
│   │   └── run_soc_benchmark.expect   # UART automation (full benchmark suite)
│   └── approx_batch_*/                # Batch directories of bitstreams to test
├── generators/gemmini/                # AxSCOPE hardware (custom multiplier framework)
└── build.sbt                          # Updated to include Genesys2 support
```

---

## Attribution

```bibtex
@article{chipyard,
  author={Amid, Alon and Biancolin, David and Gonzalez, Abraham and Grubb, Daniel
          and Karandikar, Sagar and Liew, Harrison and Magyar, Albert and Mao, Howard
          and Ou, Albert and Pemberton, Nathan and Rigge, Paul and Schmidt, Colin
          and Wright, John and Zhao, Jerry and Shao, Yakun Sophia
          and Asanovi\'{c}, Krste and Nikoli\'{c}, Borivoje},
  journal={IEEE Micro},
  title={Chipyard: Integrated Design, Simulation, and Implementation Framework for Custom SoCs},
  year={2020},
  volume={40},
  number={4},
  pages={10-21},
  doi={10.1109/MM.2020.2996616},
}
```
