`timescale 1ns/1ps

module systolic_top #(
    parameter INPUT_WIDTH = 16,
    parameter RESULT_WIDTH = 16,
    parameter FRAC_WIDTH = 15,
    parameter ADDR_WIDTH = 10
)(
    input                           clk,
    input                           rst,
    // Data memory A host write port
    input      [ADDR_WIDTH-1:0]     addrA,
    input                           enA,
    input      [INPUT_WIDTH-1:0]    dataA,
    // Data memory B host write port
    input      [ADDR_WIDTH-1:0]     addrB,
    input                           enB,
    input      [INPUT_WIDTH-1:0]    dataB,
    // Instruction memory host write port
    input      [ADDR_WIDTH-1:0]     addrI,
    input                           enI,
    input      [INPUT_WIDTH-1:0]    dataI,
    // Output memory host read port
    input      [ADDR_WIDTH-1:0]     addrO,
    output     [RESULT_WIDTH-1:0]   dataO,
    // Control
    input                           ap_start,
    output                          ap_done
);

    // Memory wires
    wire [INPUT_WIDTH-1:0]  data_a_ctrl_rdata;
    wire [INPUT_WIDTH-1:0]  data_b_ctrl_rdata;
    wire [INPUT_WIDTH-1:0]  inst_ctrl_rdata;
    wire [RESULT_WIDTH-1:0] result_host_rdata;

    wire                  controller_tile_clear;
    wire                  controller_feed_valid;
    wire [INPUT_WIDTH*4-1:0] controller_row_bus;
    wire [INPUT_WIDTH*4-1:0] controller_col_bus;
    wire                  array_ready;
    wire                  array_tile_done;
    wire [RESULT_WIDTH*16-1:0] array_tile_results;

    wire                  ctrl_data_a_en;
    wire [ADDR_WIDTH-1:0] ctrl_data_a_addr;
    wire                  ctrl_data_b_en;
    wire [ADDR_WIDTH-1:0] ctrl_data_b_addr;
    wire                  ctrl_inst_en;
    wire [ADDR_WIDTH-1:0] ctrl_inst_addr;
    wire                  ctrl_res_en;
    wire                  ctrl_res_we;
    wire [ADDR_WIDTH-1:0] ctrl_res_addr;
    wire [RESULT_WIDTH-1:0] ctrl_res_wdata;

    simple_dp_ram #(
        .DATA_WIDTH (INPUT_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) data_mem_a (
        .clk        (clk),
        .rst        (rst),
        .host_en    (enA),
        .host_we    (1'b1),
        .host_addr  (addrA),
        .host_wdata (dataA),
        .host_rdata (),
        .ctrl_en    (ctrl_data_a_en),
        .ctrl_we    (1'b0),
        .ctrl_addr  (ctrl_data_a_addr),
        .ctrl_wdata ('0),
        .ctrl_rdata (data_a_ctrl_rdata)
    );

    simple_dp_ram #(
        .DATA_WIDTH (INPUT_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) data_mem_b (
        .clk        (clk),
        .rst        (rst),
        .host_en    (enB),
        .host_we    (1'b1),
        .host_addr  (addrB),
        .host_wdata (dataB),
        .host_rdata (),
        .ctrl_en    (ctrl_data_b_en),
        .ctrl_we    (1'b0),
        .ctrl_addr  (ctrl_data_b_addr),
        .ctrl_wdata ('0),
        .ctrl_rdata (data_b_ctrl_rdata)
    );

    simple_dp_ram #(
        .DATA_WIDTH (INPUT_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) inst_mem (
        .clk        (clk),
        .rst        (rst),
        .host_en    (enI),
        .host_we    (1'b1),
        .host_addr  (addrI),
        .host_wdata (dataI),
        .host_rdata (),
        .ctrl_en    (ctrl_inst_en),
        .ctrl_we    (1'b0),
        .ctrl_addr  (ctrl_inst_addr),
        .ctrl_wdata ('0),
        .ctrl_rdata (inst_ctrl_rdata)
    );

    simple_dp_ram #(
        .DATA_WIDTH (RESULT_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) result_mem (
        .clk        (clk),
        .rst        (rst),
        .host_en    (1'b1),
        .host_we    (1'b0),
        .host_addr  (addrO),
        .host_wdata ('0),
        .host_rdata (result_host_rdata),
        .ctrl_en    (ctrl_res_en),
        .ctrl_we    (ctrl_res_we),
        .ctrl_addr  (ctrl_res_addr),
        .ctrl_wdata (ctrl_res_wdata),
        .ctrl_rdata ()
    );

    assign dataO = result_host_rdata;

    systolic_array_4x4 #(
        .INPUT_WIDTH   (INPUT_WIDTH),
        .ACC_WIDTH     (RESULT_WIDTH),
        .FRAC_WIDTH    (FRAC_WIDTH),
        .VECTOR_LENGTH (4)
    ) u_array (
        .clk             (clk),
        .rst             (rst),
        .tile_clear      (controller_tile_clear),
        .feed_valid      (controller_feed_valid),
        .row_data_bus    (controller_row_bus),
        .col_data_bus    (controller_col_bus),
        .ready_for_feed  (array_ready),
        .tile_done       (array_tile_done),
        .tile_result_flat(array_tile_results)
    );

    systolic_controller #(
        .INPUT_WIDTH   (INPUT_WIDTH),
        .RESULT_WIDTH  (RESULT_WIDTH),
        .FRAC_WIDTH    (FRAC_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .VECTOR_LENGTH (4)
    ) u_controller (
        .clk             (clk),
        .rst             (rst),
        .ap_start        (ap_start),
        .ap_done         (ap_done),
        .data_a_en       (ctrl_data_a_en),
        .data_a_addr     (ctrl_data_a_addr),
        .data_a_rdata    (data_a_ctrl_rdata),
        .data_b_en       (ctrl_data_b_en),
        .data_b_addr     (ctrl_data_b_addr),
        .data_b_rdata    (data_b_ctrl_rdata),
        .inst_en         (ctrl_inst_en),
        .inst_addr       (ctrl_inst_addr),
        .inst_rdata      (inst_ctrl_rdata),
        .result_en       (ctrl_res_en),
        .result_we       (ctrl_res_we),
        .result_addr     (ctrl_res_addr),
        .result_wdata    (ctrl_res_wdata),
        .tile_clear      (controller_tile_clear),
        .feed_valid      (controller_feed_valid),
        .row_data_bus    (controller_row_bus),
        .col_data_bus    (controller_col_bus),
        .ready_for_feed  (array_ready),
        .tile_done       (array_tile_done),
        .tile_result_flat(array_tile_results)
    );

endmodule

