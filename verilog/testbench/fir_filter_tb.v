/*
 * FIR Filter Testbench (Architecture Equivalence)
 *
 * Compares baseline, serial-pipeline, L2, and L3 implementations
 * using the same tap count and coefficient file.
 */

`timescale 1ns / 1ps

module fir_filter_tb;

    localparam DATA_WIDTH = 16;
    localparam COEFF_WIDTH = 21;
    localparam NUM_TAPS = 175;
    localparam OUTPUT_WIDTH = 32;
    localparam CLK_PERIOD = 10;
    localparam OUT_WIDTH = OUTPUT_WIDTH;

    // Equivalence criteria (same math, allow small implementation differences)
    localparam EQ_THRESH = 0;
    localparam PIPELINE_LATENCY = 1;
    localparam WARMUP_SAMPLES = 50;

    reg clk, rst_n;
    reg [DATA_WIDTH-1:0] data_in;
    reg valid_in;

    wire [OUT_WIDTH-1:0] data_out_base;
    wire [OUT_WIDTH-1:0] data_out_pipe;
    wire [OUT_WIDTH-1:0] data_out_l2;
    wire [OUT_WIDTH-1:0] data_out_l3;
    wire valid_out_base;
    wire valid_out_pipe;
    wire valid_out_l2;
    wire valid_out_l3;

    reg signed [OUT_WIDTH-1:0] diff_pipe;
    reg signed [OUT_WIDTH-1:0] diff_l2;
    reg signed [OUT_WIDTH-1:0] diff_l3;
    reg signed [OUT_WIDTH-1:0] abs_diff_pipe;
    reg signed [OUT_WIDTH-1:0] abs_diff_l2;
    reg signed [OUT_WIDTH-1:0] abs_diff_l3;

    reg signed [OUT_WIDTH-1:0] base_delay_1;
    reg base_delay_1_valid;

    reg signed [OUT_WIDTH-1:0] max_abs_diff_pipe;
    reg signed [OUT_WIDTH-1:0] max_abs_diff_l2;
    reg signed [OUT_WIDTH-1:0] max_abs_diff_l3;

    integer sample_count;
    integer fail_pipe;
    integer fail_l2;
    integer fail_l3;
    integer log_fd;
    integer stim_i;

    // Baseline architecture
    fir_filter #(
        .NUM_TAPS(NUM_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PARALLEL_FACTOR(1),
        .ENABLE_PIPELINE(0),
        .COEFF_FILE("../results/fir_coefficients_reference.hex")
    ) dut_base (
        .clk(clk), .rst_n(rst_n), .data_in(data_in), .valid_in(valid_in),
        .data_out(data_out_base), .valid_out(valid_out_base)
    );

    // Serial pipelined architecture
    fir_filter #(
        .NUM_TAPS(NUM_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PARALLEL_FACTOR(1),
        .ENABLE_PIPELINE(1),
        .COEFF_FILE("../results/fir_coefficients_reference.hex")
    ) dut_pipe (
        .clk(clk), .rst_n(rst_n), .data_in(data_in), .valid_in(valid_in),
        .data_out(data_out_pipe), .valid_out(valid_out_pipe)
    );

    // L2 architecture
    fir_filter #(
        .NUM_TAPS(NUM_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PARALLEL_FACTOR(2),
        .ENABLE_PIPELINE(0),
        .COEFF_FILE("../results/fir_coefficients_reference.hex")
    ) dut_l2 (
        .clk(clk), .rst_n(rst_n), .data_in(data_in), .valid_in(valid_in),
        .data_out(data_out_l2), .valid_out(valid_out_l2)
    );

    // L3 architecture
    fir_filter #(
        .NUM_TAPS(NUM_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PARALLEL_FACTOR(3),
        .ENABLE_PIPELINE(0),
        .COEFF_FILE("../results/fir_coefficients_reference.hex")
    ) dut_l3 (
        .clk(clk), .rst_n(rst_n), .data_in(data_in), .valid_in(valid_in),
        .data_out(data_out_l3), .valid_out(valid_out_l3)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        valid_in = 1'b0;
        data_in = {DATA_WIDTH{1'b0}};
        sample_count = 0;
        fail_pipe = 0;
        fail_l2 = 0;
        fail_l3 = 0;
        max_abs_diff_pipe = 0;
        max_abs_diff_l2 = 0;
        max_abs_diff_l3 = 0;
        base_delay_1 = 0;
        base_delay_1_valid = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // Impulse
        valid_in = 1'b1;
        data_in = 16'sd1;
        @(posedge clk);

        // Step section
        data_in = 16'sd4096;
        repeat (200) @(posedge clk);

        // Deterministic pseudo-random-like section (ramp), easy to reproduce in MATLAB.
        for (stim_i = 0; stim_i < 1000; stim_i = stim_i + 1) begin
            data_in = stim_i - 500;
            @(posedge clk);
        end

        valid_in = 1'b0;
        data_in = 0;
        repeat (100) @(posedge clk);

        $display("\n=== Architecture Equivalence Summary ===");
        $display("Samples compared        : %0d", sample_count);
        $display("Warmup samples ignored  : %0d", WARMUP_SAMPLES);
        $display("Threshold               : %0d", EQ_THRESH);
        $display("Pipeline latency align  : %0d", PIPELINE_LATENCY);
        $display("Max |diff| pipeline     : %0d", max_abs_diff_pipe);
        $display("Max |diff| L2           : %0d", max_abs_diff_l2);
        $display("Max |diff| L3           : %0d", max_abs_diff_l3);
        $display("Violations pipeline     : %0d", fail_pipe);
        $display("Violations L2           : %0d", fail_l2);
        $display("Violations L3           : %0d", fail_l3);
        if ((fail_pipe == 0) && (fail_l2 == 0) && (fail_l3 == 0)) begin
            $display("RESULT: PASS");
        end else begin
            $display("RESULT: FAIL");
        end

        if (log_fd != 0) begin
            $fclose(log_fd);
        end
        $finish;
    end

    initial begin
        $dumpfile("fir_filter_sim.vcd");
        $dumpvars(0, fir_filter_tb);

        log_fd = $fopen("fir_compare_log.csv", "w");
        if (log_fd != 0) begin
            $fwrite(log_fd, "time_ns,input,base,pipeline,l2,l3,diff_pipe,diff_l2,diff_l3\n");
        end
    end

    always @(posedge clk) begin
        // Baseline delay line for pipeline comparison
        base_delay_1 <= $signed(data_out_base);
        base_delay_1_valid <= valid_out_base;

        if (valid_out_pipe && base_delay_1_valid) begin
            diff_pipe = $signed(data_out_pipe) - $signed(base_delay_1);
            if ($signed(diff_pipe) < 0) abs_diff_pipe = -$signed(diff_pipe);
            else abs_diff_pipe = $signed(diff_pipe);

            if (abs_diff_pipe > max_abs_diff_pipe) max_abs_diff_pipe = abs_diff_pipe;
            if ((sample_count > WARMUP_SAMPLES) && (abs_diff_pipe > EQ_THRESH)) fail_pipe = fail_pipe + 1;
        end else begin
            diff_pipe = 0;
        end

        if (valid_out_base && valid_out_l2 && valid_out_l3) begin
            sample_count = sample_count + 1;

            diff_l2 = $signed(data_out_l2) - $signed(data_out_base);
            diff_l3 = $signed(data_out_l3) - $signed(data_out_base);

            if ($signed(diff_l2) < 0) abs_diff_l2 = -$signed(diff_l2);
            else abs_diff_l2 = $signed(diff_l2);

            if ($signed(diff_l3) < 0) abs_diff_l3 = -$signed(diff_l3);
            else abs_diff_l3 = $signed(diff_l3);

            if (abs_diff_l2 > max_abs_diff_l2) max_abs_diff_l2 = abs_diff_l2;
            if (abs_diff_l3 > max_abs_diff_l3) max_abs_diff_l3 = abs_diff_l3;

            if ((sample_count > WARMUP_SAMPLES) && (abs_diff_l2 > EQ_THRESH)) fail_l2 = fail_l2 + 1;
            if ((sample_count > WARMUP_SAMPLES) && (abs_diff_l3 > EQ_THRESH)) fail_l3 = fail_l3 + 1;

            if (log_fd != 0) begin
                $fwrite(log_fd, "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    $time,
                    $signed(data_in),
                    $signed(data_out_base),
                    $signed(data_out_pipe),
                    $signed(data_out_l2),
                    $signed(data_out_l3),
                    $signed(diff_pipe),
                    $signed(diff_l2),
                    $signed(diff_l3));
            end
        end
    end

endmodule
