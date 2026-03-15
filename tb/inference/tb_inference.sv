// tb_inference.sv
// feeds MNIST INT8 FC2 activations + weights through top_fpga
// checks accumulated outputs against Python golden model
// USAGE: make TB=tb_inference N=4 NUM=48  (48= 3 row* 16 cols)

timeunit 1ns; timeprecision 1ps;

`ifndef N
    `define N 4
`endif

module tb_inference;
    localparam int unsigned DATA_WIDTH = 8;
    localparam int unsigned ACCUM_WIDTH = 48;
    localparam int unsigned N = `N;
    localparam int unsigned DEPTH = 256;
    localparam int unsigned ADDR_WIDTH = $clog2(DEPTH);

    localparam int unsigned ROW_BITS = N * DATA_WIDTH;
    localparam int unsigned FEED_ROWS = 2 * N - 1;

    localparam int unsigned N_COL_TILES = 64 / N; // 16
    localparam int unsigned N_ROW_TILES = 12 / N; // 64
    localparam int unsigned N_TILES = N_ROW_TILES * N_COL_TILES; // 48
    localparam int unsigned TOTAL_FEED_ROWS = N_TILES * FEED_ROWS;
    localparam int unsigned GOLD_ELEMS = N_TILES * N * N;
    localparam int unsigned CYCLES_PER_TILE = 4 * FEED_ROWS + 4  * N * N + 20;
    localparam int unsigned TIMEOUT_CYCLES = N_TILES * CYCLES_PER_TILE + 100;

    logic clk, rst_n, start;
    logic wr_en_a, wr_en_b;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [ROW_BITS-1:0] wr_data;
    logic [$clog2(N)-1:0] rd_row, rd_col;
    logic signed [ACCUM_WIDTH-1:0] result;
    logic done;
    logic controller_error, sa_error, error_detected;

    top_fpga #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .N          (N),
        .DEPTH      (DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
     ) top_fpga (
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

    logic [ROW_BITS-1:0] raw_a [0:TOTAL_FEED_ROWS-1];
    logic [ROW_BITS-1:0] raw_b [0:TOTAL_FEED_ROWS-1];
    logic [ACCUM_WIDTH-1:0] raw_gold [0:GOLD_ELEMS-1];
    
    logic signed [ACCUM_WIDTH-1:0] gold [0:N_TILES-1][0:N-1][0:N-1];

    int pass_count = 0;
    int fail_count = 0;

    task automatic reset_dut();
        begin
            rst_n = 1'b0;
            start = 1'b0;
            wr_en_a = '0;
            wr_en_b = '0;
            wr_addr = '0;
            wr_data = '0;
            rd_row = '0;
            rd_col = '0;
            repeat(4) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk); #1;
            $display("[RESET] DUT @ t=%0t", $time);
        end
    endtask

    // write feed_rows staggered rows into BRAM for one tile
    task automatic load_tile(input int unsigned tile_idx, input logic is_a);
        int unsigned base = tile_idx * FEED_ROWS;
        for (int row = 0; row < FEED_ROWS; row++) begin
            @(posedge clk); #1;
            wr_addr = ADDR_WIDTH'(row);
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
            $error("TIMOUET: tile did not complete within %0d cycles", CYCLES_PER_TILE);
            timed_out = 1'b1;
        end
    endtask

    task automatic check_tile(input int unsigned tile_index);
        logic signed [ACCUM_WIDTH-1:0] dut_result;
        for (int r =0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                rd_row = $clog2(N)'(r);
                rd_col = $clog2(N)'(c);
                #1;
                dut_result = result;
                if (dut_result !== gold[tile_index][r][c]) begin
                    $error("FAIL : tile:%0d [%0d][%0d]: got=%0d, exp=%0d", tile_index, r, c, dut_result, gold[tile_index][r][c]);
                    fail_count++;
                end else begin pass_count++; end
            end
        end
    endtask

    task automatic soft_reset();
        rst_n = 1'b0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    // monitor error
    always @(posedge clk) begin
        if (error_detected) begin
            $error("[HW ERROR] ctrl=%b sa=%b @t=%0t", controller_error, sa_error, $time);
        end
    end

    initial begin
        $dumpfile("tb_inference.vcd");
        $dumpvars(0, tb_inference);
    
        $readmemh("tb/inference/inference_vectors/sv_fc2_a.hex", raw_a);
        $readmemh("tb/inference/inference_vectors/sv_fc2_b.hex", raw_b);
        $readmemh("tb/inference/inference_vectors/sv_fc2_gold.hex", raw_gold);

        for (int t= 0; t < N_TILES; t++) begin
            for (int r =0; r < N; r++) begin
                for (int c = 0; c < N; c++) begin
                    gold[t][r][c] = signed'(raw_gold[t*N*N + r*N + c]);
                end
            end
        end

        $display("INIT: %0d tiles, %0d feed rows each, %0d total BRAM roles", N_TILES, FEED_ROWS, TOTAL_FEED_ROWS);
        $display("INIT: checking %0d outputs per tile (%0d total)", N*N, N_TILES*N*N);

        reset_dut();

        for (int tile = 0; tile < N_TILES; tile++) begin
            logic timed_out;
            $display("TILE: %0d / %0d  (row-tile=%0d  col-tile=%0d)", tile, N_TILES-1, tile/N_COL_TILES, tile%N_COL_TILES);
 
            // Load A and B for this tile
            load_tile(tile, 1'b1);
            load_tile(tile, 1'b0);
 
            @(posedge clk); #1;
 
            run_wait(timed_out);
 
            if (!timed_out) begin
                if (error_detected) begin
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

        $display("\nINFERENCE TESTBENCH SUMMARY");
        $display("Tiles:      %0d", N_TILES);
        $display("Elements:   %0d", N_TILES*N*N);
        $display("Pass:       %0d", pass_count);
        $display("Fail:       %0d", fail_count);
        $display("%s", fail_count == 0 ? "ALL TILES PASSED" : "FAILURES DETECTED");
        $display("Latency: ~%0d cycles/tile; %0d tiles = ~%0d total cycles", 3*N + FEED_ROWS, N_TILES, (3*N + FEED_ROWS) * N_TILES);
        $display("Throughput: %.2f inferences/sec @ 100MHz (1 FC2 pass)", 100_000_000.0 / ((3*N + FEED_ROWS) * N_TILES));
        
        repeat(10) @(posedge clk);
        $finish;
    end

    initial begin
        #(TIMEOUT_CYCLES * 10ns + 1ms);
        $error("GLOBAL TIMEOUT: Tb did not complete in time");
        $finish;
    end

endmodule