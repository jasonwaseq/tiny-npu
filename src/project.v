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
  wire [1:0] class_out;
  wire busy;
  wire valid;
  wire [3:0] confidence;
  wire [6:0] hidden_debug;

  reg start_prev;

  assign start_pulse = uio_in[0] & ~start_prev;

  always @(posedge clk) begin
    if (!rst_n) begin
      start_prev <= 1'b0;
    end else begin
      start_prev <= uio_in[0];
    end
  end

    serial_mlp_core core (
      .clk(clk),
      .rst_n(rst_n),
      .start_pulse(start_pulse),
      .x_in(ui_in),
      .class_out(class_out),
      .busy(busy),
      .valid(valid),
      .confidence(confidence),
      .hidden_debug(hidden_debug)
  );

    assign uo_out = {confidence, busy, valid, class_out};
    assign uio_out = {hidden_debug, 1'b0};
    assign uio_oe  = 8'b11111110;

  wire _unused = &{ena, 1'b0};

endmodule

module serial_mlp_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start_pulse,
    input  wire [7:0] x_in,
    output reg  [1:0] class_out,
    output wire       busy,
    output wire       valid,
    output reg  [3:0] confidence,
    output wire [6:0] hidden_debug
);

  localparam [1:0] ST_IDLE   = 2'd0;
  localparam [1:0] ST_HIDDEN = 2'd1;
  localparam [1:0] ST_OUTPUT = 2'd2;
  localparam [1:0] ST_DONE   = 2'd3;

  localparam [7:0] H0_MASK = 8'b11110000;
  localparam [7:0] H1_MASK = 8'b11001100;
  localparam [7:0] H2_MASK = 8'b10101010;
  localparam [7:0] H3_MASK = 8'b11101001;
  localparam [7:0] H4_MASK = 8'b00001111;
  localparam [7:0] H5_MASK = 8'b00110011;
  localparam [7:0] H6_MASK = 8'b01010101;
  localparam [7:0] H7_MASK = 8'b10011100;

  localparam [3:0] H0_THRESH = 4'd4;
  localparam [3:0] H1_THRESH = 4'd4;
  localparam [3:0] H2_THRESH = 4'd4;
  localparam [3:0] H3_THRESH = 4'd5;
  localparam [3:0] H4_THRESH = 4'd4;
  localparam [3:0] H5_THRESH = 4'd4;
  localparam [3:0] H6_THRESH = 4'd4;
  localparam [3:0] H7_THRESH = 4'd5;

  localparam [7:0] O0_MASK = 8'b11001010;
  localparam [7:0] O1_MASK = 8'b10110100;
  localparam [7:0] O2_MASK = 8'b01101100;
  localparam [7:0] O3_MASK = 8'b10010111;

  reg [1:0] state;
  reg [2:0] bit_index;

  reg [7:0] x_shift;

  reg [7:0] h0_w_shift;
  reg [7:0] h1_w_shift;
  reg [7:0] h2_w_shift;
  reg [7:0] h3_w_shift;
  reg [7:0] h4_w_shift;
  reg [7:0] h5_w_shift;
  reg [7:0] h6_w_shift;
  reg [7:0] h7_w_shift;

  reg [3:0] h0_score;
  reg [3:0] h1_score;
  reg [3:0] h2_score;
  reg [3:0] h3_score;
  reg [3:0] h4_score;
  reg [3:0] h5_score;
  reg [3:0] h6_score;
  reg [3:0] h7_score;

  reg [7:0] hidden_bits;
  reg [7:0] hidden_shift;

  reg [7:0] o0_w_shift;
  reg [7:0] o1_w_shift;
  reg [7:0] o2_w_shift;
  reg [7:0] o3_w_shift;

  reg [3:0] o0_score;
  reg [3:0] o1_score;
  reg [3:0] o2_score;
  reg [3:0] o3_score;

  reg [1:0] class_next;
  reg [3:0] confidence_next;

  wire h0_match = (x_shift[0] == h0_w_shift[0]);
  wire h1_match = (x_shift[0] == h1_w_shift[0]);
  wire h2_match = (x_shift[0] == h2_w_shift[0]);
  wire h3_match = (x_shift[0] == h3_w_shift[0]);
  wire h4_match = (x_shift[0] == h4_w_shift[0]);
  wire h5_match = (x_shift[0] == h5_w_shift[0]);
  wire h6_match = (x_shift[0] == h6_w_shift[0]);
  wire h7_match = (x_shift[0] == h7_w_shift[0]);

  wire [3:0] h0_score_next = h0_score + {3'b000, h0_match};
  wire [3:0] h1_score_next = h1_score + {3'b000, h1_match};
  wire [3:0] h2_score_next = h2_score + {3'b000, h2_match};
  wire [3:0] h3_score_next = h3_score + {3'b000, h3_match};
  wire [3:0] h4_score_next = h4_score + {3'b000, h4_match};
  wire [3:0] h5_score_next = h5_score + {3'b000, h5_match};
  wire [3:0] h6_score_next = h6_score + {3'b000, h6_match};
  wire [3:0] h7_score_next = h7_score + {3'b000, h7_match};

  wire h0_bit_next = (h0_score_next >= H0_THRESH);
  wire h1_bit_next = (h1_score_next >= H1_THRESH);
  wire h2_bit_next = (h2_score_next >= H2_THRESH);
  wire h3_bit_next = (h3_score_next >= H3_THRESH);
  wire h4_bit_next = (h4_score_next >= H4_THRESH);
  wire h5_bit_next = (h5_score_next >= H5_THRESH);
  wire h6_bit_next = (h6_score_next >= H6_THRESH);
  wire h7_bit_next = (h7_score_next >= H7_THRESH);

  wire [7:0] hidden_next = {
    h7_bit_next, h6_bit_next, h5_bit_next, h4_bit_next,
    h3_bit_next, h2_bit_next, h1_bit_next, h0_bit_next
  };

  wire o0_match = (hidden_shift[0] == o0_w_shift[0]);
  wire o1_match = (hidden_shift[0] == o1_w_shift[0]);
  wire o2_match = (hidden_shift[0] == o2_w_shift[0]);
  wire o3_match = (hidden_shift[0] == o3_w_shift[0]);

  wire [3:0] o0_score_next = o0_score + {3'b000, o0_match};
  wire [3:0] o1_score_next = o1_score + {3'b000, o1_match};
  wire [3:0] o2_score_next = o2_score + {3'b000, o2_match};
  wire [3:0] o3_score_next = o3_score + {3'b000, o3_match};

  assign busy = (state == ST_HIDDEN) || (state == ST_OUTPUT);
  assign valid = (state == ST_DONE);
  assign hidden_debug = hidden_bits[6:0];

  always @* begin
    class_next = 2'd0;
    confidence_next = o0_score_next;

    if (o1_score_next >= confidence_next) begin
      class_next = 2'd1;
      confidence_next = o1_score_next;
    end

    if (o2_score_next >= confidence_next) begin
      class_next = 2'd2;
      confidence_next = o2_score_next;
    end

    if (o3_score_next >= confidence_next) begin
      class_next = 2'd3;
      confidence_next = o3_score_next;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      bit_index <= 3'd0;
      x_shift <= 8'h00;
      h0_w_shift <= 8'h00;
      h1_w_shift <= 8'h00;
      h2_w_shift <= 8'h00;
      h3_w_shift <= 8'h00;
      h4_w_shift <= 8'h00;
      h5_w_shift <= 8'h00;
      h6_w_shift <= 8'h00;
      h7_w_shift <= 8'h00;
      h0_score <= 4'd0;
      h1_score <= 4'd0;
      h2_score <= 4'd0;
      h3_score <= 4'd0;
      h4_score <= 4'd0;
      h5_score <= 4'd0;
      h6_score <= 4'd0;
      h7_score <= 4'd0;
      hidden_bits <= 8'h00;
      hidden_shift <= 8'h00;
      o0_w_shift <= 8'h00;
      o1_w_shift <= 8'h00;
      o2_w_shift <= 8'h00;
      o3_w_shift <= 8'h00;
      o0_score <= 4'd0;
      o1_score <= 4'd0;
      o2_score <= 4'd0;
      o3_score <= 4'd0;
      class_out <= 2'd0;
      confidence <= 4'd0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (start_pulse) begin
            x_shift <= x_in;
            h0_w_shift <= H0_MASK;
            h1_w_shift <= H1_MASK;
            h2_w_shift <= H2_MASK;
            h3_w_shift <= H3_MASK;
            h4_w_shift <= H4_MASK;
            h5_w_shift <= H5_MASK;
            h6_w_shift <= H6_MASK;
            h7_w_shift <= H7_MASK;
            h0_score <= 4'd0;
            h1_score <= 4'd0;
            h2_score <= 4'd0;
            h3_score <= 4'd0;
            h4_score <= 4'd0;
            h5_score <= 4'd0;
            h6_score <= 4'd0;
            h7_score <= 4'd0;
            hidden_bits <= 8'h00;
            hidden_shift <= 8'h00;
            o0_score <= 4'd0;
            o1_score <= 4'd0;
            o2_score <= 4'd0;
            o3_score <= 4'd0;
            bit_index <= 3'd0;
            state <= ST_HIDDEN;
          end
        end

        ST_HIDDEN: begin
          x_shift <= {1'b0, x_shift[7:1]};
          h0_w_shift <= {1'b0, h0_w_shift[7:1]};
          h1_w_shift <= {1'b0, h1_w_shift[7:1]};
          h2_w_shift <= {1'b0, h2_w_shift[7:1]};
          h3_w_shift <= {1'b0, h3_w_shift[7:1]};
          h4_w_shift <= {1'b0, h4_w_shift[7:1]};
          h5_w_shift <= {1'b0, h5_w_shift[7:1]};
          h6_w_shift <= {1'b0, h6_w_shift[7:1]};
          h7_w_shift <= {1'b0, h7_w_shift[7:1]};
          h0_score <= h0_score_next;
          h1_score <= h1_score_next;
          h2_score <= h2_score_next;
          h3_score <= h3_score_next;
          h4_score <= h4_score_next;
          h5_score <= h5_score_next;
          h6_score <= h6_score_next;
          h7_score <= h7_score_next;
          bit_index <= bit_index + 3'd1;

          if (bit_index == 3'd7) begin
            hidden_bits <= hidden_next;
            hidden_shift <= hidden_next;
            o0_w_shift <= O0_MASK;
            o1_w_shift <= O1_MASK;
            o2_w_shift <= O2_MASK;
            o3_w_shift <= O3_MASK;
            bit_index <= 3'd0;
            state <= ST_OUTPUT;
          end
        end

        ST_OUTPUT: begin
          hidden_shift <= {1'b0, hidden_shift[7:1]};
          o0_w_shift <= {1'b0, o0_w_shift[7:1]};
          o1_w_shift <= {1'b0, o1_w_shift[7:1]};
          o2_w_shift <= {1'b0, o2_w_shift[7:1]};
          o3_w_shift <= {1'b0, o3_w_shift[7:1]};
          o0_score <= o0_score_next;
          o1_score <= o1_score_next;
          o2_score <= o2_score_next;
          o3_score <= o3_score_next;
          bit_index <= bit_index + 3'd1;

          if (bit_index == 3'd7) begin
            class_out <= class_next;
            confidence <= confidence_next;
            bit_index <= 3'd0;
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

endmodule
