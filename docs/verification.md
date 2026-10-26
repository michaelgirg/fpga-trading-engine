# Verification

## Primary Regression

From `verification/`, run `vsim -c -do run_questa.do`. The script compiles the
RTL and benches, then executes 43 configurations: the original 38, three
seeded complete-gateway runs, and two book-throughput configurations. A final
`REGRESSION COMPLETE` line records the number of passing configurations.

Every self-checking bench calls `$fatal` when its failure count is nonzero.
The shared runner accepts normal `$finish` completion and rejects unexpected
stops, fatal failures, and tests that do not finish within 5 ms of simulated
time. Each passing configuration emits `REGRESSION PASS`.

The runner's failure handling can be tested independently on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File verification/test_questa_runner.ps1
```

The self-test checks normal completion, an injected scoreboard failure, an
explicit fatal failure, an infinite wait, and an unexpected `$stop`. Only
normal completion must return zero. Each probe must reach its identifying
marker, so a compile or license failure cannot masquerade as an expected
negative result. Logs and probe libraries stay under ignored `build/`.

## Seeded Packet-To-Order Scenarios

`market_parser_100g_ouch5_top_tb` retains its deterministic smoke test and adds
parameterized `SEED` and `STRESS_ROUNDS` configurations. The default regression
runs seeds 7, 17, and 101 with 32 scenarios each.

Each seed covers the Cartesian product of four response modes, four symbols,
and buy/sell direction. Explicit scenario counters require every combination
to execute. Response modes are:

- Venue rejection of a new order.
- Acknowledgment followed by a complete fill.
- Acknowledgment followed by two partial fills that exhaust the order.
- Acknowledgment, partial fill, kill-switch cancellation, and cancel response.

The bench generates Ethernet/IPv4/UDP/MoldUDP64 packets containing two ITCH
Add messages. Prices, displayed quantities, order size, inter-beat ingress
gaps, Soup output stalls, venue delays, and the gap within a two-beat Accepted
response vary through a private deterministic PRNG. Order bytes are checked
against the expected imbalance decision and configured symbol mapping.

The scoreboard checks signed position, unaffected symbols, remaining working
state, exact lifecycle/protocol counters, first-response latency samples,
zero telemetry anomalies, and zero ingress loss. A clocked checker requires
Soup output valid, data, keep, and last to remain stable during backpressure.

Each scenario resets the DUT and creates one order. These tests do not yet
exercise persistent-session order-ID growth, concurrent working symbols,
arbitrary malformed traffic, or a Python venue driving the RTL. The Python
adversarial exchange tests remain a separate software-model regression.

Questa 2021.2 requires `-voptargs=+acc` for these stress configurations to avoid
an optimizer crash. The regression applies that option to the seeded runs.

## Packet-To-Order Latency

Passive testbench timestamps record the first accepted CMAC beat, final CMAC
beat, and successful logical Soup transfer of the generated Enter Order.
Per-scenario cycle counts, per-seed minima/maxima, and a four-bucket histogram
are printed. The interval includes configured ingress gaps and output stalls.
It ends above TCP and excludes PHY, network, transport, and real venue time.

| Seed | Orders | First RX beat to Soup transfer | Final RX beat to Soup transfer |
| ---: | ---: | ---: | ---: |
| 7 | 32 | 77-101 clocks | 71-89 clocks |
| 17 | 32 | 76-102 clocks | 71-90 clocks |
| 101 | 32 | 79-102 clocks | 71-90 clocks |

These are the configured two-message packets with eight-entry books and
deliberate output stalls. They are workload measurements rather than latency
bounds for arbitrary packets or the default sixteen-entry book configuration.

This complements the synthesizable monitor in `order_latency.md`, whose
starting boundary is the risk-approved command rather than the market packet.

## Book Throughput Benchmark

`market_parser_book_throughput_tb` continuously offers one Add followed by 31
exact-reference Replace events to a single-symbol book. The quote sink is
always ready. Every quote's best price, aggregate quantity, timestamp, and
empty ask are checked, along with accepted/applied/ignored/overflow counters.

| Table depth | Events | Accept-to-quote cycles | Accepted-update interval | Nominal rate at 3.102 ns |
| ---: | ---: | ---: | ---: | ---: |
| 8 | 32 | 19 | 19 clocks | 16.967 million updates/s |
| 16 | 32 | 35 | 35 clocks | 9.211 million updates/s |

These are simulation measurements for a continuously offered single-symbol
replacement workload. They expose the iterative lookup/recompute cost and
do not establish sustained 100G throughput, multi-symbol aggregate throughput,
or live-feed performance.

## Software Models

```bash
python -m unittest verification/test_exchange_simulator.py \
  verification/test_signal_engine_golden.py
```

The 11 Python tests include deterministic and seeded-adversarial exchange
behavior, share conservation over 1,500 orders, 120 cancellations, and the
quote-policy reference model. Parser cocotb tests are an additional optional
layer documented in `verification/cocotb/README.md`.
