timeunit 1ns; timeprecision 1ps;

module top #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned ACCUM_WIDTH = 48,
    parameter int unsigned N = 16,
    parameter int unsigned DEPTH = 256,
    parameter int unsigned ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst_n,
    input logic start,

    // host port 
    input logic wr_en_a,
    input logic wr_en_b,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [N*DATA_WIDTH-1:0] wr_data,

    input logic [$clog2(N)-1:0] rd_row, rd_col,
    output logic signed [ACCUM_WIDTH-1:0] result,
    output logic done,

    output logic controller_error,
    output logic sa_error,
    output logic error_detected
);

    // BRAM read bus
    logic [N*DATA_WIDTH-1:0] bram_a_dout, bram_b_dout;
    logic [ADDR_WIDTH-1:0] rd_addr_a, rd_addr_b;
    logic bram_en, clear;

    logic signed [N-1:0][DATA_WIDTH-1:0]  sa_data, sa_weight;
    logic signed [N-1:0][N-1:0][ACCUM_WIDTH-1:0] sa_result;
    logic sa_done;
    logic feed_valid; // high during FEED stage

    genvar i;
    generate
        for (i = 0; i < N; i++) begin : unpack
            assign sa_data[i] = feed_valid ? $signed(bram_a_dout[i*DATA_WIDTH +: DATA_WIDTH]) : '0;
            assign sa_weight[i] = feed_valid ? $signed(bram_b_dout[i*DATA_WIDTH +: DATA_WIDTH]) : '0;
        end
    endgenerate
    
    always_comb begin
        result = signed'(sa_result[rd_row][rd_col]);
        done = sa_done && !error_detected;
        error_detected = controller_error | sa_error;
    end

    // bram a
    bram #(.DATA_WIDTH(N*DATA_WIDTH), .DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) bram_a_inst (
        .i_a_clk(clk),
        .i_a_wr_en(wr_en_a),
        .i_a_addr(wr_addr),
        .i_a_din(wr_data),
        .i_b_clk(clk),
        .i_b_en(bram_en),
        .i_b_addr(rd_addr_a),
        .o_b_dout(bram_a_dout)
    );

    // bram b
    bram #(.DATA_WIDTH(N*DATA_WIDTH), .DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) bram_b_inst (
        .i_a_clk(clk),
        .i_a_wr_en(wr_en_b),
        .i_a_addr(wr_addr),
        .i_a_din(wr_data),
        .i_b_clk(clk),
        .i_b_en(bram_en),
        .i_b_addr(rd_addr_b),
        .o_b_dout(bram_b_dout)
    );

    // controller
    controller #(.N(N), .ADDR_WIDTH(ADDR_WIDTH)) ctrl_inst (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_start(start),
        .i_done(sa_done),
        .o_clear(clear),
        .o_bram_en(bram_en),
        .o_addr_a(rd_addr_a),
        .o_addr_b(rd_addr_b),
        .o_valid(feed_valid),
        .o_error(controller_error)
    );

    systolic_array #( .DATA_WIDTH (DATA_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH), .N(N) ) sa_inst (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_clear(clear),
        .i_data(sa_data),
        .i_weight(sa_weight),
        .o_result(sa_result),
        .o_done(sa_done),
        .o_error(sa_error)
    );

endmodule