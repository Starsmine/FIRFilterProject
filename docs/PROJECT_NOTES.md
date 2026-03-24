# FIR Filter Project - Working Notes

## Design Decisions

### Filter Specifications
- **Number of Taps:** 100 (may increase if needed for 80dB stopband attenuation)
- **Transition Band:** 0.2π to 0.23π rad/sample (normalized frequency)
- **Stopband Attenuation:** ≥ 80 dB
- **Design Method:** Parks-McClellan (equiripple) or Window-based method

### Quantization Strategy
- **Coefficient Bits:** 16 bits (signed fixed-point)
- **Input Data Bits:** 16 bits (signed fixed-point)
- **Output Bits:** 32 bits (to handle accumulation)
- **Overflow Handling:** [To be documented]

### Hardware Architecture Considerations

#### 1. Baseline Serial Implementation
- Single multiply-accumulate per clock cycle
- Minimal area, lowest throughput
- Latency: NUM_TAPS cycles

#### 2. Pipelined Implementation
- Multi-stage pipeline for MAC operations
- Benefits: Higher clock frequency, reduced critical path
- Trade-off: Increased area and latency

#### 3. Parallel Processing (L=2)
- Two samples processed per clock cycle
- Requires 2 parallel computation paths
- Latency: NUM_TAPS/2 cycles

#### 4. Parallel Processing (L=3)
- Three samples processed per clock cycle
- Requires 3 parallel computation paths
- Latency: NUM_TAPS/3 cycles

#### 5. Combined Pipelining + L=3 Parallel
- Combines pipelining with 3-way parallelism
- Highest throughput but largest area

## MATLAB Design Progress
- [ ] Load baseline filter design parameters
- [ ] Design 100-tap FIR filter
- [ ] Verify passband ripple and stopband attenuation
- [ ] Analyze frequency response
- [ ] Quantize filter coefficients
- [ ] Compare original vs quantized response
- [ ] Document quantization effects
- [ ] Export coefficients for Verilog

## Verilog Implementation Progress
- [ ] Implement baseline serial FIR filter
- [ ] Implement pipelined version
- [ ] Implement L=2 parallel processing
- [ ] Implement L=3 parallel processing
- [ ] Implement pipelined + L=3 combined
- [ ] Create comprehensive testbench
- [ ] Simulate and verify correctness

## Synthesis & Analysis Progress
- [ ] Synthesize with Xilinx/Synopsys
- [ ] Extract area metrics (LUTs, FFs, DSPs)
- [ ] Analyze clock frequency and timing
- [ ] Estimate power consumption
- [ ] Compare architectures

## Key References
- MATLAB FIR Filter Design: https://www.mathworks.com/help/signal/ug/fir-filter-design.html
- Digital Signal Processing fundamentals
- FPGA Design best practices

## Important Dates
- **Due Date:** March 24th, 2026
- **Grading Breakdown:**
  - 20%: MATLAB design + Verilog structure description
  - 20%: Filter frequency response analysis
  - 20%: Architecture documentation
  - 20%: Hardware implementation results
  - 20%: Analysis and conclusion
