// Processing Element
timeunit 1ns; timeprecision 1ps;

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
)(
    input logic i_clk,
    input logic rst_n,
    input logic signed [DATA_WIDTH-1:0] i_data,
    input logic signed [DATA_WIDTH-1:0] i_weight,
    input logic signed [ACCUM_WIDTH-1:0] i_psum,
    
    output logic signed [DATA_WIDTH-1:0] o_data,
    output logic signed [DATA_WIDTH-1:0] o_weight,
    output logic signed [ACCUM_WIDTH-1:0] o_psum
);
    logic signed [DATA_WIDTH-1:0] data_r, weight_r;
    logic signed [ACCUM_WIDTH-1:0] psum_r;
    logic signed [2*ACCUM_WIDTH-1:0] mult_r;
    logic signed [ACCUM_WIDTH-1:0] mac_r;

    always_ff @(posedge i_clk) begin
        if (!rst_n) begin
            data_r   <= '0;
            weight_r <= '0;
            psum_r   <= '0;
            mult_r   <= '0;
            mac_r    <= '0;
            o_psum   <= '0;
            o_data   <= '0;
            o_weight <= '0;
        end else begin
            data_r <= i_data;
            weight_r <= i_weight;
            psum_r <= i_psum;
            mult_r <= data_r * weight_r; // Mult stage
            mac_r <= psum_r + mult_r;   // Add stage
            o_psum <= mac_r;
            o_data <= data_r;
            o_weight <= weight_r;
        end
    end

endmodule