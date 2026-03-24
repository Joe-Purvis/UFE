% ------------------------------------------------------------
% WR_RegisterStressTest_NoPortReopen.m
%
% Robust thrash-test for a single 8-bit read/write register over UART.
% Recovery strategy (NO COM port reopen):
%   - For each test value: WRITE -> READ -> compare
%   - If fault: do NOT advance; retry same value with escalating backoff
%     and drain-until-quiet resync attempts.
%   - If still failing after all attempts: abort test (unrecoverable).
%
% UART protocol:
%   Request : 55 OP ADDR DATA CHK
%   Response: 56 STATUS ADDR DATA CHK
% CHK = XOR of first four bytes.
% ------------------------------------------------------------

clear;
clc;

% -------------------------------
% Configuration
% -------------------------------
port        = "COM4";
baud        = 9600;

ADDR        = uint8(hex2dec("30"));

OP_READ8    = uint8(hex2dec("01"));
OP_WRITE8   = uint8(hex2dec("02"));

num_passes  = 10;
per_pattern = 256;

% Recovery policy (no port reopen)
attempt_delays_s      = [0.001, 0.010, 0.100, 0.250, 0.500];  % escalating backoff
quiet_window_s        = 0.050;                                 % quiet for 50ms
drain_max_total_s     = 1.0;                                   % max drain time
timeout_resp_s        = 1.0;                                   % wait for valid response
max_scan_bytes        = 6000;                                  % scan budget

require_status_ok     = true;                                  % require STATUS==0x00 for READ

serial_timeout_s      = 1.0;

rng(1);

% -------------------------------
% Logging
% -------------------------------
tstamp   = datestr(now, "yyyy-mm-dd_HHMMSS");
log_dir  = string(pwd);
log_file = fullfile(log_dir, "WR_RegisterStressTest_Log_" + tstamp + ".csv");

fid = fopen(log_file, "wt");
if fid < 0
     error("Could not open log file for writing: %s", log_file);
end

fprintf(fid, "timestamp,pass,pattern,idx,addr,tx,rx,status,result,reason,attempt,bytes_scanned,frames_rejected,bytes_drained\n");

fprintf("Logging to: %s\n", log_file);

% -------------------------------
% Open UART (once)
% -------------------------------
s = serialport(port, baud, ...
     "DataBits", 8, ...
     "Parity", "none", ...
     "StopBits", 1);

configureTerminator(s, uint8(0));
s.Timeout = serial_timeout_s;

flush(s);

fprintf("UART opened: %s @ %d baud\n", port, baud);

% -------------------------------
% Patterns
% -------------------------------
pat_names = ["INC", "DEC", "RND"];

total_ops    = 0;
total_errors = 0;

try
     for pass = 1:num_passes
          fprintf("\n=== PASS %d / %d ===\n", pass, num_passes);

          for pat = 1:3
               switch pat
                    case 1
                         vec = uint8(0:255);
                    case 2
                         vec = uint8(255:-1:0);
                    otherwise
                         vec = uint8(randi([0 255], 1, per_pattern));
               end

               fprintf("Pattern: %s\n", pat_names(pat));

               for k = 1:length(vec)
                    tx_val = vec(k);

                    % Keep retrying SAME value until success or abort.
                    [ok, reason] = deal(false, "INIT");

                    for attempt = 1:length(attempt_delays_s)
                         pause(attempt_delays_s(attempt));

                         bytes_drained = drain_until_quiet(s, quiet_window_s, drain_max_total_s);

                         uart_write_reg(s, ADDR, OP_WRITE8, tx_val);
                         pause(0.001);

                         uart_send_read_req(s, ADDR, OP_READ8);

                         [rx, rok, rreason, bscan, frej] = uart_read_response_strict( ...
                              s, ADDR, timeout_resp_s, max_scan_bytes, require_status_ok);

                         total_ops = total_ops + 1;

                         if ~rok
                              reason = rreason;
                              log_row(fid, pass, pat_names(pat), k, ADDR, tx_val, uint8(0), uint8(0), "FAIL", reason, attempt, bscan, frej, bytes_drained);
                              continue;
                         end

                         rx_status = rx(2);
                         rx_data   = rx(4);

                         if rx_data ~= tx_val
                              reason = "DATA_MISMATCH";
                              log_row(fid, pass, pat_names(pat), k, ADDR, tx_val, rx_data, rx_status, "FAIL", reason, attempt, bscan, frej, bytes_drained);
                              continue;
                         end

                         % Success
                         ok = true;
                         reason = "OK";
                         log_row(fid, pass, pat_names(pat), k, ADDR, tx_val, rx_data, rx_status, "PASS", reason, attempt, bscan, frej, bytes_drained);
                         break;
                    end

                    if ~ok
                         total_errors = total_errors + 1;
                         fprintf("ABORT: unrecoverable at pass=%d pat=%s idx=%d tx=%02X (reason=%s)\n", ...
                                 pass, pat_names(pat), k, tx_val, reason);
                         error("Unrecoverable failure at tx=%02X (pass=%d pat=%s idx=%d). See log: %s", ...
                               tx_val, pass, pat_names(pat), k, log_file);
                    end
               end
          end
     end

     fprintf("\n==============================\n");
     fprintf("TEST COMPLETE\n");
     fprintf("Total transactions: %d\n", total_ops);
     fprintf("Total unrecoverable errors: %d\n", total_errors);

     if total_errors == 0
          fprintf("RESULT: PASS\n");
     else
          fprintf("RESULT: FAIL (see log CSV)\n");
     end

