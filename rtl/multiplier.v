module multiplier#(
    parameter INPUT_A_WIDTH = 16,
    parameter INPUT_B_WIDTH = 16,
    parameter INPUT_A_FRAC  = 15,
    parameter INPUT_B_FRAC  = 15,
    parameter OUTPUT_WIDTH  = 16,
    parameter OUTPUT_FRAC   = 15,
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

    //mult
    always @(posedge clk ) begin
        if (reset) begin
            mult    <=  '0;
        end else if (!stall && en) begin
            mult <= product_clamped;
        end
    end

    //output buffer
    genvar i;
    generate
        if (DELAY <= 1) begin
            assign out = mult;
            //sync with mult
            always @(posedge clk ) begin
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
            //sync with mult
            always @(posedge clk ) begin
                if (reset) begin
                    en_reg <= '0;
                end else begin
                    en_reg <= (stall) ? en_reg : en;
                end
            end
            for (i = 0; i < DELAY-1; i = i + 1) begin
                if (i == 0) begin
                    always @(posedge clk ) begin
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
                    always @(posedge clk ) begin
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