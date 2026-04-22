# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


WEIGHT_MASK = 0b11010110
THRESHOLD = 5


def golden_model(vector: int):
    score = 0
    for bit in range(8):
        input_bit = (vector >> bit) & 1
        weight_bit = (WEIGHT_MASK >> bit) & 1
        score += int(input_bit == weight_bit)
    return score >= THRESHOLD, score


def decode_outputs(value: int):
    class_bit = value & 1
    busy = (value >> 1) & 1
    valid = (value >> 2) & 1
    score = (value >> 3) & 0xF
    all_match = (value >> 7) & 1
    return class_bit, busy, valid, score, all_match


async def run_inference(dut, vector: int):
    dut.ui_in.value = vector
    dut.uio_in.value = 1

    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0

    for _ in range(12):
        await ClockCycles(dut.clk, 1)
        class_bit, busy, valid, score, all_match = decode_outputs(int(dut.uo_out.value))
        if valid:
            return class_bit, busy, valid, score, all_match

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
    expected_class, expected_score = golden_model(sample_vector)
    class_bit, busy, valid, score, all_match = await run_inference(dut, sample_vector)

    assert valid == 1
    assert busy == 0
    assert class_bit == int(expected_class)
    assert score == expected_score
    assert all_match == int(expected_score == 8)

    for vector in range(256):
        expected_class, expected_score = golden_model(vector)
        class_bit, busy, valid, score, all_match = await run_inference(dut, vector)

        assert valid == 1
        assert busy == 0
        assert class_bit == int(expected_class)
        assert score == expected_score
        assert all_match == int(expected_score == 8)

    edge_vectors = [0b11010110, 0b11010111, 0b10010110, 0b01010110]
    for vector in edge_vectors:
        expected_class, expected_score = golden_model(vector)
        class_bit, busy, valid, score, all_match = await run_inference(dut, vector)

        assert class_bit == int(expected_class)
        assert score == expected_score
        assert all_match == int(expected_score == 8)
