module buffer #(
    parameter                               BUFFER_SIZE = 16,
    parameter                               DATA_WIDTH = 8
)(
    input                                   clk,
    input                                   rst,
    input [DATA_WIDTH-1:0]                  data_in,
    input                                   write_en,
    input                                   read_en,
    output                                  full,
    output                                  empty,
    output [DATA_WIDTH-1:0]                 data_out
);
    reg [DATA_WIDTH-1:0]                    buffer_mem [0:BUFFER_SIZE-1];
    reg [$clog2(BUFFER_SIZE)-1:0]           write_ptr;
    reg [$clog2(BUFFER_SIZE)-1:0]           read_ptr;
    reg [$clog2(BUFFER_SIZE):0]             buffer_count;

    generate
        genvar i;
        for (i = 0; i < BUFFER_SIZE; i = i + 1) begin
            always @(posedge clk) begin
                if (rst) begin
                    buffer_mem[i] <= '0;
                end
            end
        end
    endgenerate

    // Write logic
    always @(posedge clk) begin
        if (rst) begin
            write_ptr               <= 0;
            buffer_count            <= 0;
        end else if (write_en && (!full || read_en)) begin
            buffer_mem[write_ptr]   <= data_in;
            write_ptr               <= (write_ptr + 1) % BUFFER_SIZE;
            if (!full || (full && read_en)) begin
                buffer_count        <= buffer_count + 1;
            end
        end
    end

    // Read logic
    always @(posedge clk) begin
        if (rst) begin
            read_ptr                <= 0;
        end else if (read_en && !empty) begin
            read_ptr                <= (read_ptr + 1) % BUFFER_SIZE;
            buffer_count            <= buffer_count - 1;
        end
    end

    assign data_out     = buffer_mem[read_ptr];
    assign full         = (buffer_count == BUFFER_SIZE);
    assign empty        = (buffer_count == 0);
endmodule