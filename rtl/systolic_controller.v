`timescale 1ns/1ps

module systolic_controller #(
    parameter INPUT_WIDTH   = 16,
    parameter RESULT_WIDTH  = 16,
    parameter FRAC_WIDTH    = 15,
    parameter ADDR_WIDTH    = 12,
    parameter VECTOR_LENGTH = 4
)(
    input                           clk,
    input                           rst,
    input                           ap_start,
    output reg                      ap_done,
    // Data memory A (matrix rows)
    output reg                      data_a_en,
    output reg [ADDR_WIDTH-1:0]     data_a_addr,
    input      [INPUT_WIDTH-1:0]    data_a_rdata,
    // Data memory B (matrix columns)
    output reg                      data_b_en,
    output reg [ADDR_WIDTH-1:0]     data_b_addr,
    input      [INPUT_WIDTH-1:0]    data_b_rdata,
    // Instruction memory
    output reg                      inst_en,
    output reg [ADDR_WIDTH-1:0]     inst_addr,
    input      [INPUT_WIDTH-1:0]    inst_rdata,
    // Output memory
    output reg                      result_en,
    output reg                      result_we,
    output reg [ADDR_WIDTH-1:0]     result_addr,
    output reg [RESULT_WIDTH-1:0]   result_wdata,
    // Systolic array interface
    output reg                      tile_clear,
    output reg                      feed_valid,
    output reg [INPUT_WIDTH*4-1:0]  row_data_bus,
    output reg [INPUT_WIDTH*4-1:0]  col_data_bus,
    input                           ready_for_feed,
    input                           tile_done,
    input      [RESULT_WIDTH*16-1:0] tile_result_flat
);

    localparam STATE_IDLE         = 4'd0;
    localparam STATE_FETCH_INST   = 4'd1;
    localparam STATE_WAIT_INST    = 4'd2;
    localparam STATE_CHECK_INST   = 4'd3;
    localparam STATE_PREP_TILE    = 4'd4;
    localparam STATE_LOAD_A       = 4'd5;
    localparam STATE_LOAD_B       = 4'd6;
    localparam STATE_TILE_CLEAR   = 4'd7;
    localparam STATE_FEED         = 4'd8;
    localparam STATE_WAIT_TILE    = 4'd9;
    localparam STATE_WRITE_TILE   = 4'd10;
    localparam STATE_ADVANCE_TILE = 4'd11;
    localparam STATE_DONE         = 4'd12;

    localparam integer TILE_ELEMS = VECTOR_LENGTH * VECTOR_LENGTH;

    reg [3:0] state;
    reg [3:0] next_state;
    bit debug_controller;

    // Instruction tracking
    reg [ADDR_WIDTH-1:0] inst_ptr;
    reg [ADDR_WIDTH-1:0] a_ptr;
    reg [ADDR_WIDTH-1:0] b_ptr;
    reg [ADDR_WIDTH-1:0] o_ptr;
    reg [15:0]           curr_size;
    reg [7:0]            row_blocks_total;
    reg [7:0]            col_blocks_total;
    reg [7:0]            row_block_idx;
    reg [7:0]            col_block_idx;

    // Memory read bookkeeping
    reg [5:0] a_req_count;
    reg [5:0] a_cap_count;
    reg [5:0] b_req_count;
    reg [5:0] b_cap_count;

    reg       data_a_en_d;
    reg       data_b_en_d;
    reg       inst_en_d;

    // Feed/write counters
    reg [3:0] feed_count;
    reg [3:0] feed_cycles;
    localparam integer WRITE_CNT_WIDTH = $clog2(TILE_ELEMS+1);

    reg [WRITE_CNT_WIDTH-1:0] write_count;

    reg [RESULT_WIDTH*16-1:0] tile_result_reg;

    reg                     pending_result_valid;
    reg [ADDR_WIDTH-1:0]    pending_result_addr;
    reg [RESULT_WIDTH-1:0]  pending_result_data;

    // Tile buffers
    reg signed [INPUT_WIDTH-1:0] a_tile [0:VECTOR_LENGTH-1][0:VECTOR_LENGTH-1];
    reg signed [INPUT_WIDTH-1:0] b_tile [0:VECTOR_LENGTH-1][0:VECTOR_LENGTH-1];

    wire start_pulse;
    reg  ap_start_d;

    assign start_pulse = ap_start & ~ap_start_d;

    integer r, c;

    initial begin
        debug_controller = $test$plusargs("DEBUG_CTRL");
    end

    always @(posedge clk) begin
        if (rst) begin
            ap_start_d <= 1'b0;
        end else begin
            ap_start_d <= ap_start;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state        <= STATE_IDLE;
            inst_ptr     <= '0;
            a_ptr        <= '0;
            b_ptr        <= '0;
            o_ptr        <= '0;
            curr_size    <= '0;
            row_blocks_total <= '0;
            col_blocks_total <= '0;
            row_block_idx <= '0;
            col_block_idx <= '0;
            a_req_count  <= '0;
            a_cap_count  <= '0;
            b_req_count  <= '0;
            b_cap_count  <= '0;
            feed_count   <= '0;
            feed_cycles  <= '0;
            write_count  <= '0;
            ap_done      <= 1'b1;
            tile_clear   <= 1'b0;
            feed_valid   <= 1'b0;
            row_data_bus <= '0;
            col_data_bus <= '0;
            data_a_en    <= 1'b0;
            data_b_en    <= 1'b0;
            inst_en      <= 1'b0;
            result_en    <= 1'b0;
            result_we    <= 1'b0;
            result_addr  <= '0;
            result_wdata <= '0;
            pending_result_valid <= 1'b0;
            pending_result_addr  <= '0;
            pending_result_data  <= '0;
            data_a_en_d  <= 1'b0;
            data_b_en_d  <= 1'b0;
            inst_en_d    <= 1'b0;
            tile_result_reg <= '0;
            for (r = 0; r < VECTOR_LENGTH; r = r + 1) begin
                for (c = 0; c < VECTOR_LENGTH; c = c + 1) begin
                    a_tile[r][c] <= '0;
                    b_tile[r][c] <= '0;
                end
            end
        end else begin
            if (debug_controller && state != next_state) begin
                $display("%0t CTRL state %0d -> %0d size=%0d row_blk=%0d/%0d col_blk=%0d/%0d feed_cnt=%0d write_cnt=%0d",
                         $time, state, next_state, curr_size,
                         row_block_idx, row_blocks_total, col_block_idx, col_blocks_total,
                         feed_count, write_count);
            end
            state       <= next_state;
            data_a_en_d <= data_a_en;
            data_b_en_d <= data_b_en;
            inst_en_d   <= inst_en;

            // Defaults
            data_a_en    <= 1'b0;
            data_b_en    <= 1'b0;
            inst_en      <= 1'b0;
            result_en    <= pending_result_valid;
            result_we    <= pending_result_valid;
            tile_clear   <= 1'b0;
            feed_valid   <= 1'b0;
            result_addr  <= pending_result_addr;
            result_wdata <= pending_result_data;
            pending_result_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    ap_done <= 1'b1;
                    if (start_pulse) begin
                        ap_done  <= 1'b0;
                        inst_ptr <= '0;
                        a_ptr    <= '0;
                        b_ptr    <= '0;
                        o_ptr    <= '0;
                    end
                end
                STATE_FETCH_INST: begin
                    inst_en  <= 1'b1;
                    inst_addr<= inst_ptr;
                    if (debug_controller) begin
                        $display("%0t CTRL fetch inst_ptr=%0d", $time, inst_ptr);
                    end
                end
                STATE_WAIT_INST: begin
                    if (inst_en_d) begin
                        curr_size <= inst_rdata;
                        if (debug_controller) begin
                            $display("%0t CTRL inst data size=%0d a_ptr=%0d b_ptr=%0d o_ptr=%0d",
                                     $time, {{(16-INPUT_WIDTH){1'b0}}, inst_rdata}, a_ptr, b_ptr, o_ptr);
                        end
                    end
                end
                STATE_CHECK_INST: begin
                    row_blocks_total <= curr_size[15:2];
                    col_blocks_total <= curr_size[15:2];
                    row_block_idx    <= '0;
                    col_block_idx    <= '0;
                    if (debug_controller) begin
                        $display("%0t CTRL begin tiles row_blocks=%0d col_blocks=%0d",
                                 $time, curr_size[15:2], curr_size[15:2]);
                    end
                end
                STATE_PREP_TILE: begin
                    a_req_count <= '0;
                    a_cap_count <= '0;
                    b_req_count <= '0;
                    b_cap_count <= '0;
                    feed_count  <= '0;
                    feed_cycles <= '0;
                    write_count <= '0;
                    if (debug_controller) begin
                        $display("%0t CTRL prep tile row_blk=%0d col_blk=%0d",
                                 $time, row_block_idx, col_block_idx);
                    end
                end
                STATE_LOAD_A: begin
                    if (a_req_count < TILE_ELEMS[5:0]) begin
                        data_a_en <= 1'b1;
                        data_a_addr <= a_ptr + compute_a_addr(row_block_idx, a_req_count);
                        a_req_count <= a_req_count + 1'b1;
                        if (debug_controller) begin
                            $display("%0t CTRL load A req idx=%0d addr=%0d",
                                     $time, a_req_count, data_a_addr);
                        end
                    end
                    if (data_a_en_d && a_cap_count < TILE_ELEMS[5:0]) begin
                        store_a_tile(a_cap_count, data_a_rdata);
                        a_cap_count <= a_cap_count + 1'b1;
                        if (debug_controller) begin
                            $display("%0t CTRL cap A idx=%0d data=%0d",
                                     $time, a_cap_count, data_a_rdata);
                        end
                    end
                end
                STATE_LOAD_B: begin
                    if (b_req_count < TILE_ELEMS[5:0]) begin
                        data_b_en <= 1'b1;
                        data_b_addr <= b_ptr + compute_b_addr(curr_size, col_block_idx, b_req_count);
                        b_req_count <= b_req_count + 1'b1;
                        if (debug_controller) begin
                            $display("%0t CTRL load B req idx=%0d addr=%0d",
                                     $time, b_req_count, data_b_addr);
                        end
                    end
                    if (data_b_en_d && b_cap_count < TILE_ELEMS[5:0]) begin
                        store_b_tile(b_cap_count, data_b_rdata);
                        b_cap_count <= b_cap_count + 1'b1;
                        if (debug_controller) begin
                            $display("%0t CTRL cap B idx=%0d data=%0d",
                                     $time, b_cap_count, data_b_rdata);
                        end
                    end
                end
                STATE_TILE_CLEAR: begin
                    if (ready_for_feed) begin
                        tile_clear   <= 1'b1;
                        feed_count   <= '0;
                        feed_cycles  <= '0;
                        if (debug_controller) begin
                            $display("%0t CTRL tile_clear row_blk=%0d col_blk=%0d",
                                     $time, row_block_idx, col_block_idx);
                        end
                    end
                end
                STATE_FEED: begin
                    if (feed_cycles < VECTOR_LENGTH[3:0]) begin
                        reg [3:0] feed_idx;
                        feed_idx      = feed_count;
                        feed_valid   <= 1'b1;
                        row_data_bus <= pack_row_bus(feed_idx);
                        col_data_bus <= pack_col_bus(feed_idx);
                        feed_count   <= feed_count + 1'b1;
                        feed_cycles  <= feed_cycles + 1'b1;
                        if (debug_controller) begin
                            $display("%0t CTRL feed emit=%0d idx=%0d", $time, feed_cycles, feed_idx);
                        end
                    end else begin
                        feed_valid <= 1'b0;
                    end
                end
                STATE_WAIT_TILE: begin
                    if (tile_done) begin
                        tile_result_reg <= tile_result_flat;
                        if (debug_controller) begin
                            $display("%0t CTRL tile_done row_blk=%0d col_blk=%0d",
                                     $time, row_block_idx, col_block_idx);
                        end
                    end
                end
                STATE_WRITE_TILE: begin
                    if (write_count < TILE_ELEMS[WRITE_CNT_WIDTH-1:0]) begin : write_tile_block
                        reg [ADDR_WIDTH-1:0] addr_calc;
                        reg [RESULT_WIDTH-1:0] data_calc;
                        addr_calc = o_ptr + compute_c_addr(curr_size, row_block_idx, col_block_idx, write_count[4:0]);
                        data_calc = tile_result_reg[write_count[4:0]*RESULT_WIDTH +: RESULT_WIDTH];
                        pending_result_valid <= 1'b1;
                        pending_result_addr  <= addr_calc;
                        pending_result_data  <= data_calc;
                        if (debug_controller) begin
                            $display("%0t CTRL write instr_ptr=%0d tile_row=%0d tile_col=%0d idx=%0d addr=%0d data=%0d",
                                     $time, inst_ptr, row_block_idx, col_block_idx, write_count[4:0], addr_calc, data_calc);
                        end
                        write_count <= write_count + 1'b1;
                    end
                end
                STATE_ADVANCE_TILE: begin
                    // handled in combinational block
                end
                STATE_DONE: begin
                    ap_done <= 1'b1;
                    if (start_pulse) begin
                        ap_done  <= 1'b0;
                        inst_ptr <= '0;
                        a_ptr    <= '0;
                        b_ptr    <= '0;
                        o_ptr    <= '0;
                    end
                end
            endcase
        end
    end

    // Helper tasks/functions
    function [ADDR_WIDTH-1:0] compute_a_addr;
        input [7:0] block_row;
        input [5:0] index;
        reg [1:0] local_row;
        reg [1:0] local_col;
        reg [ADDR_WIDTH-1:0] global_row;
        begin
            local_row  = index[3:2];
            local_col  = index[1:0];
            global_row = (block_row << 2) + local_row;
            compute_a_addr = (global_row << 2) + local_col;
        end
    endfunction

    function [ADDR_WIDTH-1:0] compute_b_addr;
        input [15:0] size_value;
        input [7:0]  block_col;
        input [5:0]  index;
        reg [1:0] local_row;
        reg [1:0] local_col;
        reg [ADDR_WIDTH-1:0] col_index;
        begin
            local_row = index[3:2];
            local_col = index[1:0];
            col_index = (block_col << 2) + local_col;
            compute_b_addr = local_row * size_value + col_index;
        end
    endfunction

    function [ADDR_WIDTH-1:0] compute_c_addr;
        input [15:0] size_value;
        input [7:0]  block_row;
        input [7:0]  block_col;
        input [4:0]  index;
        reg [1:0] local_row;
        reg [1:0] local_col;
        reg [ADDR_WIDTH-1:0] global_row;
        reg [ADDR_WIDTH-1:0] global_col;
        begin
            local_row  = index[3:2];
            local_col  = index[1:0];
            global_row = (block_row << 2) + local_row;
            global_col = (block_col << 2) + local_col;
            compute_c_addr = global_row * size_value + global_col;
        end
    endfunction

    task store_a_tile;
        input [5:0] index;
        input signed [INPUT_WIDTH-1:0] data_word;
        reg [1:0] local_row;
        reg [1:0] local_col;
        begin
            local_row = index[3:2];
            local_col = index[1:0];
            a_tile[local_row][local_col] <= data_word;
        end
    endtask

    task store_b_tile;
        input [5:0] index;
        input signed [INPUT_WIDTH-1:0] data_word;
        reg [1:0] local_row;
        reg [1:0] local_col;
        begin
            local_row = index[3:2];
            local_col = index[1:0];
            b_tile[local_row][local_col] <= data_word;
        end
    endtask

    function [INPUT_WIDTH*4-1:0] pack_row_bus;
        input [3:0] column_sel;
        reg [INPUT_WIDTH*4-1:0] packed_bus;
        integer i;
        begin
            packed_bus = '0;
            for (i = 0; i < VECTOR_LENGTH; i = i + 1) begin
                packed_bus[i*INPUT_WIDTH +: INPUT_WIDTH] = a_tile[i][column_sel];
            end
            pack_row_bus = packed_bus;
        end
    endfunction

    function [INPUT_WIDTH*4-1:0] pack_col_bus;
        input [3:0] row_sel;
        reg [INPUT_WIDTH*4-1:0] packed_bus;
        integer j;
        begin
            packed_bus = '0;
            for (j = 0; j < VECTOR_LENGTH; j = j + 1) begin
                packed_bus[j*INPUT_WIDTH +: INPUT_WIDTH] = b_tile[row_sel][j];
            end
            pack_col_bus = packed_bus;
        end
    endfunction

    wire load_a_done = (a_cap_count == TILE_ELEMS[5:0]);
    wire load_b_done = (b_cap_count == TILE_ELEMS[5:0]);
wire feed_done   = (feed_cycles == VECTOR_LENGTH[3:0]);
    wire write_done  = (write_count == TILE_ELEMS[WRITE_CNT_WIDTH-1:0]);

    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE: begin
                if (start_pulse) next_state = STATE_FETCH_INST;
            end
            STATE_FETCH_INST: begin
                next_state = STATE_WAIT_INST;
            end
            STATE_WAIT_INST: begin
                if (inst_en_d) next_state = STATE_CHECK_INST;
            end
            STATE_CHECK_INST: begin
                if (curr_size == 0) begin
                    next_state = STATE_DONE;
                end else begin
                    next_state = STATE_PREP_TILE;
                end
            end
            STATE_PREP_TILE: begin
                next_state = STATE_LOAD_A;
            end
            STATE_LOAD_A: begin
                if (load_a_done) next_state = STATE_LOAD_B;
            end
            STATE_LOAD_B: begin
                if (load_b_done) next_state = STATE_TILE_CLEAR;
            end
            STATE_TILE_CLEAR: begin
                if (ready_for_feed) next_state = STATE_FEED;
            end
            STATE_FEED: begin
                if (feed_done) next_state = STATE_WAIT_TILE;
            end
            STATE_WAIT_TILE: begin
                if (tile_done) next_state = STATE_WRITE_TILE;
            end
            STATE_WRITE_TILE: begin
                if (write_done) next_state = STATE_ADVANCE_TILE;
            end
            STATE_ADVANCE_TILE: begin
                if (col_block_idx + 1 < col_blocks_total) begin
                    next_state = STATE_PREP_TILE;
                end else if (row_block_idx + 1 < row_blocks_total) begin
                    next_state = STATE_PREP_TILE;
                end else begin
                    next_state = STATE_FETCH_INST;
                end
            end
            STATE_DONE: begin
                if (start_pulse) next_state = STATE_FETCH_INST;
            end
            default: next_state = STATE_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            // already handled above
        end else begin
            if (state == STATE_ADVANCE_TILE) begin
                if (col_block_idx + 1 < col_blocks_total) begin
                    col_block_idx <= col_block_idx + 1'b1;
                end else begin
                    col_block_idx <= '0;
                    if (row_block_idx + 1 < row_blocks_total) begin
                        row_block_idx <= row_block_idx + 1'b1;
                    end else begin
                        row_block_idx <= '0;
                        inst_ptr <= inst_ptr + 1'b1;
                        a_ptr    <= a_ptr + curr_size * VECTOR_LENGTH;
                        b_ptr    <= b_ptr + curr_size * VECTOR_LENGTH;
                        o_ptr    <= o_ptr + curr_size * curr_size;
                    end
                end
            end
        end
    end

endmodule

