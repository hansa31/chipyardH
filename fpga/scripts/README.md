# generate_bitstream.sh Usage

This script builds the bitstream and related files for the Genesys2 FPGA using Chipyard.


## Important Notes
- You must manually set the `chipyard_root` variable near the top of the script to match your local Chipyard path. For example:
  - On your PC: `chipyard_root="$HOME/Desktop/GemminiChipyard/chipyard"`
  - On your laptop: `chipyard_root="$HOME/Desktop/chipyard"`
- The script expects Vivado 2021.2. Make sure the following line is present in the script:

  ```bash
  source /tools/Xilinx/Vivado/2021.2/settings64.sh
  ```

- If you want the bitstream and Vivado reports copied to an external SSD, ensure it is mounted at `/media/hansa/SanDisk1TBH` before running the script.

## Running the Script

```bash
./generate_bitstream.sh
```

Make sure the script is executable:

```bash
chmod +x generate_bitstream.sh
```

## Output
- Bitstream, device tree source, and Vivado reports will be copied to both the project directory and the SSD (if present).
