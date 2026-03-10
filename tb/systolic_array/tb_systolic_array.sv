timeunit 1ns; timeprecision 1ps;

`ifndef N
    `define N 4
`endif

module tb_systolic_array;

    parameter DATA_WIDTH  = 8;
    parameter ACCUM_WIDTH = 32;
    parameter N = `N;

    localparam TOTAL_CYCLES = 2 * N - 1;
    localparam RUN_CYCLES   = 3 * N;
    // localparam PIPE_DELAY   = 2;

    logic clk, rst_n;
    logic signed [N-1:0][DATA_WIDTH-1:0] data, weight;
    logic signed [N-1:0][N-1:0][ACCUM_WIDTH-1:0] result;
    logic done;

    systolic_array #(.DATA_WIDTH(DATA_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH), .N(N)) dut (
        .i_clk    (clk),
        .i_rst_n  (rst_n),
        .i_data   (data),
        .i_weight (weight),
        .o_result (result),
        .o_done   (done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int pass_count = 0;
    int fail_count = 0;

    logic [DATA_WIDTH-1:0] raw_a [0:TOTAL_CYCLES-1][0:N-1];
    logic [DATA_WIDTH-1:0] raw_b [0:TOTAL_CYCLES-1][0:N-1];
    logic [ACCUM_WIDTH-1:0] raw_gold [0:N*N-1];

    logic signed [DATA_WIDTH-1:0] tv_a [0:TOTAL_CYCLES-1][0:N-1];
    logic signed [DATA_WIDTH-1:0] tv_b [0:TOTAL_CYCLES-1][0:N-1];
    logic signed [ACCUM_WIDTH-1:0] gold_c [0:N-1][0:N-1];

    task automatic reset_dut;
        rst_n = 0; data = '0; weight = '0;
        repeat(2) @(posedge clk);
        rst_n = 1; @(posedge clk); #1;
    endtask

    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);

        $readmemh("tv_a.hex",   raw_a);
        $readmemh("tv_b.hex",   raw_b);
        $readmemh("gold_c.hex", raw_gold);

        for (int t = 0; t < TOTAL_CYCLES; t++)
            for (int n = 0; n < N; n++) begin
                tv_a[t][n] = signed'(raw_a[t][n]);
                tv_b[t][n] = signed'(raw_b[t][n]);
            end

        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                gold_c[i][j] = signed'(raw_gold[i*N + j]);

        reset_dut();

        // feed staggered input for TOTAL_CYCLES then zeros till RUN_CYCLES
        for (int t = 0; t < RUN_CYCLES; t++) begin
            if (t < TOTAL_CYCLES) begin
                for (int n = 0; n < N; n++) begin
                    data[n]   = tv_a[t][n];
                    weight[n] = tv_b[t][n];
                end
            end else begin
                data   = '0;
                weight = '0;
            end
            @(posedge clk); #1;
        end

        repeat(dut.o_done) @(posedge clk); #1; // wait pipeline drain

        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                if (result[i][j] !== gold_c[i][j]) begin
                    $error("FAIL C[%0d][%0d]: got=%0d exp=%0d",
                           i, j, result[i][j], gold_c[i][j]);
                    fail_count++;
                end else
                    pass_count++;

        $display("PASS: %0d  FAIL: %0d  TOTAL: %0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TEST(S) FAILED");

        repeat(5) @(posedge clk);
        $finish;
    end

endmodule