module fir_top_baseline #(
    parameter DATA_WIDTH = 16,
    parameter COEFF_WIDTH = 21,
    parameter NUM_TAPS = 175,
    parameter OUTPUT_WIDTH = 32
)(
    input clk,
    input rst_n,
    input [DATA_WIDTH-1:0] data_in,
    input valid_in,
    output [OUTPUT_WIDTH-1:0] data_out,
    output valid_out
);

    fir_filter #(
        .NUM_TAPS(NUM_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PARALLEL_FACTOR(1),
        .ENABLE_PIPELINE(0),
        .COEFF_FILE("fir_coefficients_reference.hex")
    ) u_fir_filter (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .valid_in(valid_in),
        .data_out(data_out),
        .valid_out(valid_out)
    );

endmodule
