// tb_pe.sv - Testbench for pe.sv
timeunit 1ns; timeprecision 1ps;

module tb_pe;
    parameter DATA_WIDTH  = 8;
    parameter ACCUM_WIDTH = 32;

    localparam NUM_TESTS = 112; // Default: 12 corners + 100 random = 112
    localparam PIPELINE_DEPTH = 3;

    logic clk, rst_n;
    logic signed [DATA_WIDTH-1:0]  data_in,   data_out;
    logic signed [DATA_WIDTH-1:0]  weight_in, weight_out;
    logic signed [ACCUM_WIDTH-1:0] psum_in,   psum_out;

    pe #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) dut (
        .i_clk    (clk),
        .rst_n    (rst_n),
        .i_data   (data_in),
        .i_weight (weight_in),
        .i_psum   (psum_in),
        .o_data   (data_out),
        .o_weight (weight_out),
        .o_psum   (psum_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    int pass_count = 0;
    int fail_count = 0;

    task automatic reset_dut;
        rst_n   = 0;
        data_in = '0;  weight_in = '0;  psum_in = '0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;
        $display("[RESET] DUT reset complete");
    endtask

    task automatic test_mid_reset;
        $display("[TEST] Mid-simulation reset...");
        data_in = 8'd5;  weight_in = 8'd3;  psum_in = 32'd999;
        repeat(2) @(posedge clk);
        rst_n = 0; @(posedge clk); #1;

        if (data_out !== '0 || weight_out !== '0 || psum_out !== '0) begin
            $error("[FAIL] Mid-reset: outputs not cleared  data_out=%0h weight_out=%0h psum_out=%0h",
                   data_out, weight_out, psum_out);
            fail_count++;
        end else begin
            $display("[PASS] Mid-reset: outputs cleared");
            pass_count++;
        end

        if (dut.data_r !== '0 || dut.mult_r !== '0 || dut.mac_r !== '0) begin
            $error("[FAIL] Mid-reset: internal regs not cleared  data_r=%0h mult_r=%0h mac_r=%0h",
                   dut.data_r, dut.mult_r, dut.mac_r);
            fail_count++;
        end else begin
            $display("[PASS] Mid-reset: internal regs cleared");
            pass_count++;
        end
        rst_n = 1;
        @(posedge clk); #1;
    endtask

    logic [DATA_WIDTH-1:0]    raw_data   [0:NUM_TESTS-1];
    logic [DATA_WIDTH-1:0]    raw_weight [0:NUM_TESTS-1];
    logic [ACCUM_WIDTH-1:0]   raw_psum   [0:NUM_TESTS-1];
    logic [2*DATA_WIDTH-1:0]  raw_mult   [0:NUM_TESTS-1];  // 16-bit for 8b inputs
    logic [ACCUM_WIDTH-1:0]   raw_mac    [0:NUM_TESTS-1];

    logic signed [DATA_WIDTH-1:0]   tv_data   [0:NUM_TESTS-1];
    logic signed [DATA_WIDTH-1:0]   tv_weight [0:NUM_TESTS-1];
    logic signed [ACCUM_WIDTH-1:0]  tv_psum   [0:NUM_TESTS-1];
    logic signed [2*DATA_WIDTH-1:0] gold_mult [0:NUM_TESTS-1];
    logic signed [ACCUM_WIDTH-1:0]  gold_mac  [0:NUM_TESTS-1];

    initial begin
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);

        $readmemh("sim/pe/tv_data.hex",   raw_data);
        $readmemh("sim/pe/tv_weight.hex", raw_weight);
        $readmemh("sim/pe/tv_psum.hex",   raw_psum);
        $readmemh("sim/pe/gold_mult.hex", raw_mult);
        $readmemh("sim/pe/gold_mac.hex",  raw_mac);

        // Cast to signed for downstream comparisons
        for (int i = 0; i < NUM_TESTS; i++) begin
            tv_data[i]   = signed'(raw_data[i]);
            tv_weight[i] = signed'(raw_weight[i]);
            tv_psum[i]   = signed'(raw_psum[i]);
            gold_mult[i] = signed'(raw_mult[i]);
            gold_mac[i]  = signed'(raw_mac[i]);
        end
        $display("[INIT] Loaded %0d test vectors", NUM_TESTS);

        reset_dut();

        for (int i = 0; i < NUM_TESTS; i++) begin
            data_in   = tv_data[i];
            weight_in = tv_weight[i];
            psum_in   = tv_psum[i];

            repeat(PIPELINE_DEPTH) @(posedge clk); #1;

            // Multiply check
            if (dut.mult_r[2*DATA_WIDTH-1:0] !== gold_mult[i]) begin
                $error("[FAIL] vec[%0d] MULT: got=%0h  exp=%0h  (%0d * %0d)",
                       i, dut.mult_r[2*DATA_WIDTH-1:0], gold_mult[i],
                       tv_data[i], tv_weight[i]);
                fail_count++;
            end else begin
                pass_count++;
            end

            // MAC check
            if (dut.mac_r !== gold_mac[i]) begin
                $error("[FAIL] vec[%0d] MAC:  got=%0h  exp=%0h  (psum=%0d mult=%0d)",
                       i, dut.mac_r, gold_mac[i], tv_psum[i], gold_mult[i]);
                fail_count++;
            end else begin
                pass_count++;
            end
        end

        test_mid_reset();

        // Summary
        $display("Summary");
        $display("Pass count: %0d", pass_count);
        $display("Fail count: %0d", fail_count);
        $display("Total count: %0d", pass_count + fail_count);
        
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TEST(S) FAILED");

        repeat(5) @(posedge clk);
        $finish;
    end

endmodule