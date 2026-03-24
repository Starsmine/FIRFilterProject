/*
 * FIR Filter Implementation - Verilog
 * 
 * Description:
 *   Configurable FIR filter with support for:
 *   - Standard implementation
 *   - Pipelined architecture
 *   - Parallel processing (L=2, L=3)
 *   - Pipelined + Parallel combination
 *
 * Parameters:
 *   NUM_TAPS     : Number of filter taps (default: 100)
 *   DATA_WIDTH   : Input/Output data width in bits (default: 16)
 *   COEFF_WIDTH  : Filter coefficient width in bits (default: 16)
 *   PARALLEL_FACTOR : Parallelism factor L (1=serial, 2=2-parallel, 3=3-parallel)
 *   ENABLE_PIPELINE : Enable pipelining (1=yes, 0=no)
 */

module fir_filter #(
    parameter NUM_TAPS = 175,
    parameter DATA_WIDTH = 16,
    parameter COEFF_WIDTH = 21,
    parameter OUTPUT_WIDTH = 32,
    parameter PARALLEL_FACTOR = 1,
    parameter ENABLE_PIPELINE = 0,
    parameter PIPELINE_STAGES = 1,
    parameter COEFF_FILE = "fir_coefficients_reference.hex"
)(
    input  clk,
    input  rst_n,
    input  [DATA_WIDTH-1:0] data_in,
    input  valid_in,
    output [OUTPUT_WIDTH-1:0] data_out,
    output valid_out
);

    // Internal parameters
    localparam ACC_WIDTH = DATA_WIDTH + COEFF_WIDTH + $clog2(NUM_TAPS);
    
    // Filter coefficients (to be initialized from external file or parameter)
    reg signed [COEFF_WIDTH-1:0] coeff [0:NUM_TAPS-1];
    
    // Register file for stored input samples
    reg signed [DATA_WIDTH-1:0] shift_reg [0:NUM_TAPS-1];
    
    // Accumulator and pipeline registers
    reg signed [ACC_WIDTH-1:0] accumulator;
    reg valid_out_reg;
    reg signed [ACC_WIDTH-1:0] mac_sum;
    reg signed [ACC_WIDTH-1:0] mac_sum_l2_even;
    reg signed [ACC_WIDTH-1:0] mac_sum_l2_odd;
    reg signed [ACC_WIDTH-1:0] mac_sum_l3_0;
    reg signed [ACC_WIDTH-1:0] mac_sum_l3_1;
    reg signed [ACC_WIDTH-1:0] mac_sum_l3_2;
    reg signed [ACC_WIDTH-1:0] mac_sum_l3_pipe;
    reg signed [ACC_WIDTH-1:0] mac_sum_l3_pipe01;
    reg signed [ACC_WIDTH-1:0] mac_sum_l3_pipe2;
    reg signed [ACC_WIDTH-1:0] mac_sum_pipe_a;
    reg signed [ACC_WIDTH-1:0] mac_sum_pipe_b;
    reg signed [ACC_WIDTH-1:0] mac_sum_pipe_c;
    reg signed [ACC_WIDTH-1:0] mac_sum_pipe_d;
    reg signed [ACC_WIDTH-1:0] mac_sum_pipe_ab;
    reg signed [ACC_WIDTH-1:0] mac_sum_pipe_cd;
    reg signed [ACC_WIDTH-1:0] mac_tmp0;
    reg signed [ACC_WIDTH-1:0] mac_tmp1;
    reg signed [ACC_WIDTH-1:0] mac_tmp2;
    reg signed [ACC_WIDTH-1:0] mac_tmp3;
    reg valid_pipe;
    reg valid_pipe0;
    reg valid_pipe1;
    integer i;

    // Final-stage saturating resize. Internal accumulation stays full width.
    function [OUTPUT_WIDTH-1:0] sat_resize;
        input signed [ACC_WIDTH-1:0] value;
        reg signed [ACC_WIDTH-1:0] max_out;
        reg signed [ACC_WIDTH-1:0] min_out;
        reg pos_overflow;
        reg neg_overflow;
        begin
            if (OUTPUT_WIDTH >= ACC_WIDTH) begin
                sat_resize = value[OUTPUT_WIDTH-1:0];
            end else begin
                max_out = {{(ACC_WIDTH-OUTPUT_WIDTH+1){1'b0}}, {(OUTPUT_WIDTH-1){1'b1}}};
                min_out = {{(ACC_WIDTH-OUTPUT_WIDTH+1){1'b1}}, {1'b1, {(OUTPUT_WIDTH-1){1'b0}}}};
                pos_overflow = (value > max_out);
                neg_overflow = (value < min_out);

                if (pos_overflow)
                    sat_resize = {1'b0, {(OUTPUT_WIDTH-1){1'b1}}};
                else if (neg_overflow)
                    sat_resize = {1'b1, {(OUTPUT_WIDTH-1){1'b0}}};
                else
                    sat_resize = value[OUTPUT_WIDTH-1:0];
            end
        end
    endfunction

    // Load coefficients from a HEX file. One signed coefficient per line.
    initial begin
        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            coeff[i] = {COEFF_WIDTH{1'b0}};
        end
        $readmemh(COEFF_FILE, coeff);
    end

    //==========================================================================
    // BASELINE IMPLEMENTATION: Serial processing (PARALLEL_FACTOR = 1)
    //==========================================================================
    generate
        if (PARALLEL_FACTOR == 1 && ENABLE_PIPELINE == 0) begin : SERIAL_NO_PIPELINE
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    accumulator <= {ACC_WIDTH{1'b0}};
                    valid_out_reg <= 1'b0;
                    mac_sum <= {ACC_WIDTH{1'b0}};
                    for (i = 0; i < NUM_TAPS; i = i + 1) begin
                        shift_reg[i] <= {DATA_WIDTH{1'b0}};
                    end
                end else if (valid_in) begin
                    // Shift data through the register file
                    for (i = NUM_TAPS-1; i > 0; i = i - 1) begin
                        shift_reg[i] <= shift_reg[i-1];
                    end
                    shift_reg[0] <= data_in;
                    
                    // Compute FIR filter output (convolution)
                    mac_sum = {ACC_WIDTH{1'b0}};
                    for (i = 0; i < NUM_TAPS; i = i + 1) begin
                        mac_sum = mac_sum + (shift_reg[i] * coeff[i]);
                    end
                    accumulator <= mac_sum;
                    valid_out_reg <= 1'b1;
                end else begin
                    valid_out_reg <= 1'b0;
                end
            end
        end
    endgenerate

    //==========================================================================
    // PIPELINED IMPLEMENTATION (PARALLEL_FACTOR = 1, ENABLE_PIPELINE = 1)
    //==========================================================================
    generate
        if (PARALLEL_FACTOR == 1 && ENABLE_PIPELINE == 1) begin : SERIAL_PIPELINE
            // Configurable serial pipeline:
            // - PIPELINE_STAGES <= 1: true 2-stage reduction (2 halves -> final)
            // - PIPELINE_STAGES > 1 : true 3-stage reduction (4 quarters -> 2 pairs -> final)
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    accumulator <= {ACC_WIDTH{1'b0}};
                    valid_out_reg <= 1'b0;
                    mac_sum <= {ACC_WIDTH{1'b0}};
                    mac_sum_pipe_a <= {ACC_WIDTH{1'b0}};
                    mac_sum_pipe_b <= {ACC_WIDTH{1'b0}};
                    mac_sum_pipe_c <= {ACC_WIDTH{1'b0}};
                    mac_sum_pipe_d <= {ACC_WIDTH{1'b0}};
                    mac_sum_pipe_ab <= {ACC_WIDTH{1'b0}};
                    mac_sum_pipe_cd <= {ACC_WIDTH{1'b0}};
                    valid_pipe <= 1'b0;
                    valid_pipe0 <= 1'b0;
                    valid_pipe1 <= 1'b0;
                    for (i = 0; i < NUM_TAPS; i = i + 1) begin
                        shift_reg[i] <= {DATA_WIDTH{1'b0}};
                    end
                end else begin
                    // Shift operation for incoming sample stream
                    if (valid_in) begin
                        for (i = NUM_TAPS-1; i > 0; i = i - 1) begin
                            shift_reg[i] <= shift_reg[i-1];
                        end
                        shift_reg[0] <= data_in;
                    end

                    if (PIPELINE_STAGES <= 1) begin
                        // Stage 0: register two half sums.
                        // Stage 1: combine half sums to final accumulator.
                        valid_out_reg <= valid_pipe;
                        valid_pipe <= valid_in;

                        if (valid_in) begin
                            mac_tmp0 = {ACC_WIDTH{1'b0}};
                            mac_tmp1 = {ACC_WIDTH{1'b0}};
                            for (i = 0; i < (NUM_TAPS/2); i = i + 1) begin
                                mac_tmp0 = mac_tmp0 + (shift_reg[i] * coeff[i]);
                            end
                            for (i = (NUM_TAPS/2); i < NUM_TAPS; i = i + 1) begin
                                mac_tmp1 = mac_tmp1 + (shift_reg[i] * coeff[i]);
                            end
                            mac_sum_pipe_a <= mac_tmp0;
                            mac_sum_pipe_b <= mac_tmp1;
                        end

                        if (valid_pipe) begin
                            accumulator <= mac_sum_pipe_a + mac_sum_pipe_b;
                        end
                    end else begin
                        // Stage 0: register four quarter sums.
                        // Stage 1: register pairwise reductions.
                        // Stage 2: final reduction into accumulator.
                        valid_out_reg <= valid_pipe1;
                        valid_pipe1 <= valid_pipe0;
                        valid_pipe0 <= valid_in;

                        if (valid_in) begin
                            mac_tmp0 = {ACC_WIDTH{1'b0}};
                            mac_tmp1 = {ACC_WIDTH{1'b0}};
                            mac_tmp2 = {ACC_WIDTH{1'b0}};
                            mac_tmp3 = {ACC_WIDTH{1'b0}};
                            for (i = 0; i < (NUM_TAPS/4); i = i + 1) begin
                                mac_tmp0 = mac_tmp0 + (shift_reg[i] * coeff[i]);
                            end
                            for (i = (NUM_TAPS/4); i < (NUM_TAPS/2); i = i + 1) begin
                                mac_tmp1 = mac_tmp1 + (shift_reg[i] * coeff[i]);
                            end
                            for (i = (NUM_TAPS/2); i < (3*NUM_TAPS/4); i = i + 1) begin
                                mac_tmp2 = mac_tmp2 + (shift_reg[i] * coeff[i]);
                            end
                            for (i = (3*NUM_TAPS/4); i < NUM_TAPS; i = i + 1) begin
                                mac_tmp3 = mac_tmp3 + (shift_reg[i] * coeff[i]);
                            end
                            mac_sum_pipe_a <= mac_tmp0;
                            mac_sum_pipe_b <= mac_tmp1;
                            mac_sum_pipe_c <= mac_tmp2;
                            mac_sum_pipe_d <= mac_tmp3;
                        end

                        if (valid_pipe0) begin
                            mac_sum_pipe_ab <= mac_sum_pipe_a + mac_sum_pipe_b;
                            mac_sum_pipe_cd <= mac_sum_pipe_c + mac_sum_pipe_d;
                        end

                        if (valid_pipe1) begin
                            accumulator <= mac_sum_pipe_ab + mac_sum_pipe_cd;
                        end
                    end
                end
            end
        end
    endgenerate

    //==========================================================================
    // PARALLEL PROCESSING IMPLEMENTATION
    //==========================================================================
    generate
        if (PARALLEL_FACTOR == 2) begin : PARALLEL_L2
            // L=2 datapath: split MAC into even/odd tap lanes and combine.
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    accumulator <= {ACC_WIDTH{1'b0}};
                    valid_out_reg <= 1'b0;
                    mac_sum <= {ACC_WIDTH{1'b0}};
                    mac_sum_l2_even <= {ACC_WIDTH{1'b0}};
                    mac_sum_l2_odd <= {ACC_WIDTH{1'b0}};
                    for (i = 0; i < NUM_TAPS; i = i + 1) begin
                        shift_reg[i] <= {DATA_WIDTH{1'b0}};
                    end
                end else if (valid_in) begin
                    for (i = NUM_TAPS-1; i > 0; i = i - 1) begin
                        shift_reg[i] <= shift_reg[i-1];
                    end
                    shift_reg[0] <= data_in;

                    mac_sum_l2_even = {ACC_WIDTH{1'b0}};
                    mac_sum_l2_odd = {ACC_WIDTH{1'b0}};
                    for (i = 0; i < NUM_TAPS; i = i + 2) begin
                        mac_sum_l2_even = mac_sum_l2_even + (shift_reg[i] * coeff[i]);
                    end
                    for (i = 1; i < NUM_TAPS; i = i + 2) begin
                        mac_sum_l2_odd = mac_sum_l2_odd + (shift_reg[i] * coeff[i]);
                    end

                    mac_sum = mac_sum_l2_even + mac_sum_l2_odd;
                    accumulator <= mac_sum;
                    valid_out_reg <= 1'b1;
                end else begin
                    valid_out_reg <= 1'b0;
                end
            end
        end

        if (PARALLEL_FACTOR == 3) begin : PARALLEL_L3
            // L=3 datapath: split MAC into 3 modulo-3 lanes and combine.
            // - PIPELINE_STAGES <= 1: true 2-stage reduction (3 lanes -> final)
            // - PIPELINE_STAGES > 1 : true 3-stage reduction ((l0+l1), l2 -> final)
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    accumulator <= {ACC_WIDTH{1'b0}};
                    valid_out_reg <= 1'b0;
                    mac_sum <= {ACC_WIDTH{1'b0}};
                    mac_sum_l3_0 <= {ACC_WIDTH{1'b0}};
                    mac_sum_l3_1 <= {ACC_WIDTH{1'b0}};
                    mac_sum_l3_2 <= {ACC_WIDTH{1'b0}};
                    mac_sum_l3_pipe <= {ACC_WIDTH{1'b0}};
                    mac_sum_l3_pipe01 <= {ACC_WIDTH{1'b0}};
                    mac_sum_l3_pipe2 <= {ACC_WIDTH{1'b0}};
                    valid_pipe <= 1'b0;
                    valid_pipe0 <= 1'b0;
                    valid_pipe1 <= 1'b0;
                    for (i = 0; i < NUM_TAPS; i = i + 1) begin
                        shift_reg[i] <= {DATA_WIDTH{1'b0}};
                    end
                end else begin
                    if (valid_in) begin
                        for (i = NUM_TAPS-1; i > 0; i = i - 1) begin
                            shift_reg[i] <= shift_reg[i-1];
                        end
                        shift_reg[0] <= data_in;
                    end

                    if (ENABLE_PIPELINE == 1) begin
                        if (PIPELINE_STAGES <= 1) begin
                            // Stage 0: register lane sums.
                            // Stage 1: combine registered lane sums.
                            valid_out_reg <= valid_pipe;
                            valid_pipe <= valid_in;

                            if (valid_in) begin
                                mac_tmp0 = {ACC_WIDTH{1'b0}};
                                mac_tmp1 = {ACC_WIDTH{1'b0}};
                                mac_tmp2 = {ACC_WIDTH{1'b0}};

                                for (i = 0; i < NUM_TAPS; i = i + 3) begin
                                    mac_tmp0 = mac_tmp0 + (shift_reg[i] * coeff[i]);
                                end
                                for (i = 1; i < NUM_TAPS; i = i + 3) begin
                                    mac_tmp1 = mac_tmp1 + (shift_reg[i] * coeff[i]);
                                end
                                for (i = 2; i < NUM_TAPS; i = i + 3) begin
                                    mac_tmp2 = mac_tmp2 + (shift_reg[i] * coeff[i]);
                                end

                                mac_sum_l3_0 <= mac_tmp0;
                                mac_sum_l3_1 <= mac_tmp1;
                                mac_sum_l3_2 <= mac_tmp2;
                            end

                            if (valid_pipe) begin
                                accumulator <= mac_sum_l3_0 + mac_sum_l3_1 + mac_sum_l3_2;
                            end
                        end else begin
                            // Stage 0: register lane sums.
                            // Stage 1: register (l0+l1) and l2 passthrough.
                            // Stage 2: final reduction into accumulator.
                            valid_out_reg <= valid_pipe1;
                            valid_pipe1 <= valid_pipe0;
                            valid_pipe0 <= valid_in;

                            if (valid_in) begin
                                mac_tmp0 = {ACC_WIDTH{1'b0}};
                                mac_tmp1 = {ACC_WIDTH{1'b0}};
                                mac_tmp2 = {ACC_WIDTH{1'b0}};

                                for (i = 0; i < NUM_TAPS; i = i + 3) begin
                                    mac_tmp0 = mac_tmp0 + (shift_reg[i] * coeff[i]);
                                end
                                for (i = 1; i < NUM_TAPS; i = i + 3) begin
                                    mac_tmp1 = mac_tmp1 + (shift_reg[i] * coeff[i]);
                                end
                                for (i = 2; i < NUM_TAPS; i = i + 3) begin
                                    mac_tmp2 = mac_tmp2 + (shift_reg[i] * coeff[i]);
                                end

                                mac_sum_l3_0 <= mac_tmp0;
                                mac_sum_l3_1 <= mac_tmp1;
                                mac_sum_l3_2 <= mac_tmp2;
                            end

                            if (valid_pipe0) begin
                                mac_sum_l3_pipe01 <= mac_sum_l3_0 + mac_sum_l3_1;
                                mac_sum_l3_pipe2 <= mac_sum_l3_2;
                            end
                            if (valid_pipe1) begin
                                accumulator <= mac_sum_l3_pipe01 + mac_sum_l3_pipe2;
                            end
                        end
                    end else begin
                        if (valid_in) begin
                            mac_tmp0 = {ACC_WIDTH{1'b0}};
                            mac_tmp1 = {ACC_WIDTH{1'b0}};
                            mac_tmp2 = {ACC_WIDTH{1'b0}};

                            for (i = 0; i < NUM_TAPS; i = i + 3) begin
                                mac_tmp0 = mac_tmp0 + (shift_reg[i] * coeff[i]);
                            end
                            for (i = 1; i < NUM_TAPS; i = i + 3) begin
                                mac_tmp1 = mac_tmp1 + (shift_reg[i] * coeff[i]);
                            end
                            for (i = 2; i < NUM_TAPS; i = i + 3) begin
                                mac_tmp2 = mac_tmp2 + (shift_reg[i] * coeff[i]);
                            end

                            accumulator <= mac_tmp0 + mac_tmp1 + mac_tmp2;
                            valid_out_reg <= 1'b1;
                        end else begin
                            valid_out_reg <= 1'b0;
                        end
                        valid_pipe <= 1'b0;
                        valid_pipe0 <= 1'b0;
                        valid_pipe1 <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    // Output assignment
    assign data_out = sat_resize(accumulator);
    assign valid_out = valid_out_reg;

endmodule
