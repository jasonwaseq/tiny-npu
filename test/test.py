# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


HIDDEN_MASKS = [
    0b11110000,
    0b11001100,
    0b10101010,
    0b11101001,
    0b00001111,
    0b00110011,
    0b01010101,
    0b10011100,
]
HIDDEN_THRESHOLDS = [4, 4, 4, 5, 4, 4, 4, 5]

OUTPUT_MASKS = [
    0b11001010,
    0b10110100,
    0b01101100,
    0b10010111,
]


def popcount_matches(a: int, b: int) -> int:
    score = 0
    for bit in range(8):
        score += int(((a >> bit) & 1) == ((b >> bit) & 1))
    return score


def hidden_layer(vector: int):
    bits = 0
    for index, (mask, threshold) in enumerate(zip(HIDDEN_MASKS, HIDDEN_THRESHOLDS)):
        score = popcount_matches(vector, mask)
        bits |= int(score >= threshold) << index
    return bits


def output_layer(hidden_bits: int):
    scores = []
    for mask in OUTPUT_MASKS:
        scores.append(popcount_matches(hidden_bits, mask))

    class_index = 0
    confidence = scores[0]
    for index in range(1, 4):
        if scores[index] >= confidence:
            class_index = index
            confidence = scores[index]
    return class_index, confidence, scores


def golden_model(vector: int):
    hidden_bits = hidden_layer(vector)
    class_index, confidence, scores = output_layer(hidden_bits)
    return hidden_bits, class_index, confidence, scores


def decode_outputs(value: int):
    class_index = value & 0x3
    valid = (value >> 2) & 1
    busy = (value >> 3) & 1
    confidence = (value >> 4) & 0xF
    return class_index, valid, busy, confidence


async def run_inference(dut, vector: int):
    dut.ui_in.value = vector
    dut.uio_in.value = 1

    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0

    for _ in range(20):
        await ClockCycles(dut.clk, 1)
        class_index, valid, busy, confidence = decode_outputs(int(dut.uo_out.value))
        if valid:
            return class_index, busy, valid, confidence, int(dut.uio_out.value)

    raise AssertionError(f"valid did not assert for vector {vector:#04x}")


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    assert int(dut.uo_out.value) == 0

    sample_vector = 0b11010110
    expected_hidden, expected_class, expected_confidence, _ = golden_model(sample_vector)
    class_index, busy, valid, confidence, hidden_debug = await run_inference(dut, sample_vector)

    assert valid == 1
    assert busy == 0
    assert class_index == expected_class
    assert confidence == expected_confidence
    assert hidden_debug >> 1 == (expected_hidden & 0x7F)
    assert hidden_debug & 1 == 0

    for vector in range(256):
        expected_hidden, expected_class, expected_confidence, _ = golden_model(vector)
        class_index, busy, valid, confidence, hidden_debug = await run_inference(dut, vector)

        assert valid == 1
        assert busy == 0
        assert class_index == expected_class
        assert confidence == expected_confidence
        assert hidden_debug >> 1 == (expected_hidden & 0x7F)
        assert hidden_debug & 1 == 0

    edge_vectors = [0b11010110, 0b11010111, 0b10010110, 0b01010110]
    for vector in edge_vectors:
        expected_hidden, expected_class, expected_confidence, _ = golden_model(vector)
        class_index, busy, valid, confidence, hidden_debug = await run_inference(dut, vector)

        assert class_index == expected_class
        assert confidence == expected_confidence
        assert hidden_debug >> 1 == (expected_hidden & 0x7F)
        assert hidden_debug & 1 == 0
