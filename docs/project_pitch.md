# Project Pitch

## One-Sentence Summary

This project is a SystemVerilog FPGA market-data parser for Nasdaq
MoldUDP64/ITCH, built as a simulation-first feed-handler core with a U50-class
100G-capable frontend architecture and optional ZedBoard demo path.

## Interview Pitch

I built a production-shaped FPGA market parser rather than a toy decoder. The
core accepts MoldUDP64 packet frames, tracks sequence numbers, detects gaps and
malformed packets, splits ITCH messages by length, and emits normalized 256-bit
events. I verified it with generated protocol vectors, randomized output
backpressure, malformed/truncated packet tests, and Questa regression reports.

To make it relevant to low-latency trading hardware, I kept the parser core
transport-independent and added wider frontend profiles. The repo now includes
a 512-bit MAC-facing ingress shell, a multi-beat 512-bit descriptor frontend
that tracks ITCH message boundaries across packet beats, and a parallel
extractor that packs descriptor-selected fields into normalized events. I then
wired those blocks into a cut-through 512-bit event pipeline and verified it
against the same golden event vectors, including a test where the first event
appears before packet end while later beats continue arriving. I also added an
event FIFO boundary and an AXI-Lite control/status block so software can enable
the parser, read counters, clear sticky error flags, and observe FIFO state.
The verification suite now includes no-idle back-to-back packet stress,
FIFO-pressure checks, 128/256/512-byte extraction-window sweeps, cocotb
randomized repeated-packet and malformed-frame tests, and a Vivado
out-of-context synthesis hook.

For timing, I separate the accessible demo target from the HFT reference
target. The 512-bit path does not close at 322 MHz on Zynq-7020, so ZedBoard is
positioned as a functional hardware demo only. On a school Vivado 2024.2
U50-class UltraScale+ target (`xcu50-fsvh2104-2-e`), OOC synthesis meets the
same 3.102 ns target with positive slack: WNS `0.872 ns` for the 512-bit
frontend and WNS `1.091 ns` for the integrated 512-bit pipeline. A clock sweep
of the integrated pipeline meets through `2.000 ns` / 500 MHz and misses
`1.950 ns` / ~513 MHz by only `0.020 ns`.
After a lane-offset retiming cleanup, the standalone 512-bit frontend also
meets `2.100 ns` and misses `2.000 ns` by only `0.018 ns`.

The repo also includes a CMAC-facing packet shell and a strategy-facing
top-of-book integration path. The combined `market_parser_100g_strategy_top`
takes raw 100G-style Ethernet/IP/UDP feed frames through payload stripping,
MoldUDP64/ITCH parsing, normalized event buffering, and single-symbol
top-of-book quote generation. On the same U50-class target it meets the 3.102
ns / 322 MHz target with WNS `0.776 ns` and closes 2.350 ns / 426 MHz, while
2.300 ns / 435 MHz misses by only `0.026 ns`. A routed implementation harness
for that full strategy path also closes the 3.102 ns target post-route after
adding a CMAC RX register slice before payload stripping. The school
`cmac_usplus` probe confirmed an AXIS RX template with no `tready`, so I added
a source-only CMAC AXIS RX bridge and wrapper; that boundary now closes OOC at
3.102 ns with WNS `0.449 ns`, stress-closes 2.750 ns / 364 MHz, and closes a
post-route CMAC AXIS implementation harness at the 3.102 ns target.

That does not pretend to be a finished 100G trading NIC; it shows the right
interface boundary, buffering, observability, and parallel parsing stages needed
for one.

## Strong Resume Bullet

Built a SystemVerilog FPGA market-data parser for Nasdaq MoldUDP64/ITCH with
sequence tracking, gap/error detection, normalized event output, AXI-stream-style
interfaces, generated reference vectors, randomized backpressure verification,
cycle-level latency reports, AXI-Lite control/status registers, and 512-bit
100G-facing descriptor/event-extraction frontend blocks integrated into a
cut-through parallel event pipeline with queued normalized-event output,
back-to-back packet stress, FIFO-pressure accounting, 128/256/512-byte
extraction-window sweeps, cocotb randomized checks, a CMAC-facing packet shell,
source-only CMAC AXIS RX buffering, and a top-of-book quote path. Vivado OOC
synthesis meets a 3.102 ns target on a U50-class UltraScale+ reference part for
the full packet-to-book strategy top and CMAC AXIS strategy boundary, the routed
implementation harness closes that same 100G target post-route, and the parser
pipeline closes through `2.000 ns` / 500 MHz on the same reference target.

## What To Emphasize

- Clean hardware interfaces: valid/ready input and output paths.
- Protocol awareness: MoldUDP64 sequence/message count and ITCH message lengths.
- Verification discipline: self-checking testbenches, generated vectors,
  randomized backpressure, FIFO pressure, bad packet cases, cocotb checks, and
  zero-warning Questa regressions.
- Production mindset: counters, sticky error flags, implemented AXI-Lite
  register map, and honest documentation of what is and is not line-rate.
- Growth path: byte-serial golden parser first, then wide frontend descriptors,
  then parallel field extraction, then integrated cut-through event pipeline,
  then sustained-line-rate timing and burst proof.

## Honest Limits

The byte-serial parser remains the mature golden correctness path. The 512-bit
parallel path is now cut-through within a packet and uses a four-beat/256-byte
default packet-local extraction window with 128/256/512-byte sweep coverage,
and OOC synthesis meets a 3.102 ns target on a U50-class UltraScale+ reference
part, with sweep headroom through 2.100 ns. The routed implementation harness
also closes the 3.102 ns / 322 MHz target, and the source-only CMAC AXIS
strategy boundary closes that same OOC target. It is still not a completed 100G
MAC integration. The next production steps are actual AMD CMAC IP integration,
board-level clock/reset constraints, larger replay-style book tests, broader
school-target timing comparison, and optional 1.950 ns parser timing cleanup.
