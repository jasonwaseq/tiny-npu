<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This design is a fixed-weight 8-input binary neural classifier. On a rising edge of `uio_in[0]`, the core captures `ui_in[7:0]` as the feature vector, loads an internal 8-bit weight mask, and then evaluates one bit per clock using bitwise equality as the XNOR step. Each matching bit increments a 4-bit score. After 8 cycles, the score is compared against a 4-bit threshold and the result is latched onto `uo_out[0]` as the class bit.

The remaining output pins provide status and debug visibility: `uo_out[1]` is busy, `uo_out[2]` is valid, `uo_out[6:3]` show the running score, and `uo_out[7]` indicates a perfect 8/8 match.

## How to test

Drive the 8-bit input vector on `ui_in[7:0]`, pulse `uio_in[0]` high for one clock to start inference, and wait for `uo_out[2]` to assert valid. The class result appears on `uo_out[0]`, and the score/debug bits can be read from `uo_out[6:3]` and `uo_out[7]`.

For simulation, run the cocotb testbench in `test/`.

## External hardware

None required. A simple demo can use switches for `ui_in[7:0]`, one pushbutton for `uio_in[0]`, and LEDs or a logic analyzer on the outputs.
