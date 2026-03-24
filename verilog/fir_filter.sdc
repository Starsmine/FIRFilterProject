# FIR project timing constraints
# Primary clock for all FIR top wrappers
create_clock -name clk -period 10.000 [get_ports {clk}]

# Improve analysis realism and silence unconstrained-transfer warnings.
derive_clock_uncertainty

# Use zero-board-delay assumptions for architecture-level comparisons.
set_input_delay -clock clk 0.000 [get_ports {data_in[*]}]
set_input_delay -clock clk 0.000 [get_ports {valid_in}]
set_output_delay -clock clk 0.000 [get_ports {data_out[*]}]
set_output_delay -clock clk 0.000 [get_ports {valid_out}]

# Exclude asynchronous reset from timing closure
set_false_path -from [get_ports {rst_n}]
