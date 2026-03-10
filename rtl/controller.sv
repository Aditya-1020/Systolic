timeunit 1ns; timeprecision 1ps;

module controller #(
    parameter int N = 8,
    parameter int ADDR_WIDTH = 12
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_start,
    input logic i_done, // from systolic array
    output logic o_clear,
    output logic o_bram_en,
    output logic [ADDR_WIDTH-1:0] o_addr_a,
    output logic [ADDR_WIDTH-1:0] o_addr_b,
    output logic o_valid,
    output logic o_error
);
    initial begin
        assert (N >= 2 && N <= (1 << 16)) else $fatal(1, "N oout of range");
        assert (ADDR_WIDTH >= $clog2(N))   else $fatal(1, "ADDR_WIDTH too small");
    end

    localparam int unsigned FEED_LEN = 2*N -1;
    localparam int unsigned FEED_CNT_WIDTH = $clog2(FEED_LEN + 1);

    typedef enum logic [3:0] {
        IDLE  = 4'b0001,
        CLEAR = 4'b0010,
        FEED  = 4'b0100,
        WAIT  = 4'b1000
    } controller_state_t;

    controller_state_t state, next_state;
    logic [FEED_CNT_WIDTH-1:0] feed_cnt, next_feed_cnt;

    logic next_clear, next_bram_en, next_valid, next_error;
    logic [ADDR_WIDTH-1:0] next_addr_a, next_addr_b;

    always_comb begin
        next_state = state;
        next_feed_cnt = feed_cnt;
        next_clear = 1'b0;
        next_bram_en = 1'b0;
        next_addr_a = '0;
        next_addr_b = '0;
        next_valid = 1'b0;
        next_error = o_error;
        
        unique case (state)
            IDLE: begin
                if (i_start && !o_error) begin
                    next_clear = 1'b1;
                    next_state = CLEAR;
                end else if (i_start && o_error) begin
                    next_error = 1'b1;
                end
            end

            CLEAR: begin
                next_feed_cnt = '0;
                next_bram_en = 1'b1;
                next_addr_a = '0;
                next_addr_b = '0;
                next_state = FEED;
            end

            FEED: begin
                next_valid = 1'b1;
                if (int'(feed_cnt) == FEED_LEN-1) begin
                    next_bram_en = 1'b0;
                    next_feed_cnt = feed_cnt;
                    next_state = WAIT;
                end else begin
                    next_bram_en = 1'b1;
                    next_feed_cnt = feed_cnt + 1'b1;
                    next_addr_a = ADDR_WIDTH'(feed_cnt + 1'b1);
                    next_addr_b = ADDR_WIDTH'(feed_cnt + 1'b1);
                end
            end

            WAIT: begin
                if (i_done) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= IDLE;
            feed_cnt <= '0;
            o_clear <= 1'b0;
            o_bram_en <= 1'b0;
            o_addr_a <= '0;
            o_addr_b <= '0;
            o_valid <= 1'b0;
            o_error <= 1'b0;
        end else begin
            state <= next_state;
            feed_cnt <= next_feed_cnt;
            o_clear <= next_clear;
            o_bram_en <= next_bram_en;
            o_addr_a <= next_addr_a;
            o_addr_b <= next_addr_b;
            o_valid <= next_valid;
            o_error <= next_error;
        end
    end

endmodule