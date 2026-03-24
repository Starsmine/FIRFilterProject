%% FIR Filter Design - Low-pass filter
% Objective: Design a 100-tap (or more) low-pass FIR filter
% Specifications:
%   - Transition band: 0.2π to 0.23π rad/sample
%   - Stopband attenuation: ≥ 80 dB
%   - Implementation options: pipelining, parallel processing (L=2,3), or combined

clear all; close all; clc;

%% Design Specifications
Fpass = 0.2;              % Passband edge (normalized frequency, 0.2π rad/sample)
Fstop = 0.23;             % Stopband edge (normalized frequency, 0.23π rad/sample)
Apass = 1;                % Passband ripple (dB)
Astop = 80;               % Stopband attenuation (dB)
num_taps = 100;           % Minimum number of taps

%% Design both filters: fixed 100-tap and spec-meeting reference
% Reference design lets MATLAB choose order to meet the ripple/attenuation spec.
d = fdesign.lowpass('Fp,Fst,Ap,Ast', Fpass, Fstop, Apass, Astop);
Hd_ref = design(d, 'equiripple');
h_ref = Hd_ref.Numerator(:).';
N_ref = length(h_ref);

% Fixed-order 100-tap design for direct Verilog implementation.
% Park-McClellan design with weighted error to meet specs as closely as possible
% Stop band dominant, not good for audio.
dp = (10^(Apass/20)-1) / (10^(Apass/20)+1);
ds = 10^(-Astop/20);
weights = [1/dp, 1/ds];
h_100 = firpm(num_taps-1, [0 Fpass Fstop 1], [1 1 0 0], weights);
N_100 = length(h_100);

fprintf('Reference filter taps (spec-meeting): %d\n', N_ref);
fprintf('Fixed filter taps (for RTL): %d\n', N_100);

%% Analyze floating-point frequency response
[H_ref, w] = freqz(h_ref, 1, 8192);
[H_100, ~] = freqz(h_100, 1, 8192);
H_ref_dB = 20*log10(abs(H_ref) + eps);
H_100_dB = 20*log10(abs(H_100) + eps);

pass_idx = (w <= pi*Fpass);
stop_idx = (w >= pi*Fstop);

ref_pass_ripple = max(H_ref_dB(pass_idx)) - min(H_ref_dB(pass_idx));
ref_stop_attn = -max(H_ref_dB(stop_idx));
f100_pass_ripple = max(H_100_dB(pass_idx)) - min(H_100_dB(pass_idx));
f100_stop_attn = -max(H_100_dB(stop_idx));

% Set up output directories for figures and results
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
results_dir = fullfile(project_root, 'results');
figures_dir = fullfile(results_dir, 'figures');
if ~exist(figures_dir, 'dir'); mkdir(figures_dir); end

figure('Name', 'Floating-Point Filter Comparison');
plot(w/pi, H_ref_dB, 'b', 'LineWidth', 1.5); hold on;
plot(w/pi, H_100_dB, 'k--', 'LineWidth', 1.5);
grid on; xlabel('Normalized Frequency (pi rad/sample)');
ylabel('Magnitude (dB)');
title('Floating-Point Response: Spec-Meeting vs Fixed 100-Tap');
axis([0 1 -120 5]);
legend(sprintf('Reference (%d taps)', N_ref), sprintf('Fixed (%d taps)', N_100));
print(gcf, fullfile(figures_dir, 'fig1_floatpoint_comparison'), '-dsvg');

%% Quantization Analysis
coeff_bits = 21;          % Coefficient quantization (bits used for export files)
coeff_bits_32 = 32;       % Additional export precision for 32-bit fixed-point comparison
input_bits = 16;          % Input data quantization (bits)
output_bits = 32;         % Output data quantization (bits)

% Sweep coefficient quantization from 10 to 20 bits.
bit_sweep = 10:24;
num_sweep = length(bit_sweep);
ref_stop_attn_sweep = zeros(1, num_sweep);
f100_stop_attn_sweep = zeros(1, num_sweep);
ref_pass_ripple_sweep = zeros(1, num_sweep);
f100_pass_ripple_sweep = zeros(1, num_sweep);

for k = 1:num_sweep
    b = bit_sweep(k);

    ref_scale_k = (2^(b-1)-1) / max(abs(h_ref));
    h_ref_q_k = round(h_ref * ref_scale_k) / ref_scale_k;
    [H_ref_q_k, ~] = freqz(h_ref_q_k, 1, 8192);
    H_ref_q_k_dB = 20*log10(abs(H_ref_q_k) + eps);
    ref_stop_attn_sweep(k) = -max(H_ref_q_k_dB(stop_idx));
    ref_pass_ripple_sweep(k) = max(H_ref_q_k_dB(pass_idx)) - min(H_ref_q_k_dB(pass_idx));

    f100_scale_k = (2^(b-1)-1) / max(abs(h_100));
    h_100_q_k = round(h_100 * f100_scale_k) / f100_scale_k;
    [H_100_q_k, ~] = freqz(h_100_q_k, 1, 8192);
    H_100_q_k_dB = 20*log10(abs(H_100_q_k) + eps);
    f100_stop_attn_sweep(k) = -max(H_100_q_k_dB(stop_idx));
    f100_pass_ripple_sweep(k) = max(H_100_q_k_dB(pass_idx)) - min(H_100_q_k_dB(pass_idx));
