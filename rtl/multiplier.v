`include "systolic_config.vh"

// Signed fixed-point multiplier with saturation
//
// Performs signed fixed-point multiplication of two inputs with configurable fractional widths.
// Computes full-width product, applies fractional bit alignment via shift, and clamps result
// to output width using symmetric saturation. Supports configurable pipeline delay.
//
// Parameters:
//   INPUT_A_WIDTH: Bit width of first input operand
//   INPUT_B_WIDTH: Bit width of second input operand
//   INPUT_A_FRAC: Number of fractional bits in first input (Q format)
//   INPUT_B_FRAC: Number of fractional bits in second input (Q format)
//   OUTPUT_WIDTH: Bit width of output result
//   OUTPUT_FRAC: Number of fractional bits in output (Q format)
//   DELAY: Pipeline delay stages (default 3)
//
// Behavior:
//   - Multiplies a_in * b_in to produce full-width product (INPUT_A_WIDTH + INPUT_B_WIDTH bits)
//   - Shifts product right by (INPUT_A_FRAC + INPUT_B_FRAC - OUTPUT_FRAC) bits to align fractional points
//   - If shift is negative, shifts left instead
//   - Clamps shifted result to [MIN_VAL, MAX_VAL] using symmetric saturation
//   - Outputs result after DELAY clock cycles with done signal synchronized to output
//   - Respects stall signal to pause pipeline when asserted

module multiplier #(
    parameter INPUT_A_WIDTH = `SYSTOLIC_INPUT_WIDTH,
    parameter INPUT_B_WIDTH = `SYSTOLIC_INPUT_WIDTH,
    parameter INPUT_A_FRAC  = `SYSTOLIC_FRAC_WIDTH,
    parameter INPUT_B_FRAC  = `SYSTOLIC_FRAC_WIDTH,
    parameter OUTPUT_WIDTH  = `SYSTOLIC_RESULT_WIDTH,
    parameter OUTPUT_FRAC   = `SYSTOLIC_FRAC_WIDTH,
    parameter DELAY         = 3
)(
    input                               clk,
    input                               reset,
    input                               en,
    input                               stall,
    input      signed [INPUT_A_WIDTH-1:0] a_in,
    input      signed [INPUT_B_WIDTH-1:0] b_in,
    output     signed [OUTPUT_WIDTH-1:0] out,
    output                              done
);

    localparam integer EXT_WIDTH = INPUT_A_WIDTH + INPUT_B_WIDTH;

    reg signed [OUTPUT_WIDTH-1:0] mult;
    reg en_reg;

    localparam integer SHIFT_VALUE = INPUT_A_FRAC + INPUT_B_FRAC - OUTPUT_FRAC;
    localparam integer SHIFT_LEFT  = (SHIFT_VALUE < 0) ? -SHIFT_VALUE : 0;

    localparam signed [OUTPUT_WIDTH-1:0] MAX_VAL = {1'b0, {(OUTPUT_WIDTH-1){1'b1}}};
    localparam signed [OUTPUT_WIDTH-1:0] MIN_VAL = {1'b1, {(OUTPUT_WIDTH-1){1'b0}}};

    function automatic signed [OUTPUT_WIDTH-1:0] clamp_to_output;
        input signed [EXT_WIDTH-1:0] value;
        reg signed [EXT_WIDTH-1:0] max_ext;
        reg signed [EXT_WIDTH-1:0] min_ext;
        begin
            max_ext = {{(EXT_WIDTH-OUTPUT_WIDTH){MAX_VAL[OUTPUT_WIDTH-1]}}, MAX_VAL};
            min_ext = {{(EXT_WIDTH-OUTPUT_WIDTH){MIN_VAL[OUTPUT_WIDTH-1]}}, MIN_VAL};
            if (value > max_ext) begin
                clamp_to_output = MAX_VAL;
            end else if (value < min_ext) begin
                clamp_to_output = MIN_VAL;
            end else begin
                clamp_to_output = value[OUTPUT_WIDTH-1:0];
            end
        end
    endfunction

    wire signed [EXT_WIDTH-1:0] product_full = a_in * b_in;
    wire signed [EXT_WIDTH-1:0] product_shifted = (SHIFT_VALUE >= 0) ?
        (product_full >>> SHIFT_VALUE) :
        (product_full <<< SHIFT_LEFT);
    wire signed [OUTPUT_WIDTH-1:0] product_clamped = clamp_to_output(product_shifted);

    always @(posedge clk) begin
        if (reset) begin
            mult    <=  '0;
        end else if (!stall && en) begin
            mult <= product_clamped;
        end
    end

    genvar i;
    generate
        if (DELAY <= 1) begin
            assign out = mult;
            always @(posedge clk) begin
                if (reset) begin
                    en_reg <= '0;
                end else begin
                    en_reg <= (stall) ? en_reg : en;
                end
            end
            assign done = en_reg && ~reset;
        end
        else begin
            reg [OUTPUT_WIDTH-1:0] mult_delayed[0:DELAY-2];
            reg en_delayed[0:DELAY-2];
            always @(posedge clk) begin
                if (reset) begin
                    en_reg <= '0;
                end else begin
                    en_reg <= (stall) ? en_reg : en;
                end
            end
            for (i = 0; i < DELAY-1; i = i + 1) begin
                if (i == 0) begin
                    always @(posedge clk) begin
                        if (reset) begin
                            mult_delayed[i] <= '0;
                            en_delayed[i] <= '0;
                        end else begin
                            mult_delayed[i] <= (stall) ? mult_delayed[i] : mult;
                            en_delayed[i] <= (stall) ? en_delayed[i] : en_reg;
                        end
                    end
                end
                else begin
                    always @(posedge clk) begin
                        if (reset) begin
                            mult_delayed[i] <= '0;
                            en_delayed[i] <= '0;
                        end else begin
                            mult_delayed[i] <= (stall) ? mult_delayed[i] : mult_delayed[i-1];
                            en_delayed[i] <= (stall) ? en_delayed[i] : en_delayed[i-1];
                        end
                    end
                end
            end
            assign out = mult_delayed[DELAY-2];
            assign done = en_delayed[DELAY-2] && ~reset;
        end
    endgenerate

endmodule
