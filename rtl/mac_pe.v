`timescale 1ns/1ps

module mac_pe #(
    parameter INPUT_WIDTH   = 16,
    parameter ACC_WIDTH     = 16,
    parameter FRAC_WIDTH    = 8,
    parameter VECTOR_LENGTH = 4,
    parameter integer MAC_ROW = 0,
    parameter integer MAC_COL = 0
)(
    input                               clk,
    input                               rst,
    input                               clear,
    input        signed [INPUT_WIDTH-1:0] a_in,
    input                               a_valid_in,
    input        signed [INPUT_WIDTH-1:0] b_in,
    input                               b_valid_in,
    output reg   signed [INPUT_WIDTH-1:0] a_out,
    output reg                          a_valid_out,
    output reg   signed [INPUT_WIDTH-1:0] b_out,
    output reg                          b_valid_out,
    output reg   signed [ACC_WIDTH-1:0]  acc_value,
    output reg                          acc_valid
);

    localparam integer COUNT_WIDTH = $clog2(VECTOR_LENGTH+1);

    wire operation_en = a_valid_in & b_valid_in;

    localparam integer MULT_DELAY = 3;
    localparam integer ADD_DELAY  = 1;

    wire signed [ACC_WIDTH-1:0] product;
    wire                        product_valid;
    wire signed [ACC_WIDTH-1:0] sum_value;
    wire                        sum_valid;
    wire signed [ACC_WIDTH-1:0] acc_feedback;
    bit debug_mac;

    initial begin
        debug_mac = $test$plusargs("DEBUG_MAC");
    end

    multiplier #(
        .INPUT_A_WIDTH (INPUT_WIDTH),
        .INPUT_B_WIDTH (INPUT_WIDTH),
        .INPUT_A_FRAC  (FRAC_WIDTH),
        .INPUT_B_FRAC  (FRAC_WIDTH),
        .OUTPUT_WIDTH  (ACC_WIDTH),
        .OUTPUT_FRAC   (FRAC_WIDTH),
        .DELAY         (MULT_DELAY)
    ) u_multiplier (
        .clk   (clk),
        .reset (rst | clear),
        .en    (operation_en),
        .stall (1'b0),
        .a_in  (a_in),
        .b_in  (b_in),
        .out   (product),
        .done  (product_valid)
    );

    adder #(
        .INPUT_A_WIDTH (ACC_WIDTH),
        .INPUT_A_FRAC  (FRAC_WIDTH),
        .INPUT_B_WIDTH (ACC_WIDTH),
        .INPUT_B_FRAC  (FRAC_WIDTH),
        .OUTPUT_WIDTH  (ACC_WIDTH),
        .OUTPUT_FRAC   (FRAC_WIDTH),
        .DELAY         (ADD_DELAY)
    ) u_adder (
        .clk   (clk),
        .reset (rst | clear),
        .en    (product_valid),
        .stall (1'b0),
        .a_in  (product),
        .b_in  (acc_feedback),
        .out   (sum_value),
        .done  (sum_valid)
    );

    assign acc_feedback = sum_valid ? sum_value : acc_value;

    reg [COUNT_WIDTH-1:0] mult_count;
    reg [COUNT_WIDTH-1:0] add_count;

    always @(posedge clk) begin
        if (rst | clear) begin
            a_out       <= '0;
            b_out       <= '0;
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
        end else begin
            if (a_valid_in) begin
                a_out <= a_in;
            end
            if (b_valid_in) begin
                b_out <= b_in;
            end
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;
        end
    end

    always @(posedge clk) begin
        if (rst | clear) begin
            acc_value  <= '0;
            acc_valid  <= 1'b0;
            mult_count <= '0;
            add_count  <= '0;
        end else begin
            if (operation_en) begin
                if (mult_count != VECTOR_LENGTH[COUNT_WIDTH-1:0]) begin
                    mult_count <= mult_count + 1'b1;
                end
                if (debug_mac) begin
                    $display("%0t MAC[%0d,%0d] mul launch a=%0d b=%0d",
                             $time, MAC_ROW, MAC_COL, a_in, b_in);
                end
            end
            if (debug_mac && product_valid) begin
                $display("%0t MAC[%0d,%0d] product=%0d",
                         $time, MAC_ROW, MAC_COL, product);
            end

            if (sum_valid) begin
                acc_value <= sum_value;
                add_count <= add_count + 1'b1;
                if (debug_mac) begin
                    $display("%0t MAC[%0d,%0d] sum=%0d add_count=%0d/%0d",
                             $time, MAC_ROW, MAC_COL, sum_value,
                             add_count + 1'b1, VECTOR_LENGTH[COUNT_WIDTH-1:0]);
                end
                if (add_count + 1'b1 == VECTOR_LENGTH[COUNT_WIDTH-1:0]) begin
                    acc_valid <= 1'b1;
                end
            end
        end
    end

endmodule

