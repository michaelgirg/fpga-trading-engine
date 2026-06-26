# Register Map

## Goal

This register map is the planned control/status surface for a Zynq PS, PCIe
host, or management block. The current RTL exposes most counters as ports; a
future AXI-Lite wrapper should map those ports to these addresses.

## Control And Status

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0000` | `CONTROL` | RW | Bit 0: enable parser. Bit 1: clear sticky flags/counters. |
| `0x0004` | `STATUS` | RO | Bit 0: parser enabled. Bit 1: ingress backpressured. Bit 2: descriptor valid. |
| `0x0008` | `BUILD_ID` | RO | Optional build/version identifier. |

## Parser Counters

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0010` | `PACKET_COUNT` | RO | MoldUDP64 packet frames accepted by parser path. |
| `0x0014` | `MESSAGE_COUNT` | RO | ITCH messages processed by parser path. |
| `0x0018` | `EVENT_COUNT` | RO | Normalized events emitted by parser path. |
| `0x001C` | `ERROR_COUNT` | RO | Parser error counter. |
| `0x0020` | `EXPECTED_SEQUENCE_LO` | RO | Lower 32 bits of next expected MoldUDP64 sequence. |
| `0x0024` | `EXPECTED_SEQUENCE_HI` | RO | Upper 32 bits of next expected MoldUDP64 sequence. |
| `0x0028` | `PACKET_SEQUENCE_LO` | RO | Lower 32 bits of last packet sequence observed. |
| `0x002C` | `PACKET_SEQUENCE_HI` | RO | Upper 32 bits of last packet sequence observed. |

## Sticky Flags

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0030` | `ERROR_FLAGS` | RO/W1C | Bit 0: gap. Bit 1: malformed. Bit 2: unknown message type. |

## 100G Ingress Counters

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0040` | `INGRESS_BEAT_COUNT` | RO | 512-bit RX beats accepted. |
| `0x0044` | `INGRESS_PACKET_COUNT` | RO | RX frames accepted by ingress shell. |
| `0x0048` | `INGRESS_BACKPRESSURE_COUNT` | RO | Cycles with RX valid high and ready low. |
| `0x004C` | `INGRESS_BAD_FRAME_COUNT` | RO | RX beats marked bad by MAC sideband. |
| `0x0050` | `INGRESS_FIFO_LEVEL` | RO | Current ingress FIFO fill level. |

## 512-Bit Frontend Counters

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0060` | `FRONTEND_PACKET_COUNT` | RO | Packets decoded by descriptor frontend. |
| `0x0064` | `FRONTEND_DESCRIPTOR_COUNT` | RO | ITCH message descriptors emitted. |
| `0x0068` | `FRONTEND_ERROR_COUNT` | RO | Descriptor frontend errors. |

## Event Output

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x0080` | `EVENT_FIFO_STATUS` | RO | Bit 0: empty. Bit 1: full. Bits 31:16: level. |
| `0x0084` | `EVENT_FIFO_DATA_0` | RO | Event bits `[31:0]`. Reading should pop only after `DATA_7`. |
| `0x0088` | `EVENT_FIFO_DATA_1` | RO | Event bits `[63:32]`. |
| `0x008C` | `EVENT_FIFO_DATA_2` | RO | Event bits `[95:64]`. |
| `0x0090` | `EVENT_FIFO_DATA_3` | RO | Event bits `[127:96]`. |
| `0x0094` | `EVENT_FIFO_DATA_4` | RO | Event bits `[159:128]`. |
| `0x0098` | `EVENT_FIFO_DATA_5` | RO | Event bits `[191:160]`. |
| `0x009C` | `EVENT_FIFO_DATA_6` | RO | Event bits `[223:192]`. |
| `0x00A0` | `EVENT_FIFO_DATA_7` | RO | Event bits `[255:224]` and pop trigger. |
