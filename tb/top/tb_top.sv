timeunit 1ns; timeprecision 1ps;

`ifndef N
    `define N 4
`endif

module tb_top;

    localparam int unsigned DATA_WIDTH  = 8;
    localparam int unsigned ACCUM_WIDTH = 48;
    localparam int unsigned N = `N;
    localparam int unsigned DEPTH = 256;
    localparam int unsigned ADDR_WIDTH = $clog2(DEPTH);

    localparam int unsigned ROW_BITS = N * DATA_WIDTH;
    localparam int unsigned FEED_ROWS = 2 * N - 1;

    localparam int unsigned NUM_CORNERS = 3;
    `ifndef NUM
        `define NUM 10
    `endif
    localparam int unsigned NUM_CASES = NUM_CORNERS + `NUM;

    // timout
    localparam int unsigned CYCLES_PER_TEST = 4 * FEED_ROWS + 4 * N + 50;
    localparam int unsigned TIMEOUT_CYCLES  = NUM_CASES * CYCLES_PER_TEST;

    logic clk, rst_n, start;
    logic wr_en_a, wr_en_b;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [ROW_BITS-1:0] wr_data;
    logic [$clog2(N)-1:0] rd_row, rd_col;
    logic signed [ACCUM_WIDTH-1:0] result;
    logic done;
    logic controller_error, sa_error, error_detected;

    top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .N          (N),
        .DEPTH      (DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
     ) top (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .wr_en_a         (wr_en_a),
        .wr_en_b         (wr_en_b),
        .wr_addr         (wr_addr),
        .wr_data         (wr_data),
        .rd_row          (rd_row),
        .rd_col          (rd_col),
        .result          (result),
        .done            (done),
        .controller_error(controller_error),
        .sa_error        (sa_error),
        .error_detected  (error_detected)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // vector load
    logic [ROW_BITS-1:0] raw_a [0:NUM_CASES*FEED_ROWS - 1];
    logic [ROW_BITS-1:0] raw_b [0:NUM_CASES*FEED_ROWS - 1];
    logic [ACCUM_WIDTH-1:0] raw_gold [0:NUM_CASES*N*N - 1];
    logic signed [ACCUM_WIDTH-1:0] gold [0:NUM_CASES-1][0:N-1][0:N-1]; // gold[case][row][col]

    int pass_count = 0;
    int fail_count = 0;

    task automatic reset_dut();
        rst_n    = 1'b0;
        start    = 1'b0;
        wr_en_a  = 1'b0;
        wr_en_b  = 1'b0;
        wr_addr  = '0;
        wr_data  = '0;
        rd_row   = '0;
        rd_col   = '0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
        $display("[RESET] DUT reset complete at t=%0t", $time);
    endtask
    
    task automatic write_matrix(
        input int unsigned base_idx,
        input logic        is_a
    );
        for (int row = 0; row < int'(FEED_ROWS); row++) begin
            @(posedge clk); #1;
            wr_addr = ADDR_WIDTH'(row);
            if (is_a) begin
                wr_en_a = 1'b1;
                wr_en_b = 1'b0;
                wr_data = raw_a[base_idx * FEED_ROWS + row];
            end else begin
                wr_en_a = 1'b0;
                wr_en_b = 1'b1;
                wr_data = raw_b[base_idx * FEED_ROWS + row];
            end
        end
        @(posedge clk); #1;
        wr_en_a = 1'b0;
        wr_en_b = 1'b0;
    endtask

    task automatic run_and_wait(output logic timed_out);
        int unsigned watchdog;
        timed_out = 1'b0;
        watchdog  = 0;

        @(posedge clk); #1;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;

        while (!done && watchdog < CYCLES_PER_TEST) begin
            @(posedge clk); #1;
            watchdog++;
        end

        if (watchdog >= CYCLES_PER_TEST) begin
            $error("[TIMEOUT] done never asserted for test case");
            timed_out = 1'b1;
        end
    endtask

    task automatic check_results(input int unsigned case_idx);
        logic signed [ACCUM_WIDTH-1:0] got;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                rd_row = $clog2(N)'(i);
                rd_col = $clog2(N)'(j);
                #1;
                got = result;
                if (got !== gold[case_idx][i][j]) begin
                    $error("[FAIL] case=%0d C[%0d][%0d]: got=%0d exp=%0d",case_idx, i, j, got, gold[case_idx][i][j]);
                    fail_count++;
                end else begin
                    pass_count++;
                end
            end
        end
    endtask

    task automatic reset_between_tests();
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    // error monitor
    always @(posedge clk) begin
        if (error_detected) begin
            $error("[ERROR] error_detected asserted @ t:%0t ctrl:%b, sa=%b", $time, controller_error, sa_error);
        end
    end

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        $readmemh("tv_a_rows.hex", raw_a);
        $readmemh("tv_b_rows.hex", raw_b);
        $readmemh("gold_c.hex",    raw_gold);

        // unpack gold into 3d arr
        for (int c = 0; c < NUM_CASES; c++) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    gold[c][i][j] = signed'(raw_gold[c*N*N + i*N + j]);
                end
            end
        end

        $display("\n[INIT] Loaded %0d test cases, N=%0d, FEED_ROWS=%0d\n", NUM_CASES, N, FEED_ROWS);
        reset_dut();

        // run cases
        for (int tc = 0; tc < NUM_CASES; tc++) begin
            logic timed_out;
            $display("[TEST] case %0d/%0d at t=%0t", tc, NUM_CASES-1, $time);

            write_matrix(tc, 1'b1);  // A to BRAM_A
            write_matrix(tc, 1'b0);  // B to BRAM_B

            @(posedge clk); #1;

            run_and_wait(timed_out);

            if (!timed_out) begin
                if (error_detected) begin
                    $error("[FAIL] case=%0d hardware error flagged", tc);
                    fail_count++;
                end else begin
                    check_results(tc);
                end
            end else begin
                fail_count++;
            end

            reset_between_tests();
        end

        // summary
        $display("Summary: pass:%0d, fail:%0d, total%0d", pass_count, fail_count, pass_count+fail_count);
        $display("%s", fail_count == 0 ? "all tests passed" : "some test(s) failed");
        
        repeat(10) @(posedge clk);
        $finish;
    end

    initial begin
        #(TIMEOUT_CYCLES * 10ns + 5ms);
        $error("{TIMEOUT}: Tb did not compile in time");
        $finish;
    end

endmodule