`timescale 1ns/1ps

module tb_systolic_top;

    localparam INPUT_WIDTH  = 16;
    localparam RESULT_WIDTH = 16;
    localparam ADDR_WIDTH = 10;
    localparam CLK_PERIOD = 10;
    localparam integer VECTOR_DIM = 4;
    localparam integer DONE_TIMEOUT_CYCLES = 200000;

    reg clk;
    reg rst;

    reg [ADDR_WIDTH-1:0] addrA;
    reg                  enA;
    reg [INPUT_WIDTH-1:0] dataA;

    reg [ADDR_WIDTH-1:0] addrB;
    reg                  enB;
    reg [INPUT_WIDTH-1:0] dataB;

    reg [ADDR_WIDTH-1:0] addrI;
    reg                  enI;
    reg [INPUT_WIDTH-1:0] dataI;

    reg [ADDR_WIDTH-1:0] addrO;
    wire [RESULT_WIDTH-1:0] dataO;

    reg ap_start;
    wire ap_done;

    string vector_dir = "build";
    string output_dump_path;

    systolic_top #(
        .INPUT_WIDTH (INPUT_WIDTH),
        .RESULT_WIDTH(RESULT_WIDTH),
        .FRAC_WIDTH  (15),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .addrA  (addrA),
        .enA    (enA),
        .dataA  (dataA),
        .addrB  (addrB),
        .enB    (enB),
        .dataB  (dataB),
        .addrI  (addrI),
        .enI    (enI),
        .dataI  (dataI),
        .addrO  (addrO),
        .dataO  (dataO),
        .ap_start(ap_start),
        .ap_done (ap_done)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Vectors loaded from Python generator
    int instruction_sizes[$];
    logic signed [INPUT_WIDTH-1:0]  dataA_words[$];
    logic signed [INPUT_WIDTH-1:0]  dataB_words[$];
    logic signed [RESULT_WIDTH-1:0] expected_words[$];

    int num_instructions;
    int a_bases[$];
    int b_bases[$];
    int o_bases[$];
    int expected_bases[$];
    int total_a_words;
    int total_b_words;
    int total_expected_words;

    task automatic host_write_A(input int addr, input logic signed [INPUT_WIDTH-1:0] value);
        begin
            @(negedge clk);
            addrA <= addr[ADDR_WIDTH-1:0];
            dataA <= value;
            enA   <= 1'b1;
            @(negedge clk);
            enA   <= 1'b0;
        end
    endtask

    task automatic host_write_B(input int addr, input logic signed [INPUT_WIDTH-1:0] value);
        begin
            @(negedge clk);
            addrB <= addr[ADDR_WIDTH-1:0];
            dataB <= value;
            enB   <= 1'b1;
            @(negedge clk);
            enB   <= 1'b0;
        end
    endtask

    task automatic host_write_I(input int addr, input logic signed [INPUT_WIDTH-1:0] value);
        begin
            @(negedge clk);
            addrI <= addr[ADDR_WIDTH-1:0];
            dataI <= value;
            enI   <= 1'b1;
            @(negedge clk);
            enI   <= 1'b0;
        end
    endtask

    task automatic read_output(input int addr, output logic signed [RESULT_WIDTH-1:0] value);
        begin
            @(negedge clk);
            addrO <= addr[ADDR_WIDTH-1:0];
            @(negedge clk);
            value = dataO;
        end
    endtask

    task automatic dump_controller_state();
        $display("---- Controller/Array Snapshot ----");
        $display("ctrl.state=%0d next=%0d curr_size=%0d ap_done=%0b",
                 dut.u_controller.state,
                 dut.u_controller.next_state,
                 dut.u_controller.curr_size,
                 ap_done);
        $display("inst_ptr=%0d a_ptr=%0d b_ptr=%0d o_ptr=%0d",
                 dut.u_controller.inst_ptr,
                 dut.u_controller.a_ptr,
                 dut.u_controller.b_ptr,
                 dut.u_controller.o_ptr);
        $display("row_block idx=%0d/%0d col_block idx=%0d/%0d",
                 dut.u_controller.row_block_idx,
                 dut.u_controller.row_blocks_total,
                 dut.u_controller.col_block_idx,
                 dut.u_controller.col_blocks_total);
        $display("A req/cap=%0d/%0d  B req/cap=%0d/%0d",
                 dut.u_controller.a_req_count,
                 dut.u_controller.a_cap_count,
                 dut.u_controller.b_req_count,
                 dut.u_controller.b_cap_count);
        $display("feed_count=%0d write_count=%0d",
                 dut.u_controller.feed_count,
                 dut.u_controller.write_count);
        $display("array.ready=%0b tile_done=%0b busy=%0b done_sent=%0b",
                 dut.array_ready,
                 dut.array_tile_done,
                 dut.u_array.busy,
                 dut.u_array.tile_done_sent);
        $display("-----------------------------------");
    endtask

    task automatic read_int_queue(input string path, ref int queue[$]);
        integer fd;
        integer code;
        integer value;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "Failed to open %s", path);
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    queue.push_back(value);
                end else if (code == 0) begin
                    void'($fgetc(fd));
                end
            end
            $fclose(fd);
        end
    endtask

    task automatic read_logic_queue_input(
        input string path,
        ref logic signed [INPUT_WIDTH-1:0] queue[$]
    );
        integer fd;
        integer code;
        integer value;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "Failed to open %s", path);
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    queue.push_back(value[INPUT_WIDTH-1:0]);
                end else if (code == 0) begin
                    void'($fgetc(fd));
                end
            end
            $fclose(fd);
        end
    endtask

    task automatic read_logic_queue_result(
        input string path,
        ref logic signed [RESULT_WIDTH-1:0] queue[$]
    );
        integer fd;
        integer code;
        integer value;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "Failed to open %s", path);
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    queue.push_back(value[RESULT_WIDTH-1:0]);
                end else if (code == 0) begin
                    void'($fgetc(fd));
                end
            end
            $fclose(fd);
        end
    endtask

    task automatic build_base_arrays();
        int a_ptr_tmp;
        int b_ptr_tmp;
        int o_ptr_tmp;
        int exp_ptr_tmp;
        int idx;
        begin
            a_ptr_tmp   = 0;
            b_ptr_tmp   = 0;
            o_ptr_tmp   = 0;
            exp_ptr_tmp = 0;

            for (idx = 0; idx < num_instructions; idx++) begin
                int size = instruction_sizes[idx];
                a_bases.push_back(a_ptr_tmp);
                b_bases.push_back(b_ptr_tmp);
                o_bases.push_back(o_ptr_tmp);
                expected_bases.push_back(exp_ptr_tmp);

                a_ptr_tmp   += size * VECTOR_DIM;
                b_ptr_tmp   += size * VECTOR_DIM;
                o_ptr_tmp   += size * size;
                exp_ptr_tmp += size * size;
            end

            total_a_words        = a_ptr_tmp;
            total_b_words        = b_ptr_tmp;
            total_expected_words = exp_ptr_tmp;
        end
    endtask

    task automatic load_vector_files(input string dir);
        string inst_file;
        string dataA_file;
        string dataB_file;
        string expected_file;
        int last_value;
        begin
            inst_file     = {dir, "/instructions.mem"};
            dataA_file    = {dir, "/dataA.mem"};
            dataB_file    = {dir, "/dataB.mem"};
            expected_file = {dir, "/expected.mem"};

            instruction_sizes.delete();
            dataA_words.delete();
            dataB_words.delete();
            expected_words.delete();
            a_bases.delete();
            b_bases.delete();
            o_bases.delete();
            expected_bases.delete();

            read_int_queue(inst_file, instruction_sizes);
            if (instruction_sizes.size() == 0) begin
                $fatal(1, "Instruction file %s is empty", inst_file);
            end
            last_value = instruction_sizes[instruction_sizes.size()-1];
            if (last_value != 0) begin
                $display("Instruction stream tail (size=%0d):", instruction_sizes.size());
                foreach (instruction_sizes[idx]) begin
                    $display("  idx %0d -> %0d", idx, instruction_sizes[idx]);
                end
                $fatal(1, "Instruction stream must terminate with 0 (last=%0d)", last_value);
            end

            num_instructions = instruction_sizes.size() - 1;
            if (num_instructions == 0) begin
                $fatal(1, "Instruction stream does not contain any workloads");
            end

            build_base_arrays();

            read_logic_queue_input (dataA_file, dataA_words);
            read_logic_queue_input (dataB_file, dataB_words);
            read_logic_queue_result(expected_file, expected_words);

            if (dataA_words.size() != total_a_words) begin
                $fatal(1, "dataA.mem length mismatch: expected %0d, got %0d",
                       total_a_words, dataA_words.size());
            end
            if (dataB_words.size() != total_b_words) begin
                $fatal(1, "dataB.mem length mismatch: expected %0d, got %0d",
                       total_b_words, dataB_words.size());
            end
            if (expected_words.size() != total_expected_words) begin
                $fatal(1, "expected.mem length mismatch: expected %0d, got %0d",
                       total_expected_words, expected_words.size());
            end
        end
    endtask

    task automatic program_memories();
        int instr_idx;
        int row;
        int col;
        int idx_a;
        int idx_b;
        begin
            idx_a = 0;
            idx_b = 0;
            for (instr_idx = 0; instr_idx < num_instructions; instr_idx++) begin
                int size    = instruction_sizes[instr_idx];
                int base_a  = a_bases[instr_idx];
                int base_b  = b_bases[instr_idx];

                for (row = 0; row < size; row++) begin
                    for (col = 0; col < VECTOR_DIM; col++) begin
                        host_write_A(base_a + row * VECTOR_DIM + col, dataA_words[idx_a]);
                        idx_a++;
                    end
                end

                for (row = 0; row < VECTOR_DIM; row++) begin
                    for (col = 0; col < size; col++) begin
                        host_write_B(base_b + row * size + col, dataB_words[idx_b]);
                        idx_b++;
                    end
                end
            end

            // Write instruction memory (including terminating 0)
            for (instr_idx = 0; instr_idx < instruction_sizes.size(); instr_idx++) begin
                host_write_I(instr_idx, instruction_sizes[instr_idx][INPUT_WIDTH-1:0]);
            end
        end
    endtask

    task automatic dump_results_to_file(input string path);
        int instr_idx;
        int row;
        int col;
        int fd;
        logic signed [RESULT_WIDTH-1:0] value_hw;
        begin
            fd = $fopen(path, "w");
            if (fd == 0) begin
                $fatal(1, "Failed to open output dump file %s", path);
            end
            for (instr_idx = 0; instr_idx < num_instructions; instr_idx++) begin
                int size     = instruction_sizes[instr_idx];
                int base_out = o_bases[instr_idx];
                for (row = 0; row < size; row++) begin
                    for (col = 0; col < size; col++) begin
                        read_output(base_out + row * size + col, value_hw);
                        $fdisplay(fd, "%0d", value_hw);
                    end
                end
            end
            $fclose(fd);
            $display("Dumped DUT outputs to %s", path);
        end
    endtask

    task automatic check_results();
        int instr_idx;
        int row;
        int col;
        int expected_index;
        logic signed [RESULT_WIDTH-1:0] value_hw;
        logic signed [RESULT_WIDTH-1:0] expected_value;
        begin
            expected_index = 0;
            for (instr_idx = 0; instr_idx < num_instructions; instr_idx++) begin
                int size     = instruction_sizes[instr_idx];
                int base_out = o_bases[instr_idx];
                for (row = 0; row < size; row++) begin
                    for (col = 0; col < size; col++) begin
                        read_output(base_out + row * size + col, value_hw);
                        if (^value_hw === 1'bX) begin
                            $display("ERROR: Read X/Z at instr %0d row %0d col %0d (addr %0d)",
                                     instr_idx, row, col, base_out + row * size + col);
                            dump_controller_state();
                            $fatal(1, "Output memory contains X/Z");
                        end
                        expected_value = expected_words[expected_index];
                        if (value_hw !== expected_value) begin
                            $display("Mismatch instr %0d row %0d col %0d exp=%0d got=%0d",
                                     instr_idx, row, col, expected_value, value_hw);
                            $fatal(1, "Result mismatch.");
                        end
                        expected_index++;
                    end
                end
            end

            if (expected_index != expected_words.size()) begin
                $fatal(1, "Expected data exhausted early (%0d/%0d)",
                       expected_index, expected_words.size());
            end
        end
    endtask

    initial begin
        enA = 0; enB = 0; enI = 0;
        addrA = 0; addrB = 0; addrI = 0; addrO = 0;
        dataA = 0; dataB = 0; dataI = 0;
        ap_start = 0;

        if (!$value$plusargs("VEC_DIR=%s", vector_dir)) begin
            vector_dir = "build";
        end

        if (!$value$plusargs("OUTPUT_DUMP=%s", output_dump_path)) begin
            output_dump_path = {vector_dir, "/dut_output.mem"};
        end

        rst = 1;
        repeat (5) @(negedge clk);
        rst = 0;

        load_vector_files(vector_dir);
        program_memories();

        @(negedge clk);
        ap_start <= 1'b1;
        @(negedge clk);
        ap_start <= 1'b0;

        fork : wait_done_or_timeout
            begin
                wait (ap_done);
            end
            begin
                repeat (DONE_TIMEOUT_CYCLES) @(negedge clk);
                $display("ERROR: Timeout (%0d cycles) waiting for ap_done", DONE_TIMEOUT_CYCLES);
                dump_controller_state();
                $fatal(1, "ap_done timeout");
            end
        join_any
        disable wait_done_or_timeout;

        dump_results_to_file(output_dump_path);
        check_results();

        $display("All systolic array tests passed using vectors in %s.", vector_dir);
        $finish;
    end

endmodule

