// Processing Element: A*B accumulation
timeunit 1ns; timeprecision 1ps;

module pe #(
    parameter DATA_WIDTH  = 8,
    parameter ACCUM_WIDTH = 32
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_clear_accum,
    input logic signed [DATA_WIDTH-1:0] i_data,
    input logic signed [DATA_WIDTH-1:0] i_weight,
    output logic signed [DATA_WIDTH-1:0] o_data,
    output logic signed [DATA_WIDTH-1:0] o_weight,
    output logic signed [ACCUM_WIDTH-1:0] o_result
);
    localparam int unsigned MULT_WIDTH = 2*DATA_WIDTH;

    logic signed [DATA_WIDTH-1:0] data_r, weight_r;
    logic signed [MULT_WIDTH-1:0]  mult_r;
    logic signed [ACCUM_WIDTH-1:0] accum, next_accum;
    logic clear_d1, clear_d2;

    assign next_accum = clear_d2 ? '0 : accum + ACCUM_WIDTH'(mult_r);

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            data_r <= '0;
            weight_r <= '0;
            mult_r <= '0;
            accum <= '0;
            o_result <= '0;
            o_data <= '0;
            o_weight <= '0;
            clear_d1 <= '0;
            clear_d2 <= '0;
        end else begin
            clear_d1 <= i_clear_accum;
            clear_d2 <= clear_d1;
            data_r <= i_data;
            weight_r <= i_weight;
            mult_r <= signed'(data_r) * signed'(weight_r);
            accum <= next_accum;
            o_result <= next_accum;
            o_data <= i_data;
            o_weight <= i_weight;
        end
    end
endmodule