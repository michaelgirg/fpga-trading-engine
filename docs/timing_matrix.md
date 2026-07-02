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
| U50-class HFT reference | `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `3.102 ns` | 322 MHz | `0.776 ns` | `0.000 ns` | Meets |

## U50 Frontend Clock Sweep

| Part | Top | Period | Approx. frequency | WNS | TNS | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `3.102 ns` | 322 MHz | `0.872 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `2.100 ns` | 476 MHz | `0.082 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_frontend` | `2.000 ns` | 500 MHz | `-0.018 ns` | `-0.184 ns` | Near miss |

## U50 Pipeline Clock Sweep

| Part | Top | Period | Approx. frequency | WNS | TNS | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `3.102 ns` | 322 MHz | `1.132 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.750 ns` | 364 MHz | `0.739 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.500 ns` | 400 MHz | `0.489 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.250 ns` | 444 MHz | `0.239 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.200 ns` | 455 MHz | `0.230 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.100 ns` | 476 MHz | `0.130 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.050 ns` | 488 MHz | `0.080 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `2.000 ns` | 500 MHz | `0.030 ns` | `0.000 ns` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_512_pipeline` | `1.950 ns` | 513 MHz | `-0.020 ns` | `-0.041 ns` | Near miss |

The integrated pipeline now closes at 2.000 ns / 500 MHz OOC on the U50-class
target and misses 1.950 ns / 513 MHz by only 0.020 ns. The standalone frontend
still misses 2.000 ns by 0.018 ns, but the integrated parser top is the
interview/resume headline.

## U50 CMAC-Facing Shell Sweep

This top includes the Ethernet II / IPv4 / UDP header strip and payload
realignment shell in front of `market_parser_512_system`. The important target
is the 3.102 ns 100G CMAC user-clock class; the 2.1 ns and 2.0 ns rows are
stress sweeps, not required CMAC operating points.

| Part | Top | Period | Approx. frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_system` | `3.102 ns` | 322 MHz | `0.265 ns` | `0.000 ns` | `21723 / 871680 (2.49%)` | `18170 / 1743360 (1.04%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_system` | `2.200 ns` | 455 MHz | `-0.637 ns` | `-157.722 ns` | `21888 / 871680 (2.51%)` | `18170 / 1743360 (1.04%)` | Does not close |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_system` | `2.100 ns` | 476 MHz | `-0.737 ns` | `-569.690 ns` | `21888 / 871680 (2.51%)` | `18170 / 1743360 (1.04%)` | Does not close |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_system` | `2.050 ns` | 488 MHz | `-0.787 ns` | `-779.328 ns` | `21888 / 871680 (2.51%)` | `18170 / 1743360 (1.04%)` | Does not close |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_system` | `2.000 ns` | 500 MHz | `-0.837 ns` | `-991.538 ns` | `21888 / 871680 (2.51%)` | `18170 / 1743360 (1.04%)` | Does not close |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_cmac_system` | `1.950 ns` | 513 MHz | `-0.887 ns` | `-1212.754 ns` | `21888 / 871680 (2.51%)` | `18170 / 1743360 (1.04%)` | Does not close |

The shell result shows the board-facing path closes at the realistic 512-bit
100G receive clock with margin. The 500 MHz result should remain attached to
the parser pipeline itself, not the full Ethernet header-strip shell.

## U50 Top-Of-Book Engine

`market_parser_top_of_book` consumes normalized ITCH events and maintains a
small single-symbol book. The first version used a one-cycle full-table
recompute and did not close 3.102 ns. The current implementation uses iterative
lookup and quote recompute.

| Part | Top | Period | Approx. frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_top_of_book` | `3.102 ns` | 322 MHz | `0.605 ns` | `0.000 ns` | `1413 / 871680 (0.16%)` | `3146 / 1743360 (0.18%)` | Meets |

This result shows the trading-oriented post-parser book block closes the same
100G user-clock target as the CMAC-facing shell.

## Strategy-Facing Packet-To-Book Top

`market_parser_100g_strategy_top` connects the CMAC-facing shell directly to
`market_parser_top_of_book`, producing quote updates from raw Ethernet/IPv4/UDP
feed frames. The target for this combined top is still the 3.102 ns / 322 MHz
100G user-clock class.

| Part | Top | Period | Approx. frequency | WNS | TNS | LUTs | Registers | Status |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- | :--- | :--- |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `3.102 ns` | 322 MHz | `0.776 ns` | `0.000 ns` | `23007 / 871680 (2.64%)` | `21869 / 1743360 (1.25%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.750 ns` | 364 MHz | `0.424 ns` | `0.000 ns` | `23188 / 871680 (2.66%)` | `21869 / 1743360 (1.25%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.500 ns` | 400 MHz | `0.174 ns` | `0.000 ns` | `23189 / 871680 (2.66%)` | `21869 / 1743360 (1.25%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.450 ns` | 408 MHz | `0.124 ns` | `0.000 ns` | `23189 / 871680 (2.66%)` | `21869 / 1743360 (1.25%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.400 ns` | 417 MHz | `0.074 ns` | `0.000 ns` | `23189 / 871680 (2.66%)` | `21869 / 1743360 (1.25%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.350 ns` | 426 MHz | `0.024 ns` | `0.000 ns` | `23189 / 871680 (2.66%)` | `21869 / 1743360 (1.25%)` | Meets |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.300 ns` | 435 MHz | `-0.026 ns` | `-0.063 ns` | `23189 / 871680 (2.66%)` | `21869 / 1743360 (1.25%)` | Near miss |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.250 ns` | 444 MHz | `-0.587 ns` | `-6.716 ns` | `23268 / 871680 (2.67%)` | `21295 / 1743360 (1.22%)` | Does not close |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.100 ns` | 476 MHz | `-0.737 ns` | `-568.394 ns` | `23268 / 871680 (2.67%)` | `21295 / 1743360 (1.22%)` | Does not close |
| `xcu50-fsvh2104-2-e` | `market_parser_100g_strategy_top` | `2.000 ns` | 500 MHz | `-0.837 ns` | `-1011.505 ns` | `23268 / 871680 (2.67%)` | `21295 / 1743360 (1.22%)` | Does not close |

This is the current full-system OOC milestone: 100G-style packet ingress,
Ethernet/IP/UDP stripping, MoldUDP64/ITCH parsing, normalized event buffering,
and top-of-book quote generation all meet the 322 MHz target in one combined
top. After adding a payload register slice and staging the frontend beat-offset
update, the same top also closes 2.350 ns / 426 MHz and misses 2.300 ns /
435 MHz by only 26 ps.

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
