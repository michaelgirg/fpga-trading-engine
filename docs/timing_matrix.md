# HFT Timing Matrix

## Purpose

The HFT reference target for this project is the 512-bit parser path on a
realistic 100G-class FPGA, not the ZedBoard. Zynq-7020 remains useful as a
functional demo target, but it does not close the 512-bit path at the
322 MHz-class 100G-facing clock.

All numbers below are out-of-context Vivado synthesis reports. They are useful
architecture evidence and regression targets, but they are not full
placed-and-routed board timing closure.

## Measured Results

| Target | Part | Top | Period | Approx. frequency | WNS | TNS | Status |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| Zynq demo | `xc7z020clg484-1` | `market_parser_512_frontend` | `3.102 ns` | 322 MHz | `-3.341 ns` | `-501.212 ns` | Does not close |
| Zynq demo | `xc7z020clg484-1` | `market_parser_512_pipeline` | `3.102 ns` | 322 MHz | `-3.290 ns` | `-9750.711 ns` | Does not close |
| U50-class HFT reference | `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `3.102 ns` | 322 MHz | `0.872 ns` | `0.000 ns` | Meets |
| U50-class HFT reference | `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `3.102 ns` | 322 MHz | `1.091 ns` | `0.000 ns` | Meets |

## U50 Frontend Clock Sweep

| Part | Top | Period | Approx. frequency | WNS | TNS | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `3.102 ns` | 322 MHz | `0.872 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `2.100 ns` | 476 MHz | `0.082 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `2.000 ns` | 500 MHz | `-0.018 ns` | `-0.184 ns` | Near miss |

## U50 Pipeline Clock Sweep

| Part | Top | Period | Approx. frequency | WNS | TNS | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `3.102 ns` | 322 MHz | `1.091 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.750 ns` | 364 MHz | `0.739 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.500 ns` | 400 MHz | `0.489 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.250 ns` | 444 MHz | `0.239 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.100 ns` | 476 MHz | `0.082 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.000 ns` | 500 MHz | `0.030 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `1.950 ns` | 513 MHz | `-0.020 ns` | `-0.041 ns` | Near miss |

The integrated pipeline now closes at 2.000 ns / 500 MHz OOC on the U50-class
target and misses 1.950 ns / 513 MHz by only 0.020 ns. The standalone frontend
still misses 2.000 ns by 0.018 ns, but the integrated parser top is the
interview/resume headline.

## School Vivado Matrix Command

On the school Linux host:

```bash
cd ~/market-parser-runs/<run-dir>
source /apps/xilinx/Vivado/2024.2/settings64.sh
bash tools/run_hft_ooc_matrix.sh
```

To run a smaller first pass:

```bash
MARKET_PARSER_PARTS="xcu50-fsvh2104-2-e" \
MARKET_PARSER_TOPS="market_parser_512_frontend market_parser_512_pipeline" \
MARKET_PARSER_PERIODS="3.102 2.100 2.000" \
bash tools/run_hft_ooc_matrix.sh
```

The script writes each run under `build/hft_ooc_matrix/<timestamp>/` and writes
a tab-separated `summary.tsv` with timing, utilization, status, and report
directory columns.

## Next Matrix Targets

The next useful comparison is not more ZedBoard synthesis. It is the same OOC
matrix across the school-installed 100G-class parts:

| Family or card class | Example part | Why it matters |
| :--- | :--- | :--- |
| Alveo U50-class | `xcu50-fsvh2104-2-e` | Current reference result and internship-friendly headline. |
| Alveo U55N/U55C-class | `xcu55n-fsvh2892-2L-e`, `xcu55c-fsvh2892-2L-e` | More realistic high-end network accelerator comparison. |
| Virtex UltraScale+ | `xcvu45p-fsvh2104-2-e` | Larger FPGA fabric target with the same parser architecture. |

Once a board target is selected, the next step is full implementation timing
with the actual CMAC, clocking, resets, packet-header strip logic, and floorplan
constraints.
