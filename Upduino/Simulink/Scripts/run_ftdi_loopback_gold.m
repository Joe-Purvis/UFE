% run_ftdi_loopback_gold.m
% Runs the GOLD Simulink loopback model from MATLAB and extracts UART bytes
% from the SimulationOutput object (out). This avoids workspace/export quirks.

clearvars;
clc;

repo_root  = "C:\Users\2923821P\OneDrive - University of Glasgow\Project\Upduino";
model_path = repo_root + "\Simulink\models\ftdi_loopback_test_GOLD.slx";

if ~isfile(model_path)
     error("Model not found: %s", model_path);
end

load_system(model_path);

% Always run via sim() and capture outputs in 'out'
out = sim(model_path);

% Bytes must be logged by a To Workspace block named exactly 'rx_bytes'
if ~isprop(out, "rx_bytes")
     error("out.rx_bytes not found. Confirm the To Workspace block Variable name is exactly: rx_bytes");
end

rx_bytes = out.rx_bytes;

rx_stream = squeeze(rx_bytes);
rx_linear = rx_stream(:);

%disp("Decoded ASCII (best effort):");
%disp(char(rx_linear.'));

% Save a reproducible artifact
data_dir = repo_root + "\Simulink\MATLAB";
if ~isfolder(data_dir)
     mkdir(data_dir);
end

stamp = datestr(now, "yyyy-mm-dd_HHMMSS");
rx_linear = rx_linear(rx_linear ~= 0);   % remove padding / repeated frames
save(data_dir + "\loopback_" + stamp + ".mat", "rx_bytes", "rx_stream", "rx_linear", "model_path");
fprintf('%s\n', char(rx_linear(1:find(rx_linear==10,1,'first')).'));


