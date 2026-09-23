# Project Pitch

## One-Sentence Summary

This project is a 512-bit SystemVerilog market-data and order gateway that
turns 100G-style Nasdaq MoldUDP64/ITCH traffic into guarded top-of-book state,
risk-checked orders, and byte-exact OUCH/Soup messages on a U50-class FPGA.

## Interview Pitch

I built the project as a closed-loop trading datapath rather than an isolated
message decoder. A no-`tready` CMAC-facing receive bridge buffers complete
packets, the Ethernet/IPv4/UDP shell extracts MoldUDP64, and a parallel 512-bit
pipeline tracks message boundaries and emits normalized ITCH events. Four
bounded books consume add, execute, cancel, delete, and replace activity while
feed guards invalidate state on packet loss, sequence gaps, session changes,
end-of-session markers, or inactivity.

The order side converts actionable quotes into venue-neutral intents, assigns
monotonic client IDs, tracks pending/live/cancel state and partial fills, and
applies an independent final risk stage. A two-entry command FIFO isolates
backpressure before byte-exact OUCH 5.0 Enter/Cancel encoding. The SoupBinTCP
logical client generates login, heartbeat, logout, and unsequenced packets;
parses session and sequence state; reconstructs two-beat responses; and fails
closed on transport or watchdog faults. Ethernet/TCP reliability and socket
establishment remain external.

Verification combines Python reference models with self-checking SystemVerilog
testbenches, randomized AXI backpressure, malformed/truncated traffic, dense
messages, no-idle MTU bursts, FIFO pressure, feed recovery, lifecycle races,
risk rejects, exact protocol-byte checks, scoreboards, and telemetry accounting.
The checked-in Questa regression runs 38 self-checking configurations with zero
compile errors, zero compile warnings, and zero failed tests.

On `xcu50-fsvh2104-2-e`, the parser pipeline closes 2.000 ns / 500 MHz OOC.
The complete packet-to-Soup/OUCH compact harness closes post-route at 3.102 ns
/ 322.4 MHz with WNS `+0.075 ns`, TNS `0.000 ns`, WHS `+0.010 ns`, 26,227
LUTs, 30,185 registers, 8.5 BRAM tiles, and zero DSPs. A separately generated,
board-constrained AXIS CAUI-4 CMAC plus parser harness also routes at the native
clock with zero black boxes and clean DRC; bitstream output remains blocked by
the CMAC encrypted-IP entitlement.

## What To Emphasize

- Low-latency streaming RTL with explicit elastic boundaries and backpressure.
- Market-data correctness across packet, feed, book, order, and session state.
- Fail-closed controls for loss, stale feeds, risk violations, and transport
  faults.
- Verification through independent models, adversarial traffic, and exact
  counter reconciliation.
- Honest separation between OOC timing, routed timing, generated vendor IP,
  and hardware-programming claims.

## Honest Limits

The Soup boundary consumes complete logical packets above TCP; the project does
not implement a TCP stack or live exchange connectivity. Routed results use a
compact deterministic harness, and no bitstream has been loaded onto hardware.
The next realism work is constrained-random full-path replay, functional
coverage, protocol assertions, latency histograms, and host/transport
integration once suitable hardware and licensing are available.