end

idx_ref_meet = find(ref_stop_attn_sweep >= Astop, 1, 'first');
idx_f100_meet = find(f100_stop_attn_sweep >= Astop, 1, 'first');

fprintf('\n=== Quantization Sweep (10 to 20 bits) ===\n');
fprintf('Bits | Ref Stop(dB) | Ref Ripple(dB) | 100tap Stop(dB) | 100tap Ripple(dB)\n');
for k = 1:num_sweep
    fprintf('%4d | %11.2f | %14.4f | %14.2f | %17.4f\n', ...
        bit_sweep(k), ref_stop_attn_sweep(k), ref_pass_ripple_sweep(k), ...
        f100_stop_attn_sweep(k), f100_pass_ripple_sweep(k));
end

if isempty(idx_ref_meet)
    fprintf('Reference filter does not meet %.1f dB stopband in 10-20 bits.\n', Astop);
else
    fprintf('Reference filter minimum bits meeting %.1f dB stopband: %d\n', Astop, bit_sweep(idx_ref_meet));
end

if isempty(idx_f100_meet)
    fprintf('Fixed-100 filter does not meet %.1f dB stopband in 10-20 bits.\n', Astop);
else
    fprintf('Fixed-100 filter minimum bits meeting %.1f dB stopband: %d\n', Astop, bit_sweep(idx_f100_meet));
end

figure('Name', 'Quantization Sweep: Stopband Attenuation');
plot(bit_sweep, ref_stop_attn_sweep, 'bo-', 'LineWidth', 1.5); hold on;
plot(bit_sweep, f100_stop_attn_sweep, 'ks--', 'LineWidth', 1.5);
yline(Astop, 'r:', 'LineWidth', 1.5);
grid on; xlabel('Coefficient Bit Width'); ylabel('Stopband Attenuation (dB)');
title('Quantization Sweep (10 to 24 bits)');
legend('Reference filter', 'Fixed 100-tap filter', sprintf('Target %.0f dB', Astop), 'Location', 'southeast');
print(gcf, fullfile(figures_dir, 'fig2_quantization_sweep'), '-dsvg');

% Quantize reference filter with 20-bit coefficient word.
ref_scale = (2^(coeff_bits-1)-1) / max(abs(h_ref));
h_ref_q = round(h_ref * ref_scale) / ref_scale;

% Use floating-point (unquantized) coefficients for 100-tap filter.
h_100_q = h_100;

[H_ref_q, ~] = freqz(h_ref_q, 1, 8192);
[H_100_q, ~] = freqz(h_100_q, 1, 8192);
H_ref_q_dB = 20*log10(abs(H_ref_q) + eps);
H_100_q_dB = 20*log10(abs(H_100_q) + eps);

ref_q_stop_attn = -max(H_ref_q_dB(stop_idx));
f100_q_stop_attn = -max(H_100_q_dB(stop_idx));

figure('Name', 'Quantized vs Floating-Point Comparison');
plot(w/pi, H_ref_dB, 'b', 'LineWidth', 1.3); hold on;
plot(w/pi, H_ref_q_dB, 'r--', 'LineWidth', 1.3);
plot(w/pi, H_100_dB, 'k', 'LineWidth', 1.3);
plot(w/pi, H_100_q_dB, 'm--', 'LineWidth', 1.3);
grid on; xlabel('Normalized Frequency (pi rad/sample)');
ylabel('Magnitude (dB)');
title('Original and Quantized Responses');
axis([0 1 -120 5]);
legend( ...
    sprintf('Reference float (%d taps)', N_ref), ...
    sprintf('Reference quantized (%d-bit)', coeff_bits), ...
    sprintf('Fixed 100 float (%d taps)', N_100), ...
    sprintf('Fixed 100 quantized (%d-bit)', coeff_bits));
print(gcf, fullfile(figures_dir, 'fig3_quantized_vs_float'), '-dsvg');

fprintf('\n=== Summary ===\n');
fprintf('Reference filter: %d taps with %d-bit quantized coefficients\n', N_ref, coeff_bits);
fprintf('Fixed-100 filter: %d taps with floating-point coefficients\n', N_100);
fprintf('Input bits: %d | Output bits: %d\n', input_bits, output_bits);
fprintf('Reference float: passband ripple = %.3f dB, stopband attn = %.2f dB\n', ref_pass_ripple, ref_stop_attn);
fprintf('Reference quant (%d-bit): stopband attn = %.2f dB\n', coeff_bits, ref_q_stop_attn);
fprintf('Fixed-100 float: passband ripple = %.3f dB, stopband attn = %.2f dB\n', f100_pass_ripple, f100_stop_attn);

