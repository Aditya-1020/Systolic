module top #(
    parameter int N = 4,
    parameter int DATA_WIDTH  = 8,
    parameter int ACCUM_WIDTH = 2*DATA_WIDTH + $clog2(N) + 8
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_start,
    input logic wr_en_a,
    input logic wr_en_b,
    input logic [$clog2(2*N-1)-1:0] wr_addr,
    input logic [N*DATA_WIDTH-1:0]  wr_data,
    input logic [$clog2(N)-1:0]     rd_row,
    input logic [$clog2(N)-1:0]     rd_col,
    output logic signed [ACCUM_WIDTH-1:0] result,
    output logic done,
    output logic error,
    output logic ctrl_error,
    output logic sa_error
);
    localparam int FEED_LEN  = 2*N - 1;
    localparam int CNT_W     = $clog2(FEED_LEN + 1);
    localparam int ADDR_WIDTH = $clog2(FEED_LEN);
    localparam int ROW_WIDTH = N * DATA_WIDTH;

    logic clear_sig;
    logic [ADDR_WIDTH-1:0] addr_a_sig, addr_b_sig;
    logic valid_sig, swap_sig;
    logic sa_done_sig, sa_error_sig, ctrl_error_sig;
    logic [ROW_WIDTH-1:0] buf_a_dout, buf_b_dout;

    logic signed [N-1:0][DATA_WIDTH-1:0] sa_data, sa_weight;
    logic signed [N-1:0][N-1:0][ACCUM_WIDTH-1:0] sa_result;

    genvar i;
    generate
        for (i = 0; i < N; i++) begin : gen_unpack
            assign sa_data[i]   = $signed(buf_a_dout[i*DATA_WIDTH +: DATA_WIDTH]);
            assign sa_weight[i] = $signed(buf_b_dout[i*DATA_WIDTH +: DATA_WIDTH]);
        end
    endgenerate

    assign done       = sa_done_sig & ~error;
    assign sa_error   = sa_error_sig;
    assign ctrl_error = ctrl_error_sig;
    assign error      = ctrl_error_sig | sa_error_sig;

    buffer #(
        .DEPTH      (FEED_LEN),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ROW_WIDTH  (ROW_WIDTH)
    ) buf_a (
        .i_clk     (i_clk),
        .i_rst_n   (i_rst_n),
        .i_wr_en   (wr_en_a),
        .i_wr_addr (wr_addr),
        .i_wr_data (wr_data),
        .i_swap    (swap_sig),
        .i_rd_addr (addr_a_sig),
        .o_rd_data (buf_a_dout)
    );

    buffer #(
        .DEPTH      (FEED_LEN),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ROW_WIDTH  (ROW_WIDTH)
    ) buf_b (
        .i_clk     (i_clk),
        .i_rst_n   (i_rst_n),
        .i_wr_en   (wr_en_b),
        .i_wr_addr (wr_addr),
        .i_wr_data (wr_data),
        .i_swap    (swap_sig),
        .i_rd_addr (addr_b_sig),
        .o_rd_data (buf_b_dout)
    );

    controller #(
        .FEED_LEN   (FEED_LEN),
        .CNT_W      (CNT_W),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) ctrl_inst (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_start  (i_start),
        .i_done   (sa_done_sig),
        .o_clear  (clear_sig),
        .o_addr_a (addr_a_sig),
        .o_addr_b (addr_b_sig),
        .o_valid  (valid_sig),
        .o_swap   (swap_sig),
        .o_error  (ctrl_error_sig)
    );

    systolic_array #(
        .N           (N),
        .DATA_WIDTH  (DATA_WIDTH),
        .ACCUM_WIDTH (ACCUM_WIDTH)
    ) sa_inst (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_clear  (clear_sig),
        .i_valid  (valid_sig),
        .i_data   (sa_data),
        .i_weight (sa_weight),
        .o_result (sa_result),
        .o_done   (sa_done_sig),
        .o_error  (sa_error_sig)
    );

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            result <= '0;
        end else begin
            result <= $signed(sa_result[rd_row][rd_col]);
        end
    end

endmodule
