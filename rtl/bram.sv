// BRAM to store matices
// dual port: host write, contorller read
timeunit 1ns; timeprecision 1ps;

module bram #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 4096, // N_MAX^2 = 64^2
    parameter int unsigned ADDR_WIDTH = $clog2(DEPTH)
)(
    // host write
    input logic i_a_clk,
    input logic i_a_wr_en,
    input logic [ADDR_WIDTH-1:0] i_a_addr,
    input logic [DATA_WIDTH-1:0] i_a_din,

    // controller read
    input logic i_b_clk,
    input logic i_b_en,
    input logic [ADDR_WIDTH-1:0] i_b_addr,
    output logic [DATA_WIDTH-1:0] o_b_dout
);

    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Port A
    always_ff @(posedge i_a_clk) begin : bram_port_a_write
        if (i_a_wr_en) begin
            mem[i_a_addr] <= i_a_din;
        end
    end

    // Port B
    always_ff @(posedge i_b_clk) begin : bram_port_b_write
        if (i_b_en) begin
            o_b_dout <= mem[i_b_addr];
        end
    end
endmodule