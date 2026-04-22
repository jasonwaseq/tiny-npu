<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This design is a fixed-weight two-layer binary MLP. On a rising edge of `uio_in[0]`, the core captures `ui_in[7:0]` as the feature vector and then evaluates eight hidden neurons serially over 8 cycles. Each hidden neuron is an 8-bit match detector with its own threshold. The resulting 8 hidden activations are then fed into a second serial layer with four output heads, which selects the winning class and confidence score.

The output pins expose the 2-bit class index, `busy`, `valid`, and a 4-bit confidence score. The bidirectional pins `uio[7:1]` expose the hidden activation vector for debug and demo visibility.

## How to test

Drive the 8-bit input vector on `ui_in[7:0]`, pulse `uio_in[0]` high for one clock to start inference, and wait for `uo_out[2]` to assert valid. The class result appears on `uo_out[1:0]`, confidence on `uo_out[7:4]`, and the hidden activation debug vector is visible on `uio[7:1]`.

For simulation, run the cocotb testbench in `test/`.

## External hardware

None required. A simple demo can use switches for `ui_in[7:0]`, one pushbutton for `uio_in[0]`, and LEDs or a logic analyzer on the outputs.
