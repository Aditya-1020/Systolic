// skew buffer: diagonal input skew for nxn array
// delayred row r by r cycles and col c by c cylces

module skew_buffer #(
    parameter int N = 4,
    parameter int DATA_WIDTH = 8
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_valid,
    input logic signed [N-1:0][DATA_WIDTH-1:0] i_data,
    input logic signed [N-1:0][DATA_WIDTH-1:0] i_weight,
    output logic signed [N-1:0][DATA_WIDTH-1:0] o_data,
    output logic signed [N-1:0][DATA_WIDTH-1:0] o_weight
);
    logic signed [N-1:0][N-1:0][DATA_WIDTH-1:0] data_r;
    logic signed [N-1:0][N-1:0][DATA_WIDTH-1:0] weight_r;

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            data_r <= '0;
            weight_r <= '0;
        end else begin
            for (int k = 0; k < N; k++) begin
                data_r[k][0] <= i_valid ? i_data[k] : '0;
                weight_r[k][0] <= i_valid ? i_weight[k] : '0;
                for (int s=1; s < N; s++) begin
                    data_r[k][s] <= data_r[k][s-1];
                    weight_r[k][s] <= weight_r[k][s-1];
                end
            end
        end 
    end

    genvar i;
    generate
        for (i =0; i < N; i++) begin : gen_skew_out
            assign o_data[i] = data_r[i][i];
            assign o_weight[i] = weight_r[i][i];
        end
    endgenerate
endmodule
