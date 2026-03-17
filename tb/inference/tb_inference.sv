timeunit 1ns; timeprecision 1ps;

`ifndef N
    `define N 4
`endif

`ifndef CLK_NS
    `define CLK_NS 5.0
`endif

module tb_inference;
    localparam int unsigned DATA_WIDTH = 8;
    localparam int unsigned N = `N;
    localparam int unsigned ACCUM_WIDTH = 2*DATA_WIDTH + $clog2(N) + 8;
    localparam int unsigned FEED_LEN = 2*N - 1;
    localparam int unsigned BUF_ADDR_WIDTH = $clog2(FEED_LEN);
    localparam int unsigned ROW_BITS = N * DATA_WIDTH;
    localparam int unsigned FC2_ROWS = 10;
    localparam int unsigned FC2_COLS = 64;
    localparam int unsigned PAD_ROWS = ((FC2_ROWS + N - 1) / N) * N;
    localparam int unsigned PAD_COLS = ((FC2_COLS + N - 1) / N) * N;
    localparam int unsigned N_ROW_TILES = PAD_ROWS / N;
    localparam int unsigned N_COL_TILES = PAD_COLS / N;
    localparam int unsigned N_TILES     = N_ROW_TILES * N_COL_TILES;

    localparam int unsigned TOTAL_FEED_ROWS = N_TILES * FEED_LEN;
    localparam int unsigned GOLD_ELEMS      = N_TILES * N * N;

    // DONE_CYCLE = 3*N, feed = FEED_LEN, margin
    localparam int unsigned CYCLES_PER_TILE = 3*N + FEED_LEN;
    localparam int unsigned TIMEOUT_CYCLES  = N_TILES * CYCLES_PER_TILE + 200;

    logic clk, rst_n, start;
    logic wr_en_a, wr_en_b;
    logic [BUF_ADDR_WIDTH-1:0] wr_addr;
    logic [ROW_BITS-1:0] wr_data;
    logic [$clog2(N)-1:0] rd_row, rd_col;
    logic signed [ACCUM_WIDTH-1:0] result;
    logic done;
    logic controller_error, sa_error, error_sig;

    top #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) dut (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .i_start    (start),
        .wr_en_a    (wr_en_a),
        .wr_en_b    (wr_en_b),
        .wr_addr    (wr_addr),
        .wr_data    (wr_data),
        .rd_row     (rd_row),
        .rd_col     (rd_col),
        .result     (result),
        .done       (done),
        .ctrl_error (controller_error),
        .sa_error   (sa_error),
        .error      (error_sig)
    );

    initial clk = 0;
    always #(`CLK_NS) clk = ~clk;

    // Vector storage — sized for new FEED_LEN
    logic [ROW_BITS-1:0] raw_a [0:TOTAL_FEED_ROWS-1];
    logic [ROW_BITS-1:0] raw_b [0:TOTAL_FEED_ROWS-1];
    logic [ACCUM_WIDTH-1:0] raw_gold [0:GOLD_ELEMS-1];
    logic signed [ACCUM_WIDTH-1:0] gold [0:N_TILES-1][0:N-1][0:N-1];

    int pass_count = 0;
    int fail_count = 0;
    string vec_dir = "inference_vectors";
    string suffix;

    task automatic reset_dut();
        rst_n   = 1'b0; start   = 1'b0;
        wr_en_a = '0;   wr_en_b = '0;
        wr_addr = '0;   wr_data = '0;
        rd_row  = '0;   rd_col  = '0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
        $display("[RESET] DUT @ t=%0t", $time);
    endtask

    task automatic load_tile(input int unsigned tile_idx, input logic is_a);
        int unsigned base = tile_idx * FEED_LEN;
        for (int row = 0; row < int'(FEED_LEN); row++) begin
            @(posedge clk); #1;
            wr_addr = BUF_ADDR_WIDTH'(row);
            if (is_a) begin
                wr_en_a = 1'b1; wr_en_b = 1'b0;
                wr_data = raw_a[base + row];
            end else begin
                wr_en_a = 1'b0; wr_en_b = 1'b1;
                wr_data = raw_b[base + row];
            end
        end
        @(posedge clk); #1;
        wr_en_a = 1'b0; wr_en_b = 1'b0;
    endtask

    task automatic run_wait(output logic timed_out);
        int unsigned wd = 0;
        timed_out = 1'b0;
        @(posedge clk); #1; start = 1'b1;
        @(posedge clk); #1; start = 1'b0;
        while (!done && wd < CYCLES_PER_TILE) begin
            @(posedge clk); #1;
            wd++;
        end
        if (wd >= CYCLES_PER_TILE) begin
            $error("[TIMEOUT] tile did not complete within %0d cycles", CYCLES_PER_TILE);
            timed_out = 1'b1;
        end
    endtask

    task automatic check_tile(input int unsigned tile_index);
        logic signed [ACCUM_WIDTH-1:0] dut_result;
        for (int r = 0; r < int'(N); r++) begin
            for (int c = 0; c < int'(N); c++) begin
                rd_row = ($clog2(N))'(r);
                rd_col = ($clog2(N))'(c);
                @(posedge clk); #1;
                dut_result = result;
                if (dut_result !== gold[tile_index][r][c]) begin
                    $error("[FAIL] tile:%0d [%0d][%0d]: got=%0d exp=%0d", tile_index, r, c, dut_result, gold[tile_index][r][c]);
                    fail_count++;
                end else begin
                    pass_count++;
                end
            end
        end
    endtask

    task automatic soft_reset();
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    always @(posedge clk) begin
        if (error_sig)
            $error("[HW ERROR] ctrl=%b sa=%b @t=%0t", controller_error, sa_error, $time);
    end

    initial begin
        $dumpfile("tb_inference.vcd");
        $dumpvars(0, tb_inference);

        suffix = $sformatf("_N%0d", N);
        $readmemh({vec_dir, "/sv_fc2_a",    suffix, ".hex"}, raw_a);
        $readmemh({vec_dir, "/sv_fc2_b",    suffix, ".hex"}, raw_b);
        $readmemh({vec_dir, "/sv_fc2_gold", suffix, ".hex"}, raw_gold);

        for (int t = 0; t < int'(N_TILES); t++) begin
            for (int r = 0; r < int'(N); r++) begin
                for (int c = 0; c < int'(N); c++) begin
                    gold[t][r][c] = signed'(raw_gold[t*N*N + r*N + c]);
                end
            end
        end

        $display("[INIT] N=%0d  FC2 padded %0dx%0d  ->  %0dx%0d = %0d tiles", N, PAD_ROWS, PAD_COLS, N_ROW_TILES, N_COL_TILES, N_TILES);
        $display("[INIT] FEED_LEN=%0d  total feed rows=%0d  gold elements=%0d", FEED_LEN, TOTAL_FEED_ROWS, GOLD_ELEMS);

        reset_dut();

        for (int tile = 0; tile < int'(N_TILES); tile++) begin
            logic timed_out;
            $display("[TILE] %0d/%0d  row-tile=%0d  col-tile=%0d", tile, N_TILES-1, tile/int'(N_COL_TILES), tile%int'(N_COL_TILES));

            load_tile(tile, 1'b1);
            load_tile(tile, 1'b0);
            @(posedge clk); #1;
            run_wait(timed_out);

            if (!timed_out) begin
                if (error_sig) begin
                    $error("[FAIL] tile=%0d hardware error", tile);
                    fail_count++;
                end else begin
                    check_tile(tile);
                end
            end else begin
                fail_count++;
            end

            soft_reset();
        end

        $display("\nINFERENCE SUMMARY (N=%0d)", N);
        $display("- Tiles: %0d  (%0dx%0d)", N_TILES, N_ROW_TILES, N_COL_TILES);
        $display("- Elements: %0d", N_TILES * N * N);
        $display("- Pass: %0d", pass_count);
        $display("- Fail: %0d", fail_count);
        $display("- Latency: ~%0d cycles/tile x %0d tiles = ~%0d total cycles",
                 CYCLES_PER_TILE, N_TILES, CYCLES_PER_TILE * N_TILES);
        $display("- Throughput: %.0f inferences/sec @ %.0f MHz", 1e9 / (2.0 * `CLK_NS * real'(CYCLES_PER_TILE * N_TILES)), 500.0 / `CLK_NS);
        $display("%s", fail_count == 0 ? "ALL TILES PASSED" : "FAILURES DETECTED");

        repeat(10) @(posedge clk);
        $finish;
    end

    initial begin
        #(TIMEOUT_CYCLES * 10ns + 1ms);
        $error("[GLOBAL TIMEOUT] TB did not complete in TIME");
        $finish;
    end

endmodule
