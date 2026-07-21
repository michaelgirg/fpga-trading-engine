# Register Map

## Goal

This register map is the control/status surface for a Zynq PS, PCIe host, or
management block. The pre-hardware RTL now implements this map in
`market_parser_axi_lite_regs.sv` and connects it to the FIFO-backed 512-bit
parser through `market_parser_512_system.sv`.

## Control And Status

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0000` | `CONTROL` | RW | Bit 0: enable parser. Bit 1: clear sticky flags/counters through software-visible baselines. Bit 2: write one to clear book state and begin feed rebuild. Bit 3: write one to request activation of a qualified rebuilt feed; pulse bits read as zero. |
| `0x0004` | `STATUS` | RO | Bit 0: parser enabled. Bit 1: ingress backpressured. Bit 2: event FIFO non-empty. Bit 3: event FIFO full. Bit 4: event output valid. Bit 5: feed healthy/tradable. Bit 6: CMAC AXIS packet-buffer overflow history. Bit 7: feed-liveness timeout history. Bit 8: feed rebuild in progress. Bit 9: activation rejection history. Bit 10: MoldUDP64 session-change history. History bits are relative to the current counter baseline. |
| `0x0008` | `BUILD_ID` | RO | Build/version identifier. Default: `0x4d505253`. |

## Implemented Parser Counters

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0010` | `PACKET_COUNT` | RO | MoldUDP64 packet frames accepted by parser path. |
| `0x0014` | `DESCRIPTOR_COUNT` | RO | ITCH message descriptors processed by 512-bit parser path. |
| `0x0018` | `EVENT_COUNT` | RO | Normalized events emitted by parser path. |
| `0x001C` | `ERROR_COUNT` | RO | Parallel extractor error counter. |
| `0x004C` | `BAD_FRAME_COUNT` | RO | RX frames marked bad by MAC sideband. |

## Sticky Flags

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0030` | `ERROR_FLAGS` | RO/W1C | Bit 1: extractor error observed. Bit 3: bad frame observed. Bit 4: event FIFO backpressure observed. |

## Event Output

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0080` | `EVENT_FIFO_STATUS` | RO | Bit 0: empty. Bit 1: full. Bits 31:16: level. |
| `0x00A4` | `EVENT_FIFO_WRITE_COUNT` | RO | Normalized events written into the output FIFO. |
| `0x00A8` | `EVENT_FIFO_READ_COUNT` | RO | Normalized events accepted by the downstream event stream. |
| `0x00AC` | `EVENT_FIFO_BACKPRESSURE_COUNT` | RO | Cycles where the parser had an event but the event FIFO was full. |

## Feed Integrity

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00B0` | `FEED_STATUS` | RO | Bit 0: feed healthy/tradable. Bit 1: feed-liveness timeout history. Bit 2: feed rebuild in progress. Bit 3: rebuild has applied at least one event and is eligible for activation. Bit 4: activation rejection history. Bit 5: MoldUDP64 session-change history. A feed fault clears bits 0, 2, and 3. |
| `0x00B4` | `FEED_GAP_COUNT` | RO | Sequence-gap packets observed since the current counter baseline. |
| `0x00B8` | `FEED_SUPPRESSED_EVENT_COUNT` | RO | Events suppressed while the feed guard is unhealthy or handling a gap packet. |
| `0x00BC` | `CMAC_AXIS_FIFO` | RO | Bits 15:0: current packet-buffer beat occupancy. Bits 31:16: maximum occupancy observed since reset. |
| `0x00C0` | `CMAC_AXIS_ACCEPTED` | RO | Complete CMAC AXIS packets accepted since the current counter baseline. |
| `0x00C4` | `CMAC_AXIS_OVERFLOW` | RO | CMAC AXIS packets discarded after packet-buffer overflow since the current counter baseline. |
| `0x00C8` | `CMAC_AXIS_DROPPED_BEATS` | RO | Beats discarded while dropping an overflowing CMAC AXIS packet since the current counter baseline. |
| `0x00CC` | `FEED_IDLE_CYCLES` | RO | Saturating cycle count since the last complete CMAC AXIS packet. The count runs while the feed is healthy or rebuilding and freezes while faulted. |
| `0x00D0` | `FEED_TIMEOUT_CYCLES` | RW | Feed-liveness threshold in parser clock cycles. Zero disables the watchdog. Changing the value restarts the interval. |
| `0x00D4` | `FEED_TIMEOUT_COUNT` | RO | Feed-liveness timeouts observed since the current counter baseline. |
| `0x00D8` | `FEED_ACTIVATION_REJECT_COUNT` | RO | Activation requests rejected because the feed was not rebuilding or rebuild traffic had not yet applied an event. |
| `0x00DC` | `FEED_SESSION_CHANGE_COUNT` | RO | Unexpected MoldUDP64 session changes observed since the current counter baseline. |

Writing `CONTROL[2]` clears bounded book state, clears the parser's MoldUDP64
session and sequence expectations, and enters rebuild mode. The first replay
packet establishes new session and sequence baselines. Rebuild events update the books while
external quotes remain suppressed. After replay or snapshot processing is
complete, software waits for `FEED_STATUS[3]`, then writes `CONTROL[3]` to mark
the feed healthy and expose subsequent quotes. Activation outside rebuild or
before any rebuild event has applied is rejected, leaves the feed state
unchanged, and increments `FEED_ACTIVATION_REJECT_COUNT`. Bridge overflow
invalidates the feed immediately; software can distinguish that cause with
`STATUS[6]` and
`CMAC_AXIS_OVERFLOW`. An unexpected session change also invalidates the feed,
even when its sequence is contiguous, and is reported by `STATUS[10]`,
`FEED_STATUS[5]`, and `FEED_SESSION_CHANGE_COUNT`. Packet inactivity also
invalidates the guarded production path when `FEED_IDLE_CYCLES` reaches
`FEED_TIMEOUT_CYCLES`; its default is
`322400000` cycles, approximately one second at the native 322.4 MHz clock.
Recovery, activation, and timeout-configuration writes restart the idle
interval. Recovery does not erase fault history. Writing `CONTROL[1]` updates
the software-visible parser, feed, CMAC AXIS, timeout, activation-rejection,
and session-change counter baselines.
The CMAC AXIS FIFO high-water mark is a since-reset value and is not changed by
`CONTROL[1]`.

Recovery is an idle-boundary operation. Software should stop ingress and wait
for `CMAC_AXIS_FIFO[15:0]` and `EVENT_FIFO_STATUS[31:16]` to reach zero before
writing `CONTROL[2]`. This keeps pre-fault buffered work out of the rebuild
stream without resetting parser counters or AXI-Lite configuration.

The event payload still exits through the normalized event stream. A future
software-only demo wrapper may add memory-mapped event-data pop registers, but
the pre-hardware production path keeps the high-rate event data on ready/valid
streaming signals.

## Planned Extensions

Future hardware wrappers can add separate ingress beat, ingress packet,
ingress backpressure, and frontend-specific counters if the parser is split
across multiple independently clocked blocks. The current implemented
pre-hardware system keeps those observations at the integrated parser/FIFO
boundary.