%% Save both coefficient sets for Verilog implementation
if ~exist(results_dir, 'dir'); mkdir(results_dir); end

save(fullfile(results_dir, 'fir_coefficients.mat'), ...
    'h_ref', 'h_ref_q', 'N_ref', ...
    'h_100', 'h_100_q', 'N_100', ...
    'coeff_bits', 'coeff_bits_32', 'input_bits', 'output_bits', ...
    'bit_sweep', 'ref_stop_attn_sweep', 'f100_stop_attn_sweep', ...
    'ref_pass_ripple_sweep', 'f100_pass_ripple_sweep', ...
    'Fpass', 'Fstop', 'Apass', 'Astop');

%% Export HEX for both filters
% Reference filter: coeff_bits-bit quantized coefficients
ref_int = round(h_ref_q * (2^(coeff_bits-1)-1) / max(abs(h_ref_q)));
ref_hex = upper(dec2hex(mod(ref_int, 2^coeff_bits), ceil(coeff_bits/4)));
fid_ref = fopen(fullfile(results_dir, 'fir_coefficients_reference.hex'), 'w');
for i = 1:length(ref_int)
    fprintf(fid_ref, '%s\n', ref_hex(i,:));
end
fclose(fid_ref);

% Fixed-100 filter: also export quantized HEX for direct RTL comparison.
f100_int = round(h_100 * (2^(coeff_bits-1)-1) / max(abs(h_100)));
f100_hex = upper(dec2hex(mod(f100_int, 2^coeff_bits), ceil(coeff_bits/4)));
fid_100_hex = fopen(fullfile(results_dir, 'fir_coefficients_fixed100.hex'), 'w');
for i = 1:length(f100_int)
    fprintf(fid_100_hex, '%s\n', f100_hex(i,:));
end
fclose(fid_100_hex);

%% Export 32-bit fixed HEX for both filters
% These files are generated directly from MATLAB quantization (not sign-extension).
ref32_int = round(h_ref * (2^(coeff_bits_32-1)-1) / max(abs(h_ref)));
ref32_hex = upper(dec2hex(mod(ref32_int, 2^coeff_bits_32), ceil(coeff_bits_32/4)));
fid_ref32 = fopen(fullfile(results_dir, 'fir_coefficients_reference_fixed32.hex'), 'w');
for i = 1:length(ref32_int)
    fprintf(fid_ref32, '%s\n', ref32_hex(i,:));
end
fclose(fid_ref32);

f100_32_int = round(h_100 * (2^(coeff_bits_32-1)-1) / max(abs(h_100)));
f100_32_hex = upper(dec2hex(mod(f100_32_int, 2^coeff_bits_32), ceil(coeff_bits_32/4)));
fid_100_32_hex = fopen(fullfile(results_dir, 'fir_coefficients_fixed100_fixed32.hex'), 'w');
for i = 1:length(f100_32_int)
    fprintf(fid_100_32_hex, '%s\n', f100_32_hex(i,:));
end
fclose(fid_100_32_hex);

% Fixed-100 filter: floating-point coefficients (export as MATLAB text format)
% Save floating-point coefficients as a readable format for manual import into Verilog
fid_100 = fopen(fullfile(results_dir, 'fir_coefficients_fixed100_float.txt'), 'w');
fprintf(fid_100, '%% 100-tap FIR filter floating-point coefficients\n');
fprintf(fid_100, '%% Use these as real-valued references or convert to fixed-point as needed\n');
for i = 1:length(h_100)
    fprintf(fid_100, 'h[%3d] = %+.15e\n', i-1, h_100(i));
end
fclose(fid_100);

fprintf('\nExported coefficient files:\n');
fprintf('1) %s (175-tap reference: %d-bit hex)\n', fullfile(results_dir, 'fir_coefficients_reference.hex'), coeff_bits);
fprintf('2) %s (100-tap fixed: %d-bit hex for RTL comparison)\n', fullfile(results_dir, 'fir_coefficients_fixed100.hex'), coeff_bits);
fprintf('3) %s (175-tap reference: %d-bit hex)\n', fullfile(results_dir, 'fir_coefficients_reference_fixed32.hex'), coeff_bits_32);
fprintf('4) %s (100-tap fixed: %d-bit hex for RTL comparison)\n', fullfile(results_dir, 'fir_coefficients_fixed100_fixed32.hex'), coeff_bits_32);
fprintf('5) %s (100-tap fixed: floating-point text)\n', fullfile(results_dir, 'fir_coefficients_fixed100_float.txt'));
fprintf('\nReference file for spec-meeting design (target 80 dB stopband)\n');
fprintf('Fixed-100 files for reduced-complexity architecture (RTL and float reference)\n');
fprintf('\nFigures saved to: %s\n', figures_dir);
fprintf('  fig1_floatpoint_comparison.svg\n');
fprintf('  fig2_quantization_sweep.svg\n');
fprintf('  fig3_quantized_vs_float.svg\n');
