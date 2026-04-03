# Batch Inference Run — Issues and Fixes for Next Iteration

Observed from log file `batch_inference_log.txt`, run started Thu Mar 26 08:54:33 2026.

---

## Script Call Chain

```
batch_inference.sh                                         (host)
  ├─ [Step 1] vivado → program_bitstream_batch.tcl         (programs FPGA via JTAG)
  └─ [Step 2] expect → run_soc_inference.expect            (host)
                ├─ vivado → reset_fpga.tcl                 (reset loop, up to 5×)
                └─ picocom → UART
                      └─ sh run_inference_benchmarks.sh <bitstream_name>   (SoC /Test/)
                            │
                            ├─ run_imagenet_benchmarks.sh                  (SoC /Test/)
                            │     ├─ cd /Test/imagenet/ && ./resnet50_cifar10_stream-linux
                            │     ├─ cd /Test/imagenet/ && ./mobilenet_cifar10_stream-linux
                            │     ├─ cd /Test/imagenet/ && ./resnet50_v1-linux
                            │     ├─ cd /Test/imagenet/ && ./mobilenet_v1-linux
                            │     └─ saves imagenet_results_<ts>.csv + imagenet_logs/
                            │
                            ├─ run_transformer_benchmarks.sh               (SoC /Test/)
                            │     ├─ cd /Test/transformers/ && ./bert-tiny-sst2-stream-linux
                            │     └─ saves transformer_results_<ts>.csv + transformer_logs/
                            │
                            └─ prints "Run Complete"   ← expect detects this and exits
```

All output is piped through `tee -a master.log` into `/Test/results/<timestamp>_<config>/`.

---

## Benchmark Timing (Measured from Host Vivado Timestamps)

Each design takes almost exactly **3 hours 4 minutes** wall-clock time.
The 3 hours is the `expect` timeout firing every time. The 4 minutes is Vivado programming + FPGA boot overhead.

| Benchmark | Status | Wall-clock time |
|---|---|---|
| `resnet50_cifar10_stream-linux` | Completes every design | ~56 min (125 batches × ~26.8 s/batch) |
| `mobilenet_cifar10_stream-linux` | Completes every design | ~12 min (125 batches × ~5.9 s/batch avg) |
| `resnet50_v1-linux` | **Never completes** — timeout fires at batch ~23/125 | ~9.4 hrs estimated total (125 × ~4.5 min/batch) |
| `mobilenet_v1-linux` | **Never runs** — blocked behind resnet50_v1 | Unknown — never reached |
| `bert-tiny-sst2-stream-linux` (transformer) | **Never runs** — blocked behind imagenet suite | Unknown — never reached |

### Why resnet50_v1 is slower than SoC timing suggests

The SoC benchmark output shows ~33 seconds per batch for `resnet50_v1`. This is **only the Gemmini inference time**. It does not include:
- Loading the next batch of images from the SD card (~75 KB/s read speed on FPGA SPI-SD)
- Image preprocessing (resize, normalise) at 35 MHz
- Verbose per-image output printing (8 images × Top-10 predictions = ~120 lines per batch)

The empirical wall-clock time per batch is ~4.5 minutes (270 seconds), not 33 seconds.

Full imagenet suite estimated wall-clock: **~10–11 hours per design**.
Transformer time: unknown — no data collected yet.

---

## Issues Found

### 1. `expect` timeout too short — root cause of all failures

**Current:** `set timeout 10800` (3 hours) in `run_soc_inference.expect`

**Effect:** Every single design times out. `resnet50_v1` is cut off at batch ~23/125.
The transformer suite never starts.

**Fix:** Either remove the timeout entirely and rely unconditionally on `"Run Complete"`,
or set it to at least 43200 seconds (12 hours) per design to cover the full imagenet
suite (~10.5 hrs) plus transformer overhead.

```tcl
# Option A — no timeout (recommended, safest)
set timeout -1
expect "Run Complete"

# Option B — large explicit timeout
set timeout 43200
expect {
    "Run Complete" { ... }
    timeout        { ... }
}
```

### 2. SoC result timestamps collide across designs

**Current:** `run_inference_benchmarks.sh` uses `date +"%Y%m%d_%H%M%S"` on the SoC.
The SoC has no RTC. After each reprogram the clock resets to epoch (1970-01-01).
Timestamps end up like `19700101_000429` and repeat across designs, causing CSV files
from different designs to overwrite each other on the SD card.

**Observed collisions:**
```
[3/13] mul8s_1KV9  → imagenet_results_19700101_000429.csv
[5/13] mul8s_1KVM  → imagenet_results_19700101_000429.csv  ← overwrites!
```

