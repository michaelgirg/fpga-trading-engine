# cocotb Verification

This folder is an optional Python verification layer for the 512-bit pipeline.
It complements the deterministic Questa/SystemVerilog regression; it does not
replace it.

Install the Python dependencies in a virtual environment:

```powershell
pip install -r verification/cocotb/requirements.txt
```

Run with a cocotb-supported simulator, for example Questa:

```powershell
cd verification/cocotb
make SIM=questa
```

The starter test drives the mixed MoldUDP64/ITCH vector over the 512-bit stream,
randomizes input gaps and output `event_ready`, and compares normalized events
against `verification/vectors/expected_events.hex`.
