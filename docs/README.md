# Documentation Guide

The repository root README is the short project overview. These documents
capture stable interfaces, behavior, and measured evidence without generated
Vivado output or machine-specific setup.

## Architecture

- [Architecture](architecture.md): parser dataflow and production boundaries.
- [High-speed profiles](high_speed_profiles.md): supported stream widths and
  512-bit implementation path.
- [100G readiness](100g_readiness.md): implemented scope and remaining
  production qualification.

## Feed And Book State

- [Redundant feeds](redundant_feeds.md): packet-atomic A/B arbitration,
  deduplication, and failover.
- [Top of book](top_of_book.md): single-symbol book behavior.
- [Multi-symbol top of book](multi_symbol_top_of_book.md): guarded four-symbol
  state and recovery.
- [Strategy top](strategy_top.md): packet-to-quote integration.

## Trading Path

- [Decision engine](decision_engine.md): quote-to-intent policy and risk.
- [Order lifecycle](order_lifecycle.md): client IDs, acknowledgments, fills,
  cancels, and position updates.
- [Egress risk](egress_risk.md): final independent command checks.
- [OUCH gateway](ouch5_gateway.md): OUCH encoding and SoupBinTCP logical
  session handling.
- [Order latency](order_latency.md): order-ID-correlated latency telemetry.

## Integration And Control

- [CMAC integration](cmac_integration.md): CAUI-4 AXIS boundary, board harness,
  routed result, and license limitation.
- [Register map](register_map.md): parser and feed-health control/status.

## Results And Reproduction

- [Timing matrix](timing_matrix.md): measured OOC and routed results.
- [Implementation timing](implementation_timing.md): non-project Vivado flow
  and report conventions.
- [References](references.md): protocol and FPGA source material.
- [Project pitch](project_pitch.md): concise explanation and honest limits.
