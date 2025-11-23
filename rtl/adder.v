module adder#(
    parameter INPUT_A_WIDTH = 16,
    parameter INPUT_A_FRAC  = 8,
    parameter INPUT_B_WIDTH = 16,
    parameter INPUT_B_FRAC  = 8,
    parameter OUTPUT_WIDTH  = 16,
    parameter OUTPUT_FRAC   = 8,
    parameter DELAY         = 1
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

    reg signed [OUTPUT_WIDTH-1:0] add;
    reg en_reg;
    
    localparam integer SHIFT_A = OUTPUT_FRAC - INPUT_A_FRAC;
    localparam integer SHIFT_B = OUTPUT_FRAC - INPUT_B_FRAC;

    localparam signed [OUTPUT_WIDTH-1:0] MAX_VAL = {1'b0, {(OUTPUT_WIDTH-1){1'b1}}};
    localparam signed [OUTPUT_WIDTH-1:0] MIN_VAL = {1'b1, {(OUTPUT_WIDTH-1){1'b0}}};
    localparam signed [OUTPUT_WIDTH:0]   MAX_EXT = {MAX_VAL[OUTPUT_WIDTH-1], MAX_VAL};
    localparam signed [OUTPUT_WIDTH:0]   MIN_EXT = {MIN_VAL[OUTPUT_WIDTH-1], MIN_VAL};

    function automatic signed [OUTPUT_WIDTH-1:0] align_input(
        input signed [OUTPUT_WIDTH-1:0] value,
        input integer shift
    );
        begin
            if (shift >= 0) begin
                align_input = (shift >= OUTPUT_WIDTH) ? {OUTPUT_WIDTH{value[OUTPUT_WIDTH-1]}}
                                                      : (value <<< shift);
            end else begin
                align_input = (-shift >= OUTPUT_WIDTH) ? {OUTPUT_WIDTH{value[OUTPUT_WIDTH-1]}}
                                                       : (value >>> (-shift));
            end
        end
    endfunction

    wire signed [OUTPUT_WIDTH-1:0] a_ext = {{(OUTPUT_WIDTH-INPUT_A_WIDTH){a_in[INPUT_A_WIDTH-1]}}, a_in};
    wire signed [OUTPUT_WIDTH-1:0] b_ext = {{(OUTPUT_WIDTH-INPUT_B_WIDTH){b_in[INPUT_B_WIDTH-1]}}, b_in};

    wire signed [OUTPUT_WIDTH-1:0] a_aligned = align_input(a_ext, SHIFT_A);
    wire signed [OUTPUT_WIDTH-1:0] b_aligned = align_input(b_ext, SHIFT_B);

    wire signed [OUTPUT_WIDTH:0] a_ext_full = {a_aligned[OUTPUT_WIDTH-1], a_aligned};
    wire signed [OUTPUT_WIDTH:0] b_ext_full = {b_aligned[OUTPUT_WIDTH-1], b_aligned};
    wire signed [OUTPUT_WIDTH:0] sum_ext = a_ext_full + b_ext_full;
    wire signed [OUTPUT_WIDTH-1:0] sum_clamped =
        (sum_ext > MAX_EXT) ? MAX_VAL :
        (sum_ext < MIN_EXT) ? MIN_VAL :
        sum_ext[OUTPUT_WIDTH-1:0];

    //add
    always @(posedge clk ) begin
        if (reset) begin
            add <= '0;
        end else if (!stall && en) begin
            add <= sum_clamped;
        end
    end

    //output buffer
    genvar i;
    generate
        if (DELAY <= 1) begin
            assign out = add;
            //sync with add
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
            reg [OUTPUT_WIDTH-1:0] add_delayed[0:DELAY-2];
            reg en_delayed[0:DELAY-2];
            //sync with add
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
                            add_delayed[i] <= '0;
                            en_delayed[i] <= '0;
                        end else begin
                            add_delayed[i] <= (stall) ? add_delayed[i] : add;
                            en_delayed[i] <= (stall) ? en_delayed[i] : en_reg;
                        end
                    end
                end
                else begin
                    always @(posedge clk ) begin
                        if (reset) begin
                            add_delayed[i] <= '0;
                            en_delayed[i] <= '0;
                        end else begin
                            add_delayed[i] <= (stall) ? add_delayed[i] : add_delayed[i-1];
                            en_delayed[i] <= (stall) ? en_delayed[i] : en_delayed[i-1];
                        end
                    end
                end
            end
            assign out = add_delayed[DELAY-2];
            assign done = en_delayed[DELAY-2] && ~reset;
        end
    endgenerate

endmodule