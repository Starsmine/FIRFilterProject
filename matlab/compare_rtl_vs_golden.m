%% Compare RTL baseline output against MATLAB golden model
% Assumes testbench stimulus in fir_filter_tb.v:
% 1) impulse sample of +1
% 2) 200 samples of +4096
% 3) 1000-sample ramp: n-500, n=0..999

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
results_dir = fullfile(project_root, 'results');
verilog_dir = fullfile(project_root, 'verilog');

mat_file = fullfile(results_dir, 'fir_coefficients.mat');
rtl_log_file = fullfile(verilog_dir, 'fir_compare_log.csv');
golden_csv_file = fullfile(results_dir, 'matlab_golden_baseline.csv');

if ~exist(mat_file, 'file')
    error('Missing %s. Run fir_filter_design.m first.', mat_file);
end
if ~exist(rtl_log_file, 'file')
    error('Missing %s. Run testbench simulation first.', rtl_log_file);
end

S = load(mat_file);
if ~isfield(S, 'h_ref_q') || ~isfield(S, 'coeff_bits')
    error('fir_coefficients.mat missing h_ref_q/coeff_bits. Re-run fir_filter_design.m');
end

coeff_bits = S.coeff_bits;
h_ref_q = S.h_ref_q(:).';
output_bits = 32;

% Rebuild integer coefficient vector exactly like RTL file export.
coeff_int = round(h_ref_q * (2^(coeff_bits-1)-1) / max(abs(h_ref_q)));

% Build deterministic stimulus matching fir_filter_tb.v.
stim = [1, repmat(4096, 1, 200), ((0:999) - 500)];

% RTL computes MAC using shift_reg old values (NB shift + immediate sum),
% equivalent to a one-sample delayed input stream.
stim_delayed = [0, stim(1:end-1)];

y_golden = filter(coeff_int, 1, double(stim_delayed));

% Match RTL final-stage output saturation to 32-bit signed output.
max_out = double(2^(output_bits-1) - 1);
min_out = double(-2^(output_bits-1));
y_golden = min(max(y_golden, min_out), max_out);

% Save golden CSV (sample index + expected output).
golden_tbl = table((0:length(y_golden)-1).', round(y_golden(:)), ...
    'VariableNames', {'sample_idx', 'golden_out'});
writetable(golden_tbl, golden_csv_file);

% Load RTL baseline output from comparison CSV.
rtl_tbl = readtable(rtl_log_file);
if ~ismember('base', rtl_tbl.Properties.VariableNames)
    error('RTL CSV does not contain "base" column: %s', rtl_log_file);
end

rtl_base = rtl_tbl.base;
if any((double(rtl_base) > (2^(output_bits-1) - 1)) | (double(rtl_base) < (-2^(output_bits-1))))
    error(['RTL log contains values outside signed %d-bit output range. ' ...
        'The simulation log is stale or from the pre-32-bit-output RTL. ' ...
        'Re-run fir_filter_tb.v, then run this script again.'], output_bits);
end

N = min(length(rtl_base), length(y_golden));
err = double(rtl_base(1:N)) - double(round(y_golden(1:N)).');
abs_err = abs(err);

max_abs_err = max(abs_err);
mean_abs_err = mean(abs_err);
num_nonzero = nnz(abs_err ~= 0);

fprintf('\n=== RTL vs MATLAB Golden (Baseline) ===\n');
fprintf('Samples compared : %d\n', N);
fprintf('Max |error|      : %.0f\n', max_abs_err);
fprintf('Mean |error|     : %.3f\n', mean_abs_err);
fprintf('Non-zero errors  : %d\n', num_nonzero);

if num_nonzero == 0
    fprintf('RESULT: PASS (exact match)\n');
else
    fprintf('RESULT: FAIL (mismatch present)\n');
end

% Save detailed error report.
err_tbl = table((0:N-1).', rtl_base(1:N), round(y_golden(1:N)).', err(:), abs_err(:), ...
    'VariableNames', {'sample_idx', 'rtl_base', 'golden', 'error', 'abs_error'});
writetable(err_tbl, fullfile(results_dir, 'rtl_vs_golden_error.csv'));

fprintf('\nGenerated files:\n');
fprintf('  %s\n', golden_csv_file);
fprintf('  %s\n', fullfile(results_dir, 'rtl_vs_golden_error.csv'));
