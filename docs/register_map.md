# Register Map

## Goal

This register map is the control/status surface for a Zynq PS, PCIe host, or
management block. The pre-hardware RTL now implements this map in
`market_parser_axi_lite_regs.sv` and connects it to the FIFO-backed 512-bit
parser through `market_parser_512_system.sv`.

## Control And Status

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0000` | `CONTROL` | RW | Bit 0: enable parser. Bit 1: clear sticky flags/counters through software-visible baselines. |
| `0x0004` | `STATUS` | RO | Bit 0: parser enabled. Bit 1: ingress backpressured. Bit 2: event FIFO non-empty. Bit 3: event FIFO full. Bit 4: event output valid. |
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
