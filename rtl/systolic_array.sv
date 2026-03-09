// systolic_array.sv
timeunit 1ns; timeprecision 1ps;

module systolic_array #(
    parameter int DATA_WIDTH  = 8,
    parameter int ACCUM_WIDTH = 32,
    parameter int N = 8
)(
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_clear,
    input  logic signed [N-1:0][DATA_WIDTH-1:0] i_data,
    input  logic signed [N-1:0][DATA_WIDTH-1:0] i_weight,
    output logic signed [N-1:0][N-1:0][ACCUM_WIDTH-1:0] o_result,
    output logic o_done,
    output logic o_error
);
    localparam int unsigned DONE_CYCLE = 2*N;
    localparam int unsigned PIPE_STAGES = DONE_CYCLE-1;
    localparam int unsigned CNT_WIDTH = $clog2(DONE_CYCLE + 1);

    initial begin
        assert (N >= 2 && N <= 64) else $fatal(1, "N unsupported");
        assert (DATA_WIDTH <= 16) else $fatal(1, "DATA_WIDTH too wide");
        assert (PIPE_STAGES <= 128) else $fatal(1, "PIPE too deep");
    end
    logic signed [N-1:0][N:0][DATA_WIDTH-1:0] data_w;
    logic signed [N:0][N-1:0][DATA_WIDTH-1:0] weight_w;

    // clear pipeline
    logic [PIPE_STAGES-1:0][N*N-1:0] clear_pipe, next_clear_pipe;
    always_comb begin
        next_clear_pipe = clear_pipe;
        next_clear_pipe[0] = {N*N{i_clear}};
        for (int s = 1; s < PIPE_STAGES; s++) begin
            next_clear_pipe[s] = clear_pipe[s-1];
        end
    end

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            clear_pipe <= '0;
        end else begin
            clear_pipe <= next_clear_pipe;
        end
    end

    // Done counter
    logic [CNT_WIDTH-1:0] cycle_cnt;
    logic next_done, next_error;
    always_ff @(posedge i_clk) begin
        if (!i_rst_n || i_clear) begin
            cycle_cnt <= '0;
            o_done <= 1'b0;
            o_error <= 1'b0;
        end else begin
            o_done <= next_done;
            o_error <= next_error | o_error;
            if (cycle_cnt < DONE_CYCLE) begin
                cycle_cnt <= cycle_cnt + 1'b1;
            end else begin
                cycle_cnt <= cycle_cnt;
            end
        end
    end

    assign next_done = (cycle_cnt >= DONE_CYCLE);
    assign next_error = (cycle_cnt > DONE_CYCLE[$clog2(DONE_CYCLE+1)-1:0]);

    genvar r,c;
    generate
        for (r=0; r < N; r++) begin : gen_data_in
            assign data_w[r][0] = i_data[r];
        end
        for (c=0; c < N; c++) begin : gen_weight_in
            assign weight_w[0][c] = i_weight[c];
        end
    endgenerate

    // Pe grid
    generate
        for (r=0; r < N; r++) begin : row
            for (c=0; c < N; c++) begin : col
                pe #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACCUM_WIDTH(ACCUM_WIDTH)
                ) pe_inst (
                    .i_clk        (i_clk),
                    .i_rst_n      (i_rst_n),
                    .i_clear_accum(clear_pipe[r+c][r*N+c]),
                    .i_data       (signed'(data_w[r][c])),
                    .i_weight     (signed'(weight_w[r][c])),
                    .o_data       (data_w[r][c+1]),
                    .o_weight     (weight_w[r+1][c]),
                    .o_result     (o_result[r][c])
                );
            end
        end
    endgenerate

endmodule