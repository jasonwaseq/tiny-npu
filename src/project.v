`default_nettype none

module tt_um_tiny_npu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire start_pulse;
  wire class_out;
  wire busy;
  wire valid;
  wire all_match;
  wire [3:0] score;

  reg start_prev;

  assign start_pulse = uio_in[0] & ~start_prev;

  always @(posedge clk) begin
    if (!rst_n) begin
      start_prev <= 1'b0;
    end else begin
      start_prev <= uio_in[0];
    end
  end

  serial_match_accum #(
      .WEIGHT_MASK(8'b11010110),
      .THRESHOLD(4'd5)
  ) core (
      .clk(clk),
      .rst_n(rst_n),
      .start_pulse(start_pulse),
      .x_in(ui_in),
      .class_out(class_out),
      .busy(busy),
      .valid(valid),
      .score(score),
      .all_match(all_match)
  );

  assign uo_out = {all_match, score, valid, busy, class_out};
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  wire _unused = &{ena, 1'b0};

endmodule

module serial_match_accum #(
    parameter [7:0] WEIGHT_MASK = 8'b11010110,
    parameter [3:0] THRESHOLD = 4'd5
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start_pulse,
    input  wire [7:0] x_in,
    output wire       class_out,
    output wire       busy,
    output wire       valid,
    output wire [3:0] score,
    output wire       all_match
);

  localparam [1:0] ST_IDLE = 2'd0;
  localparam [1:0] ST_RUN  = 2'd1;
  localparam [1:0] ST_DONE = 2'd2;

  reg [1:0] state;
  reg [7:0] x_shift;
  reg [7:0] w_shift;
  reg [2:0] bit_index;
  reg [3:0] score_reg;
  reg result_class_reg;

  wire match_bit = (x_shift[0] == w_shift[0]);
  wire [3:0] score_next = score_reg + {3'b000, match_bit};

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      x_shift <= 8'h00;
      w_shift <= 8'h00;
      bit_index <= 3'd0;
      score_reg <= 4'd0;
      result_class_reg <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (start_pulse) begin
            x_shift <= x_in;
            w_shift <= WEIGHT_MASK;
            bit_index <= 3'd0;
            score_reg <= 4'd0;
            state <= ST_RUN;
          end
        end

        ST_RUN: begin
          x_shift <= {1'b0, x_shift[7:1]};
          w_shift <= {1'b0, w_shift[7:1]};
          score_reg <= score_next;
          bit_index <= bit_index + 3'd1;

          if (bit_index == 3'd7) begin
            result_class_reg <= (score_next >= THRESHOLD);
            state <= ST_DONE;
          end
        end

        ST_DONE: begin
          state <= ST_IDLE;
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

  assign class_out = result_class_reg;
  assign busy = (state == ST_RUN);
  assign valid = (state == ST_DONE);
  assign score = score_reg;
  assign all_match = (score_reg == 4'd8);

endmodule
