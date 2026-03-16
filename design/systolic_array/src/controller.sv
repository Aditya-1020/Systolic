module controller #(
    parameter int FEED_LEN  = 7,
    parameter int CNT_W     = 3,
    parameter int ADDR_WIDTH = 3
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_start,
    input logic i_done,

    output logic o_clear,
    output logic [ADDR_WIDTH-1:0] o_addr_a,
    output logic [ADDR_WIDTH-1:0] o_addr_b,
    output logic o_valid,
    output logic o_swap,
    output logic o_error
);
    typedef enum logic [3:0] {
        IDLE  = 4'b0001,
        CLEAR = 4'b0010,
        FEED  = 4'b0100,
        WAIT  = 4'b1000
    } state_t;

    state_t state, next_state;
    logic [CNT_W-1:0] feed_cnt, next_feed_cnt;

    logic next_clear, next_valid, next_swap, next_error;
    logic [ADDR_WIDTH-1:0] next_addr_a, next_addr_b;

    always_comb begin
        next_state    = state;
        next_feed_cnt = feed_cnt;
        next_clear    = 1'b0;
        next_addr_a   = '0;
        next_addr_b   = '0;
        next_valid    = 1'b0;
        next_swap     = 1'b0;
        next_error    = o_error;

        case (state)
            IDLE: begin
                if (i_start && !o_error) begin
                    next_state = CLEAR;
                end
            end

            CLEAR: begin
                next_clear    = 1'b1;
                next_feed_cnt = '0;
                next_addr_a   = '0;
                next_addr_b   = '0;
                next_state    = FEED;
            end

            FEED: begin
                next_valid   = 1'b1;
                next_addr_a  = feed_cnt;
                next_addr_b  = feed_cnt;

                if (feed_cnt == CNT_W'(FEED_LEN - 1)) begin
                    next_feed_cnt = feed_cnt;
                    next_state    = WAIT;
                end else begin
                    next_feed_cnt = feed_cnt + 1'b1;
                end
            end

            WAIT: begin
                if (i_done) begin
                    next_swap  = 1'b1;
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state     <= IDLE;
            feed_cnt  <= '0;
            o_clear   <= 1'b0;
            o_addr_a  <= '0;
            o_addr_b  <= '0;
            o_valid   <= 1'b0;
            o_swap    <= 1'b0;
            o_error   <= 1'b0;
        end else begin
            state     <= next_state;
            feed_cnt  <= next_feed_cnt;
            o_clear   <= next_clear;
            o_addr_a  <= next_addr_a;
            o_addr_b  <= next_addr_b;
            o_valid   <= next_valid;
            o_swap    <= next_swap;
            o_error   <= next_error;
        end
    end

endmodule