`timescale 1ns/1ps

// Dual-port RAM with host and controller ports
//
// Simple dual-port RAM with independent host and controller access ports.
// Host port is typically used for initialization (writes), controller port for
// runtime access (reads/writes). Both ports can access memory simultaneously
// with controller port taking precedence on conflicts.
//
// Parameters:
//   DATA_WIDTH: Bit width of data words
//   ADDR_WIDTH: Address bus width (memory depth is 2^ADDR_WIDTH)
//
// Behavior:
//   - Host port: Write when host_en && host_we, read when host_en && ~host_we
//   - Controller port: Write when ctrl_en && ctrl_we, read when ctrl_en && ~ctrl_we
//   - Memory initialized to zero on reset
//   - Read data available one cycle after address/enable
//   - Write operations are synchronous on clock edge

module simple_dp_ram #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10
)(
    input                          clk,
    input                          rst,
    input                          host_en,
    input                          host_we,
    input      [ADDR_WIDTH-1:0]    host_addr,
    input      [DATA_WIDTH-1:0]    host_wdata,
    output reg [DATA_WIDTH-1:0]    host_rdata,
    input                          ctrl_en,
    input                          ctrl_we,
    input      [ADDR_WIDTH-1:0]    ctrl_addr,
    input      [DATA_WIDTH-1:0]    ctrl_wdata,
    output reg [DATA_WIDTH-1:0]    ctrl_rdata
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer init_idx;

    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
            mem[init_idx] = '0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            host_rdata <= '0;
            ctrl_rdata <= '0;
        end else begin
            if (host_en && host_we) begin
                mem[host_addr] <= host_wdata;
            end

            if (ctrl_en) begin
                if (ctrl_we) begin
                    mem[ctrl_addr] <= ctrl_wdata;
                end
                ctrl_rdata <= mem[ctrl_addr];
            end

            if (host_en && ~host_we) begin
                host_rdata <= mem[host_addr];
            end
        end
    end

endmodule
