// buffer.sv — ping-pong register file

module buffer #(
    parameter int DEPTH      = 7,
    parameter int ADDR_WIDTH = 3,
    parameter int ROW_WIDTH  = 32
)(
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_wr_en,
    input  logic [ADDR_WIDTH-1:0] i_wr_addr,
    input  logic [ROW_WIDTH-1:0]  i_wr_data,
    input  logic i_swap,
    input  logic [ADDR_WIDTH-1:0] i_rd_addr,
    output logic [ROW_WIDTH-1:0] o_rd_data
);
    logic [ROW_WIDTH-1:0] bank [0:1][0:DEPTH-1];
    logic bank_sel;

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            bank_sel <= 1'b0;
        end
        else if (i_swap) begin
            bank_sel <= ~bank_sel;
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_wr_en) begin
            bank[bank_sel][i_wr_addr] <= i_wr_data;            
        end
    end

    assign o_rd_data = bank[bank_sel][i_rd_addr];

endmodule
