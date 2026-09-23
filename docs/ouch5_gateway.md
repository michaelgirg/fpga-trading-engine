# OUCH 5.0 gateway

The source-only gateway extends the packet-to-command pipeline through an
exchange-facing protocol boundary:

1. `market_parser_100g_ouch5_top` produces risk-cleared order commands from the
   512-bit market-data path.
2. `market_parser_ouch5_codec` encodes visible DAY limit orders and full
   cancels using Nasdaq OUCH 5.0 fixed fields.
3. `market_parser_soupbintcp_client` wraps outbound OUCH messages in
   SoupBinTCP Unsequenced Data packets and extracts inbound OUCH messages from
   Sequenced Data packets.
4. Accepted, rejected, executed, and canceled responses return to the order
   lifecycle manager and position engine.

A two-entry registered command FIFO separates final risk from the protocol
gateway. Its input readiness depends only on registered occupancy, preventing
Soup or OUCH backpressure from becoming a combinational lifecycle timing path.

The Soup interface represents complete logical packets above TCP. Ethernet,
IP, TCP reliability, and socket establishment remain the responsibility of an
external host or transport offload block. Credentials and reconnect state are
runtime inputs; no exchange credentials are stored in the source tree.

## Implemented messages

Outbound OUCH:

- Enter Order (`O`), 47 bytes without optional appendages
- Cancel Order (`X`), 11 bytes with intended quantity zero for a full cancel

Inbound OUCH:

- Order Accepted (`A`)
- Order Rejected (`J`)
- Order Executed (`E`)
- Order Canceled (`C`)

The 64-bit internal order ID must fit the unsigned 32-bit OUCH UserRefNum. A
symbol-locate table maps feed stock locates to eight-character OUCH symbols.
Invalid IDs and unmapped symbols are rejected locally and reconciled through
the same lifecycle event path as venue rejects.

## Session behavior

The logical Soup layer generates Login Request, Client Heartbeat, Logout
Request, and Unsequenced Data packets. It consumes Login Accepted, Login
Rejected, Server Heartbeat, End Of Session, and Sequenced Data packets. Login
credentials, requested session, and requested sequence are supplied at runtime.
The compact routed harness registers its synthetic exchange-response stream
before the Soup client. This models a registered transport handoff and prevents
the responder FSM from becoming part of the session parser's timing path.
The 20-byte ASCII sequence field is formatted and parsed iteratively outside
the order datapath; every accepted Sequenced Data packet advances the stored
next sequence for reconnect. Trading remains disabled until login parsing
completes successfully.

A receive watchdog clears `session_active` after a configurable silent
interval even if client heartbeats continue to transmit. Transport loss,
logout, rejection, end-of-session, malformed sequence text, and watchdog
expiry all leave the command path fail-closed. New orders are blocked while
inactive; cancel attempts presented during an inactive session are retired
through a deterministic transport reject so they cannot stall lifecycle state.

An inbound OUCH Accepted response is 64 bytes and therefore spans two 512-bit
Soup beats after the three-byte Soup header. The deframer reconstructs this
case without truncation and supports backpressure on both protocol boundaries.

## Verification

The local Questa regression checks byte-exact Enter and Cancel encoding,
the 49-byte Login Request, login sequence parsing, reconnect state, client and
server heartbeats, logout, response extraction, malformed and unsupported
messages, AXI backpressure, one- and two-beat Soup responses, session loss,
watchdog expiry, transport rejects, command-FIFO saturation and ordering, and
exact telemetry counters.

`market_parser_100g_ouch5_top_tb` provides a deterministic closed-loop replay:
a multi-beat market packet generates an OUCH order, accepted and executed
responses return through Soup, and the resulting fill updates position while
retiring the working order. This test is a logical protocol model, not a live
Nasdaq certification test.

`market_parser_100g_ouch5_impl_harness` reproduces the same closed loop behind
a compact clock/reset/status boundary for routed implementation. Its internal
exchange responder emits a two-beat Accepted packet and an Executed packet, so
implementation cannot optimize away the Soup deframer or lifecycle feedback.

## U50 OOC Timing

The complete `market_parser_100g_ouch5_top` with client-generated session
control closes the 3.102 ns constraint on `xcu50-fsvh2104-2-e` with WNS
`+0.012 ns` and TNS `0.000 ns`. The passing 322.4 MHz result includes the packet
parser, guarded multi-symbol book, decision engine, lifecycle manager, final
risk guard, command FIFO, OUCH codec, Soup logical-packet boundary, and passive
order-path latency telemetry.

## Routed Implementation

The compact `market_parser_100g_ouch5_impl_harness` closes post-route at 3.102
ns / 322.4 MHz with WNS `+0.075 ns`, TNS `0.000 ns`, WHS `+0.010 ns`, and THS
`0.000 ns`. It uses 26,227 LUTs, 30,185 registers, 8.5 BRAM tiles, and zero
DSPs. This run includes client-generated login, heartbeat, logout, reconnect
sequence state, the full packet-to-OUCH path, acceptance/fill feedback, and
order-latency telemetry.
The harness is a deterministic logical exchange model above TCP, not a live
venue certification or hardware-traffic result.