**Fix:** Pass the host-side timestamp into `run_inference_benchmarks.sh` as a second
argument, or have the batch script set the SoC clock via `date -s` over UART before
running the benchmark:

```tcl
# In run_soc_inference.expect, after boot and before benchmark:
set host_ts [exec date +%Y%m%d_%H%M%S]
send "date -s \"[exec date '+%Y-%m-%d %H:%M:%S']\"\r"
expect -re {[#$] }
```

Or simpler: modify `run_inference_benchmarks.sh` to accept an optional timestamp argument
and fall back to the SoC date only if not provided. The `batch_inference.sh` script already
passes `$bitstream_name` — a host timestamp can be passed as a second argument.

### 3. Script must not be run with `sudo`

**Current:** User ran `sudo ./batch_inference.sh`, causing:
```
WARNING: User 'root' is not in the 'dialout' group.
```
Vivado also breaks under root (license paths, `~/.Xilinx` config).

**Fix:** Run as the regular user:
```bash
bash fpga/scripts/batch_inference.sh
```
Add user to `dialout` once so picocom does not need sudo:
```bash
sudo usermod -aG dialout $USER   # then log out and back in
```

### 4. Redundant initial FPGA programming (double boot)

**Current:** `batch_inference.sh` calls `program_bitstream_batch.tcl` first (Step 1),
which immediately boots the FPGA. Then `run_soc_inference.expect` reprograms it again
(reset attempt 1 via `reset_fpga.tcl`). This causes OpenSBI to appear twice and wastes
~1 minute per design.

**Fix:** Remove Step 1 (the `program_bitstream_batch.tcl` Vivado call) from the batch
script. The expect script's reset loop handles programming completely. Step 1 is redundant.

### 5. SD card binaries incomplete or in wrong locations

`run_imagenet_benchmarks.sh` looks for binaries in `/Test/imagenet/` and
`run_transformer_benchmarks.sh` looks in `/Test/transformers/`. The required
SD card layout under `/Test/` is:

```
/Test/
├── run_inference_benchmarks.sh
├── run_imagenet_benchmarks.sh
├── run_transformer_benchmarks.sh
├── imagenet/
│   ├── resnet50_cifar10_stream-linux   ← present (runs fine)
│   ├── mobilenet_cifar10_stream-linux  ← present (runs fine)
│   ├── resnet50_v1-linux               ← present (runs, never finishes)
│   ├── mobilenet_v1-linux              ← status unknown (never reached)
│   └── *.bin / *.txt                   (image dataset files, must be in same dir)
└── transformers/
    ├── bert-tiny-sst2-stream-linux     ← missing or never reached
    └── *.bin / *.txt                   (model weights + dataset files, must be in same dir)
```

Each binary is run with `cd <dir> && ./<binary>` so dataset files must be
co-located in the same subdirectory as the binary, not in `/Test/` itself.

Compile each binary for RISC-V (`riscv64-unknown-linux-gnu-gcc`) and copy
to the SD card along with its data files before the next run.

---

## Projected Run Times for Next Iteration

Assuming timeout is fixed (removed or extended to 12 hours):

| Stage | Estimated time |
|---|---|
| Vivado FPGA programming (per design) | ~1 min |
| FPGA boot to BusyBox shell | ~7–10 min |
| `resnet50_cifar10` | ~56 min |
| `mobilenet_cifar10` | ~12 min |
| `resnet50_v1` | ~9–10 hrs |
| `mobilenet_v1` | Unknown — never reached |
| `bert-tiny` transformer | Unknown — never reached |
| **Total per design** | **~10–11 hrs + mobilenet_v1 + transformer time** |
| **Total for 13 designs** | **~6–7 days minimum** |

Consider running fewer designs per batch or reducing the dataset size (fewer images)
for quicker full-suite runs during debugging.

---

## Summary of Required Script Changes

| File | Change needed |
|---|---|
| `run_soc_inference.expect` | Set `timeout -1` (or ≥43200) for the benchmark wait |
| `run_soc_inference.expect` | Optionally set SoC clock via `date -s` before benchmark |
| `batch_inference.sh` | Remove Step 1 Vivado call (redundant programming) |
| `batch_inference.sh` | Pass host timestamp as second arg to expect script |
| `run_inference_benchmarks.sh` | Accept optional host timestamp argument |
| SD card `/Test/imagenet/` | Verify `mobilenet_v1-linux` binary + data files present |
| SD card `/Test/transformers/` | Add `bert-tiny-sst2-stream-linux` binary + data files |
| (one-time) | `sudo usermod -aG dialout $USER` and run without sudo |
