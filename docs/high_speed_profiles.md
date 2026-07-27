# High-Speed Stream Profiles

## Interfaces

| Profile | Data | Keep | Role |
| :--- | ---: | ---: | :--- |
| Portable adapter | 64/256/512 bits | 8/32/64 bytes | Reuses the byte-oriented golden parser across stream widths. |
| Parallel parser | 512 bits | 64 bytes | Descriptor scan, packet window, parallel event extraction, and event FIFO. |
| CMAC AXIS RX | 512 bits | 64 bytes | No-`tready` packet bridge, Ethernet/IPv4/UDP strip, and guarded parser path. |
| OUCH/Soup logical packets | 512 bits | 64 bytes | Backpressured order/session messages above TCP transport. |

The ZedBoard profile is a functional demo path, not a 100G networking target.
The U50-class 512-bit path is the HFT reference design.

## Implemented High-Speed Path

The parallel parser tracks MoldUDP64/ITCH message boundaries across beats,
stores a bounded packet window, and emits normalized events before packet end
when the required bytes are available. A 64-beat BRAM-backed CMAC receive
buffer absorbs no-`tready` bursts, and a 32-beat packet store supports
standard-MTU-class frames without expanding the timing-critical extraction
window.

The guarded path adds packet-atomic overflow rollback, feed-loss notification,
session/sequence continuity, inactivity timeout, two-phase rebuild, explicit
activation, multi-symbol books, quote arbitration, decision and lifecycle
state, final risk, and OUCH/Soup handling.

## Verification Evidence

- Identical normalized events across portable stream widths.
- Cut-through event emission with stable output under backpressure.
- Dense cross-beat messages, malformed/truncated packets, and FIFO pressure.
- Two contiguous 1462-byte frames carrying 200 ITCH messages without an idle
  CMAC cycle, overflow, or dropped beat.
- Packet-atomic rollback and fail-closed recovery after forced CMAC overflow.
- Closed-loop market packet to OUCH order to acceptance/fill reconciliation.
- Exact Soup login/session bytes, reconnect sequence state, heartbeats, logout,
  watchdog expiry, and transport-loss handling.

## Timing Evidence

On `xcu50-fsvh2104-2-e`, the integrated parser pipeline closes 2.000 ns / 500
MHz OOC. The source-only guarded CMAC AXIS multi-symbol top closes 2.500 ns /
400 MHz OOC with WNS `+0.011 ns`. The complete packet-to-Soup/OUCH compact
harness closes post-route at 3.102 ns / 322.4 MHz with WNS `+0.075 ns`, TNS
`0.000 ns`, and WHS `+0.010 ns`.

A separate generated AXIS CAUI-4 CMAC plus parser harness also fully routes at
3.102 ns with zero black boxes and clean DRC. Bitstream generation is blocked
by the encrypted CMAC IP entitlement, so none of these results is presented as
a programmed-hardware or live-traffic claim.
