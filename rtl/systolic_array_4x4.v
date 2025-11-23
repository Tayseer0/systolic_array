`timescale 1ns/1ps

module systolic_array_4x4 #(
    parameter INPUT_WIDTH   = 16,
    parameter ACC_WIDTH     = 16,
    parameter FRAC_WIDTH    = 8,
    parameter VECTOR_LENGTH = 4
)(
    input                               clk,
    input                               rst,
    input                               tile_clear,
    input                               feed_valid,
    input  [INPUT_WIDTH*4-1:0]          row_data_bus,
    input  [INPUT_WIDTH*4-1:0]          col_data_bus,
    output                              ready_for_feed,
    output reg                          tile_done,
    output [ACC_WIDTH*16-1:0]           tile_result_flat
);

    localparam ROWS = 4;
    localparam COLS = 4;

    wire signed [INPUT_WIDTH-1:0] row_inputs   [0:ROWS-1];
    wire signed [INPUT_WIDTH-1:0] col_inputs   [0:COLS-1];
    wire                         row_valid_in [0:ROWS-1];
    wire                         col_valid_in [0:COLS-1];

    genvar idx;
    generate
        for (idx = 0; idx < ROWS; idx = idx + 1) begin : ROW_INPUTS
            if (idx == 0) begin : ROW0
                assign row_inputs[idx]   = row_data_bus[INPUT_WIDTH*idx +: INPUT_WIDTH];
                assign row_valid_in[idx] = feed_valid;
            end else begin : ROW_DELAY
                reg signed [INPUT_WIDTH-1:0] row_data_pipe [0:idx-1];
                reg                         row_valid_pipe[0:idx-1];
                integer stage;
                always @(posedge clk) begin
                    if (rst) begin
                        for (stage = 0; stage < idx; stage = stage + 1) begin
                            row_data_pipe[stage]  <= '0;
                            row_valid_pipe[stage] <= 1'b0;
                        end
                    end else begin
                        row_data_pipe[0]  <= row_data_bus[INPUT_WIDTH*idx +: INPUT_WIDTH];
                        row_valid_pipe[0] <= feed_valid;
                        for (stage = 1; stage < idx; stage = stage + 1) begin
                            row_data_pipe[stage]  <= row_data_pipe[stage-1];
                            row_valid_pipe[stage] <= row_valid_pipe[stage-1];
                        end
                    end
                end
                assign row_inputs[idx]   = row_data_pipe[idx-1];
                assign row_valid_in[idx] = row_valid_pipe[idx-1];
            end
        end

        for (idx = 0; idx < COLS; idx = idx + 1) begin : COL_INPUTS
            if (idx == 0) begin : COL0
                assign col_inputs[idx]   = col_data_bus[INPUT_WIDTH*idx +: INPUT_WIDTH];
                assign col_valid_in[idx] = feed_valid;
            end else begin : COL_DELAY
                reg signed [INPUT_WIDTH-1:0] col_data_pipe [0:idx-1];
                reg                         col_valid_pipe[0:idx-1];
                integer cstage;
                always @(posedge clk) begin
                    if (rst) begin
                        for (cstage = 0; cstage < idx; cstage = cstage + 1) begin
                            col_data_pipe[cstage]  <= '0;
                            col_valid_pipe[cstage] <= 1'b0;
                        end
                    end else begin
                        col_data_pipe[0]  <= col_data_bus[INPUT_WIDTH*idx +: INPUT_WIDTH];
                        col_valid_pipe[0] <= feed_valid;
                        for (cstage = 1; cstage < idx; cstage = cstage + 1) begin
                            col_data_pipe[cstage]  <= col_data_pipe[cstage-1];
                            col_valid_pipe[cstage] <= col_valid_pipe[cstage-1];
                        end
                    end
                end
                assign col_inputs[idx]   = col_data_pipe[idx-1];
                assign col_valid_in[idx] = col_valid_pipe[idx-1];
            end
        end
    endgenerate

    wire signed [INPUT_WIDTH-1:0] a_bus [0:ROWS-1][0:COLS];
    wire signed [INPUT_WIDTH-1:0] b_bus [0:ROWS][0:COLS-1];
    wire                         a_val [0:ROWS-1][0:COLS];
    wire                         b_val [0:ROWS][0:COLS-1];

    generate
        for (idx = 0; idx < ROWS; idx = idx + 1) begin : ROW_BUS
            assign a_bus[idx][0] = row_inputs[idx];
            assign a_val[idx][0] = row_valid_in[idx];
        end
        for (idx = 0; idx < COLS; idx = idx + 1) begin : COL_BUS
            assign b_bus[0][idx] = col_inputs[idx];
            assign b_val[0][idx] = col_valid_in[idx];
        end
    endgenerate

    wire signed [ACC_WIDTH-1:0] pe_values[0:ROWS-1][0:COLS-1];
    wire                         pe_valids[0:ROWS-1][0:COLS-1];

    genvar r, c;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : ROW_GEN
            for (c = 0; c < COLS; c = c + 1) begin : COL_GEN
                mac_pe #(
                    .INPUT_WIDTH  (INPUT_WIDTH),
                    .ACC_WIDTH    (ACC_WIDTH),
                    .FRAC_WIDTH   (FRAC_WIDTH),
                    .VECTOR_LENGTH(VECTOR_LENGTH),
                    .MAC_ROW      (r),
                    .MAC_COL      (c)
                ) u_mac_pe (
                    .clk          (clk),
                    .rst          (rst),
                    .clear        (tile_clear),
                    .a_in         (a_bus[r][c]),
                    .a_valid_in   (a_val[r][c]),
                    .b_in         (b_bus[r][c]),
                    .b_valid_in   (b_val[r][c]),
                    .a_out        (a_bus[r][c+1]),
                    .a_valid_out  (a_val[r][c+1]),
                    .b_out        (b_bus[r+1][c]),
                    .b_valid_out  (b_val[r+1][c]),
                    .acc_value    (pe_values[r][c]),
                    .acc_valid    (pe_valids[r][c])
                );
            end
        end
    endgenerate

    generate
        for (r = 0; r < ROWS; r = r + 1) begin : OUT_ROW
            for (c = 0; c < COLS; c = c + 1) begin : OUT_COL
                localparam integer OUT_INDEX = r * COLS + c;
                assign tile_result_flat[OUT_INDEX*ACC_WIDTH +: ACC_WIDTH] = pe_values[r][c];
            end
        end
    endgenerate

    reg [ROWS*COLS-1:0] pe_done_mask;
    wire all_valid = &pe_done_mask;

    reg busy;
    reg tile_done_sent;
    bit debug_tile;
    bit debug_array;
    integer rr, cc;

    initial begin
        debug_tile  = $test$plusargs("DEBUG_TILE");
        debug_array = $test$plusargs("DEBUG_ARRAY");
    end

    assign ready_for_feed = ~busy;

    always @(posedge clk) begin
        if (rst) begin
            busy           <= 1'b0;
            tile_done_sent <= 1'b0;
            tile_done      <= 1'b0;
            pe_done_mask   <= '0;
        end else begin
            tile_done <= 1'b0;
            if (tile_clear && ~busy) begin
                busy           <= 1'b1;
                tile_done_sent <= 1'b0;
                pe_done_mask   <= '0;
                if (debug_array) begin
                    $display("%0t ARRAY start tile", $time);
                end
            end else begin
                if (busy) begin
                    for (rr = 0; rr < ROWS; rr = rr + 1) begin
                        for (cc = 0; cc < COLS; cc = cc + 1) begin
                            if (pe_valids[rr][cc]) begin
                                if (debug_array && ~pe_done_mask[rr*COLS + cc]) begin
                                    $display("%0t ARRAY PE[%0d,%0d] acc=%0d",
                                             $time, rr, cc, pe_values[rr][cc]);
                                end
                                pe_done_mask[rr*COLS + cc] <= 1'b1;
                            end
                        end
                    end

                    if (all_valid && ~tile_done_sent) begin
                        tile_done      <= 1'b1;
                        tile_done_sent <= 1'b1;
                        busy           <= 1'b0;
                        if (debug_array) begin
                            $display("%0t ARRAY tile_done mask=%b", $time, pe_done_mask);
                        end
                        if (debug_tile) begin
                            $display("DEBUG_TILE_RESULT:");
                            for (rr = 0; rr < ROWS; rr = rr + 1) begin
                                string line;
                                line = "";
                                for (cc = 0; cc < COLS; cc = cc + 1) begin
                                    line = {line, $sformatf("%0d ", pe_values[rr][cc])};
                                end
                                $display("%s", line);
                            end
                        end
                    end
                end
            end
        end
    end

endmodule