catch ME
     fprintf("\nSTOPPED: %s\n", ME.message);
     rethrow(ME);
end

% Cleanup
if exist("s", "var")
     clear s;
end
fclose(fid);

% ------------------------------------------------------------
% Local functions
% ------------------------------------------------------------
function uart_write_reg(s, addr, op_write8, val)
     frame4 = uint8([0x55, op_write8, addr, val]);
     chk    = xor4(frame4);
     frame  = uint8([frame4, chk]);
     write(s, frame, "uint8");
end

function uart_send_read_req(s, addr, op_read8)
     frame4 = uint8([0x55, op_read8, addr, 0x00]);
     chk    = xor4(frame4);
     frame  = uint8([frame4, chk]);
     write(s, frame, "uint8");
end

function [rx, ok, reason, bytes_scanned, frames_rejected] = uart_read_response_strict(s, addr_expected, timeout_s, max_scan_bytes, require_status_ok)
     rx = uint8([]);
     ok = false;
     reason = "UNKNOWN";
     bytes_scanned = 0;
     frames_rejected = 0;

     t0 = tic;

     while toc(t0) < timeout_s && bytes_scanned < max_scan_bytes
          if s.NumBytesAvailable < 1
               pause(0.0005);
               continue;
          end

          b = read(s, 1, "uint8");
          b = b(:);
          bytes_scanned = bytes_scanned + 1;

          if b(1) ~= uint8(0x56)
               continue;
          end

          tail = read_exact(s, 4, timeout_s - toc(t0));
          if numel(tail) ~= 4
               reason = "RX_TAIL_TIMEOUT";
               return;
          end

          cand = uint8([uint8(0x56), tail(:).']);  % 1x5

          chk_calc = xor4(cand(1:4));
          if cand(5) ~= chk_calc
               frames_rejected = frames_rejected + 1;
               continue;
          end

          if cand(3) ~= addr_expected
               frames_rejected = frames_rejected + 1;
               continue;
          end

          if require_status_ok
               if cand(2) ~= uint8(0x00)
                    frames_rejected = frames_rejected + 1;
                    continue;
               end
          end

          rx = cand;
          ok = true;
          reason = "OK";
          return;
     end

     if bytes_scanned >= max_scan_bytes
          reason = "RX_SCAN_LIMIT";
     else
          reason = "RX_TIMEOUT";
     end
end

function out = read_exact(s, n, timeout_s)
     out = uint8([]);
     t0 = tic;

     while numel(out) < n && toc(t0) < timeout_s
          avail = s.NumBytesAvailable;
          if avail <= 0
               pause(0.0005);
               continue;
          end

          to_read = min(n - numel(out), avail);
          chunk = read(s, to_read, "uint8");
          chunk = chunk(:);
          out = [out; chunk]; %#ok<AGROW>
     end
end

function drained = drain_until_quiet(s, quiet_window_s, max_total_s)
     drained = 0;
     t0 = tic;
     quiet_t0 = tic;

     while toc(t0) < max_total_s
          if s.NumBytesAvailable > 0
               n = s.NumBytesAvailable;
               read(s, n, "uint8");
               drained = drained + n;
               quiet_t0 = tic;
          else
               if toc(quiet_t0) >= quiet_window_s
                    return;
               end
               pause(0.001);
          end
     end
end

function c = xor4(b4)
     c = bitxor(bitxor(bitxor(uint8(b4(1)), uint8(b4(2))), uint8(b4(3))), uint8(b4(4)));
end

function log_row(fid, pass, patname, idx, addr, tx, rx, status, result, reason, attempt, bytes_scanned, frames_rejected, bytes_drained)
     ts = datestr(now, "yyyy-mm-dd HH:MM:SS.FFF");
     fprintf(fid, "%s,%d,%s,%d,0x%02X,0x%02X,0x%02X,0x%02X,%s,%s,%d,%d,%d,%d\n", ...
             ts, pass, patname, idx, addr, tx, rx, status, result, reason, attempt, bytes_scanned, frames_rejected, bytes_drained);
end
