from pathlib import Path
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from cocotbext.axi import AxiStreamFrame


CLK_PERIOD_NS = 3.102
MIXED_EVENTS = 8


def load_hex_bytes(path: Path) -> bytes:
    return bytes(int(line.strip(), 16) for line in path.read_text().splitlines() if line.strip())


def load_hex_words(path: Path) -> list[int]:
    return [int(line.strip(), 16) for line in path.read_text().splitlines() if line.strip()]


async def reset_dut(dut):
    dut.rst.value = 1
    dut.s_axis_rx_tvalid.value = 0
    dut.s_axis_rx_tdata.value = 0
    dut.s_axis_rx_tkeep.value = 0
    dut.s_axis_rx_tlast.value = 0
    dut.s_axis_rx_tuser_bad_frame.value = 0
    dut.event_ready.value = 0
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)


async def send_axis_packet(dut, packet: bytes):
    frame = AxiStreamFrame(packet)
    offset = 0
    while offset < len(frame.tdata):
        beat = frame.tdata[offset : offset + 64]
        data = 0
        keep = 0
        for lane, value in enumerate(beat):
            data |= int(value) << (lane * 8)
            keep |= 1 << lane

        await FallingEdge(dut.clk)
        dut.s_axis_rx_tvalid.value = 1
        dut.s_axis_rx_tdata.value = data
        dut.s_axis_rx_tkeep.value = keep
        dut.s_axis_rx_tlast.value = int(offset + len(beat) >= len(frame.tdata))
        dut.s_axis_rx_tuser_bad_frame.value = 0

        while True:
            await RisingEdge(dut.clk)
            if int(dut.s_axis_rx_tready.value):
                break

        await FallingEdge(dut.clk)
        dut.s_axis_rx_tvalid.value = 0
        dut.s_axis_rx_tdata.value = 0
        dut.s_axis_rx_tkeep.value = 0
        dut.s_axis_rx_tlast.value = 0

        offset += len(beat)
        for _ in range(random.randint(0, 2)):
            await RisingEdge(dut.clk)


async def collect_events(dut, count: int) -> list[int]:
    events = []
    cycles = 0
    while len(events) < count and cycles < 1000:
        dut.event_ready.value = random.randint(0, 1)
        await RisingEdge(dut.clk)
        if int(dut.event_valid.value) and int(dut.event_ready.value):
            events.append(int(dut.event_data.value))
        cycles += 1

    dut.event_ready.value = 0
    assert len(events) == count, f"timed out collecting events: got {len(events)} expected {count}"
    return events


@cocotb.test()
async def mixed_packet_matches_golden_events(dut):
    random.seed(7)
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

    vector_dir = Path(__file__).resolve().parents[1] / "vectors"
    packet = load_hex_bytes(vector_dir / "mixed_messages_packet.hex")
    expected = load_hex_words(vector_dir / "expected_events.hex")[2 : 2 + MIXED_EVENTS]

    await reset_dut(dut)

    sender = cocotb.start_soon(send_axis_packet(dut, packet))
    events = await collect_events(dut, MIXED_EVENTS)
    await sender
    await Timer(1, units="ns")

    assert events == expected
    assert int(dut.packet_count.value) == 1
    assert int(dut.descriptor_count.value) == MIXED_EVENTS
    assert int(dut.event_count.value) == MIXED_EVENTS
