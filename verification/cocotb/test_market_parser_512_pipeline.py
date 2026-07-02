from pathlib import Path
import random
from typing import List

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
from cocotbext.axi import AxiStreamFrame


CLK_PERIOD_NS = 4
MIXED_EVENTS = 8
FLAG_MALFORMED = 0x02


def load_hex_bytes(path: Path) -> bytes:
    return bytes(int(line.strip(), 16) for line in path.read_text().splitlines() if line.strip())


def load_hex_words(path: Path) -> List[int]:
    return [int(line.strip(), 16) for line in path.read_text().splitlines() if line.strip()]


def build_bad_frame_packet() -> bytes:
    packet = bytearray(128)
    packet[0:10] = b"SIM0000001"
    packet[17] = 20
    packet[19] = 1
    packet[21] = 12
    packet[22] = ord("S")
    for idx in range(23, 34):
        packet[idx] = 0x11
    return bytes(packet[:34])


def build_truncated_packet() -> bytes:
    packet = bytearray(128)
    packet[0:10] = b"SIM0000001"
    packet[17] = 21
    packet[19] = 1
    packet[21] = 40
    packet[22] = ord("A")
    for idx in range(23, 40):
        packet[idx] = 0x22
    return bytes(packet[:40])


def event_flags(event_word: int) -> int:
    return (event_word >> 232) & 0xFF


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


async def send_axis_packet(dut, packet: bytes, max_gap: int = 2, bad_frame: bool = False):
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
        dut.s_axis_rx_tuser_bad_frame.value = int(bad_frame and offset == 0)

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
        for _ in range(random.randint(0, max_gap)):
            await RisingEdge(dut.clk)


async def send_repeated_packets(dut, packet: bytes, count: int, max_gap: int):
    for _ in range(count):
        await send_axis_packet(dut, packet, max_gap=max_gap)


async def collect_events(dut, count: int) -> List[int]:
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
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    vector_dir = Path(__file__).resolve().parents[1] / "vectors"
    packet = load_hex_bytes(vector_dir / "mixed_messages_packet.hex")
    expected = load_hex_words(vector_dir / "expected_events.hex")[2 : 2 + MIXED_EVENTS]

    await reset_dut(dut)

    sender = cocotb.start_soon(send_axis_packet(dut, packet))
    events = await collect_events(dut, MIXED_EVENTS)
    await sender
    await Timer(1, unit="ns")

    assert events == expected
    assert int(dut.packet_count.value) == 1
    assert int(dut.descriptor_count.value) == MIXED_EVENTS
    assert int(dut.event_count.value) == MIXED_EVENTS


@cocotb.test()
async def repeated_mixed_packets_randomized(dut):
    random.seed(17)
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    vector_dir = Path(__file__).resolve().parents[1] / "vectors"
    packet = load_hex_bytes(vector_dir / "mixed_messages_packet.hex")
    expected_one = load_hex_words(vector_dir / "expected_events.hex")[2 : 2 + MIXED_EVENTS]
    packet_count = 5
    expected = expected_one * packet_count

    await reset_dut(dut)

    sender = cocotb.start_soon(send_repeated_packets(dut, packet, packet_count, max_gap=3))
    events = await collect_events(dut, packet_count * MIXED_EVENTS)
    await sender
    await Timer(1, unit="ns")

    assert events == expected
    assert int(dut.packet_count.value) == packet_count
    assert int(dut.descriptor_count.value) == packet_count * MIXED_EVENTS
    assert int(dut.event_count.value) == packet_count * MIXED_EVENTS
    assert int(dut.extractor_error_count.value) == packet_count


@cocotb.test()
async def malformed_packets_raise_flags(dut):
    random.seed(23)
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    await reset_dut(dut)
    sender = cocotb.start_soon(send_axis_packet(dut, build_bad_frame_packet(), max_gap=0, bad_frame=True))
    events = await collect_events(dut, 1)
    await sender
    assert event_flags(events[0]) & FLAG_MALFORMED
    assert int(dut.packet_count.value) == 1
    assert int(dut.event_count.value) == 1
    assert int(dut.extractor_error_count.value) == 1
    assert int(dut.bad_frame_count.value) == 1

    await reset_dut(dut)
    sender = cocotb.start_soon(send_axis_packet(dut, build_truncated_packet(), max_gap=1))
    events = await collect_events(dut, 1)
    await sender
    assert event_flags(events[0]) & FLAG_MALFORMED
    assert int(dut.packet_count.value) == 1
    assert int(dut.event_count.value) == 1
    assert int(dut.extractor_error_count.value) == 1
