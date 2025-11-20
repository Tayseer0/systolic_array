module multiplier#(
    parameter INPUT_A_WIDTH = 8,
    parameter INPUT_B_WIDTH = 8,
    parameter INPUT_A_FRAC  = 0,
    parameter INPUT_B_FRAC  = 0,
    parameter OUTPUT_WIDTH  = 16,
    parameter OUTPUT_FRAC   = 0,
    parameter DELAY         = 3
)(
    input                          clk,
    input                          reset,
    input                          en,
    input                          stall,
    input      [INPUT_A_WIDTH-1:0] a_in,
    input      [INPUT_B_WIDTH-1:0] b_in,
    output     [OUTPUT_WIDTH-1:0] out,
    output                         done
);

    reg [OUTPUT_WIDTH-1:0] mult;
    reg en_reg;

    localparam integer SHIFT_VALUE = INPUT_A_FRAC + INPUT_B_FRAC - OUTPUT_FRAC;
    localparam integer SHIFT_LEFT  = (SHIFT_VALUE < 0) ? -SHIFT_VALUE : 0;

    //mult
    always @(posedge clk ) begin
        if (reset) begin
            mult    <=  '0;
        end else if (!stall) begin
            if (SHIFT_VALUE >= 0) begin
                mult <= (a_in * b_in) >> SHIFT_VALUE;
            end else begin
                mult <= (a_in * b_in) << SHIFT_LEFT;
            end
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