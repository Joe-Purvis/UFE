function SystemCalculatorApp()
% ------------------------------------------------------------
% System Calculator (MATLAB UI)
%
% Inputs:
%   Medium -> speed of sound c (m/s)
%   Active frequency f (Hz)
%   Active diameter d (m)
%   Burst cycles N (integer)
%   Ground time after burst (us)
%
% Derived:
%   lambda = c / f
%   R ~= d^2 / (4*lambda)
%   Round-trip travel time t_rt = 2R / c
%
% Timing:
%   Burst duration t_burst = N / f
%   Ground window: [t_burst, t_burst + t_ground]
%   Expected echo arrival time t_echo = t_rt
%
% Receive window:
%   Lead time t_lead = max(4 us, 5% of t_echo)
%   RX window start  = t_echo - t_lead
%   RX window dur    = t_burst
%   RX window end    = RX start + t_burst
%
% Integer/HEX export fields (8-bit):
%   RX Start and RX Duration are truncated integer microseconds.
%   8-bit register value = clamp(int_us, 0..255).
%   HEX displayed as 0x%02X (e.g., 0x72).
%
% Hardware write+readback verify:
%   Button adjacent to RX Start performs:
%     1) WRITE8 to test register @ 0x30 with RX_START_U8
%     2) READ8 from test register @ 0x30
%     3) Compare readback to written value
%   On match: RX Start indicators turn GREEN
%   On mismatch/timeout/invalid response: WARNING and results panel pastel red
%
% UART frame formats:
%   Request : 55 OP ADDR DATA CHK
%             CHK = XOR(55,OP,ADDR,DATA)
%   Response: 56 STATUS ADDR DATA CHK
%             CHK = XOR(56,STATUS,ADDR,DATA)
%
% UI:
%   - Results pane table-only for values (no repeated labels)
%   - WARNING -> results panel turns pastel red
%   - Clicked/changed inputs become green and stay green
%   - Medium dropdown is never green; selecting Medium highlights only c
% ------------------------------------------------------------

     fig = uifigure('Name','System Calculator','Position',[100 100 980 640]);

     gl = uigridlayout(fig,[1 2]);
     gl.ColumnWidth = {'1x','1x'};
     gl.RowHeight   = {'1x'};

     leftPanel  = uipanel(gl,'Title','Inputs / Questions');
     rightPanel = uipanel(gl,'Title','Results');

     normalRightBg = rightPanel.BackgroundColor;
     warnRightBg   = [1.00 0.85 0.85];
     okGreenBg      = [0.80 1.00 0.80];

     leftGL = uigridlayout(leftPanel,[12 2]);
     leftGL.ColumnWidth = {300,'1x'};
     leftGL.RowHeight   = {34,34,34,34,34,34,34,34,34,'1x',34,34};

     % Results layout:
     %   Row1: status
     %   Row2: RX Start action row (adjacent button)
     %   Row3: table (everything else)
     rightGL = uigridlayout(rightPanel,[3 1]);
     rightGL.RowHeight = {28,40,'1x'};

     % -----------------------------
     % Medium table
     % -----------------------------
     mediumNames = {
          'Pure water (20°C)'
          'Seawater (~35 PSU, 20°C)'
          'Saline (0.9%)'
          'Air (20°C)'
          'Fat (typ.)'
          'Muscle (typ.)'
          'Soft tissue (generic)'
          'Cortical bone (typ.)'
          'Custom...'
          };

     mediumC_mps = [
          1482
          1520
          1540
          343
          1450
          1580
          1540
          3500
          NaN
          ];

     % -----------------------------
     % Frequency list (500 kHz to 10 MHz in 500 kHz steps)
     % -----------------------------
     f_kHz = (500:500:10000).';
     freqItems = arrayfun(@(x) sprintf('%.1f MHz',x/1000), f_kHz, 'UniformOutput', false);

     % -----------------------------
     % Diameter list (5 mm to 50 mm in 1 mm steps)
     % -----------------------------
     d_mm = (5:1:50).';
     diamItems = arrayfun(@(x) sprintf('%d mm',x), d_mm, 'UniformOutput', false);

     % -----------------------------
     % Inputs
     % -----------------------------
     uilabel(leftGL,'Text','Medium:');
     ddMedium = uidropdown(leftGL,'Items',mediumNames,'Value',mediumNames{1}, ...
          'ValueChangedFcn',@onMediumChanged);

     uilabel(leftGL,'Text','Speed of sound, c (m/s):');
     edC_mps = uieditfield(leftGL,'numeric','Value',mediumC_mps(1), ...
          'ValueChangedFcn',@onAnyInputChanged);
     edC_mps.Editable = 'off';

     uilabel(leftGL,'Text','Active frequency:');
     ddFreq = uidropdown(leftGL,'Items',freqItems,'Value',freqItems{1}, ...
          'ValueChangedFcn',@onAnyInputChanged);

     uilabel(leftGL,'Text','Active diameter:');
     ddDiam = uidropdown(leftGL,'Items',diamItems,'Value',diamItems{1}, ...
          'ValueChangedFcn',@onAnyInputChanged);

     uilabel(leftGL,'Text','Burst cycles, N (integer):');
     edCycles = uieditfield(leftGL,'numeric','Value',20, ...
          'ValueChangedFcn',@onAnyInputChanged);

     uilabel(leftGL,'Text','Ground time after burst (µs):');
     edGround_us = uieditfield(leftGL,'numeric','Value',5, ...
          'ValueChangedFcn',@onAnyInputChanged);

     % UART settings for write-to-device button
     uilabel(leftGL,'Text','COM Port (for write):');
     edCom = uieditfield(leftGL,'text','Value','COM4', ...
          'ValueChangedFcn',@onAnyInputChanged);

     uilabel(leftGL,'Text','Baud (for write):');
     edBaud = uieditfield(leftGL,'numeric','Value',9600, ...
          'ValueChangedFcn',@onAnyInputChanged);

     btnReset = uibutton(leftGL,'push','Text','Reset','ButtonPushedFcn',@onReset);
     btnReset.Layout.Row = 12;
     btnReset.Layout.Column = [1 2];

     % -----------------------------
     % Results: status
     % -----------------------------
     lblStatus = uilabel(rightGL,'Text','Status: Ready','FontWeight','bold');

     % -----------------------------
     % Results: RX Start action row (adjacent button)
     % -----------------------------
     rxGL = uigridlayout(rightGL,[1 6]);
     rxGL.ColumnWidth = {120,90,110,90,'1x',170};
     rxGL.RowHeight   = {34};
     rxGL.Padding     = [6 2 6 2];

     uilabel(rxGL,'Text','RX Start (u8):','FontWeight','bold');
     lblRxStart_u8 = uilabel(rxGL,'Text','-');

     uilabel(rxGL,'Text','RX Start (hex):','FontWeight','bold');
     lblRxStart_hex = uilabel(rxGL,'Text','-');

     uilabel(rxGL,'Text','Test reg @ 0x30:','HorizontalAlignment','right');
     btnWriteRxStart = uibutton(rxGL,'push','Text','Write+Readback 0x30', ...
          'ButtonPushedFcn',@onWriteRxStart);

     % -----------------------------
     % Results: table (single source of truth)
     % -----------------------------
     tbl = uitable(rightGL);
     tbl.Data = cell(0,3);
     tbl.ColumnName = {'Name','Value','Units'};
     tbl.ColumnEditable = [false false false];

     % -----------------------------
     % State: computed values used by button
     % -----------------------------
     state = struct();
     state.rx_start_us_i = 0;
     state.rx_start_u8   = uint8(0);
     state.rx_start_hex  = '0x00';

     % -----------------------------
     % Persistent highlight support
     % -----------------------------
     highlightControls = {edC_mps, ddFreq, ddDiam, edCycles, edGround_us, edCom, edBaud};

     clearAllHighlights();
     ddMedium.BackgroundColor = [1 1 1];

     fig.WindowButtonDownFcn = @onWindowMouseDown;

     % -----------------------------
     % Initialise
     % -----------------------------
     clearRxVerifyIndicators();
     onMediumChanged();
     onCompute();

     % -----------------------------
     % Callbacks
     % -----------------------------
     function onWindowMouseDown(~,~)
          obj = hittest(fig);
          ctrl = coerceToControl(obj);

          if isempty(ctrl)
               return;
          end

          if ctrl == ddMedium
               ddMedium.BackgroundColor = [1 1 1];
               markTouched(edC_mps);
               return;
          end

          if isHighlightControl(ctrl)
               markTouched(ctrl);
          end
     end

     function tf = isHighlightControl(ctrl)
          tf = false;
          for ii = 1:numel(highlightControls)
               if ctrl == highlightControls{ii}
                    tf = true;
                    return;
               end
          end
     end

     function ctrl = coerceToControl(obj)
          ctrl = [];

          if isempty(obj) || ~isvalid(obj)
               return;
          end

          if obj == ddMedium
               ctrl = ddMedium;
               return;
          end

          for ii = 1:numel(highlightControls)
               if obj == highlightControls{ii}
                    ctrl = obj;
                    return;
               end
          end

          try
               p = obj.Parent;
          catch
               p = [];
          end

          while ~isempty(p) && isvalid(p)
               if p == ddMedium
                    ctrl = ddMedium;
                    return;
               end

               for ii = 1:numel(highlightControls)
                    if p == highlightControls{ii}
                         ctrl = p;
                         return;
                    end
               end

               try
                    p = p.Parent;
               catch
                    p = [];
               end
          end
     end

     function onAnyInputChanged(src,~)
          if src == ddMedium
               ddMedium.BackgroundColor = [1 1 1];
               markTouched(edC_mps);
          else
               if isHighlightControl(src)
                    markTouched(src);
               end
          end
          clearRxVerifyIndicators(); % inputs changed -> prior verification invalid
          onCompute();
     end

     function onMediumChanged(~,~)
          ddMedium.BackgroundColor = [1 1 1];

          idx = find(strcmp(mediumNames, ddMedium.Value),1);
          if isempty(idx)
               idx = 1;
          end

          cVal = mediumC_mps(idx);

          if isnan(cVal)
               edC_mps.Editable = 'on';
               if ~isfinite(edC_mps.Value) || edC_mps.Value <= 0
                    edC_mps.Value = 1540;
               end
          else
               edC_mps.Value = cVal;
               edC_mps.Editable = 'off';
          end

          markTouched(edC_mps);
          clearRxVerifyIndicators();
          onCompute();
     end

     function onReset(~,~)
          ddMedium.Value = mediumNames{1};
          edC_mps.Value  = mediumC_mps(1);
          edC_mps.Editable = 'off';

          ddFreq.Value = freqItems{1};
          ddDiam.Value = diamItems{1};

          edCycles.Value = 20;
          edGround_us.Value = 5;

          edCom.Value = 'COM4';
          edBaud.Value = 9600;

          clearAllHighlights();
          ddMedium.BackgroundColor = [1 1 1];

          rightPanel.BackgroundColor = normalRightBg;
          lblStatus.Text = 'Status: Ready';
          tbl.Data = cell(0,3);

          state.rx_start_us_i = 0;
          state.rx_start_u8   = uint8(0);
          state.rx_start_hex  = '0x00';

          clearRxVerifyIndicators();
          onCompute();
     end

     function onWriteRxStart(~,~)
          % WRITE RX_START_U8 to 0x30, then READ it back and verify.
          clearRxVerifyIndicators();

          try
               port = strtrim(edCom.Value);
               if isempty(port)
                    error('COM Port is empty.');
               end

               baud = requireFinitePositive(edBaud.Value,'Baud');
               baud = floor(baud + 0.5);

               data_u8 = state.rx_start_u8;

               ADDR = uint8(hex2dec('30'));

               sp = serialport(port, baud, "DataBits", 8, "Parity", "none", "StopBits", 1);
               cleanup = onCleanup(@() clear('sp'));

               configureTerminator(sp, uint8(0));
               sp.Timeout = 1.0;
               flush(sp);

               % ------------------------
               % 1) WRITE8
               % ------------------------
               txW = makeReq(uint8(hex2dec('55')), uint8(hex2dec('02')), ADDR, uint8(data_u8));
               write(sp, txW, "uint8");

               % Give device a brief moment
               pause(0.02);
               flush(sp);  % discard any unsolicited bytes after write

               % ------------------------
               % 2) READ8
               % ------------------------
               txR = makeReq(uint8(hex2dec('55')), uint8(hex2dec('01')), ADDR, uint8(0));
               write(sp, txR, "uint8");

               % ------------------------
               % 3) Read response (5 bytes)
               % ------------------------
               rx = readExact(sp, 5, 0.25);  % 250 ms budget
               validateResp(rx, ADDR);

               dataRead = rx(4);  % 56 STATUS ADDR DATA CHK

               % ------------------------
               % 4) Compare
               % ------------------------
               if uint8(dataRead) == uint8(data_u8)
                    setRxVerifyOk();
                    rightPanel.BackgroundColor = normalRightBg;
                    lblStatus.Text = sprintf('Status: OK - Verified write/readback %s at 0x30', state.rx_start_hex);
               else
                    rightPanel.BackgroundColor = warnRightBg;
                    lblStatus.Text = sprintf('Status: WARNING - Readback mismatch. Wrote %s, read %s', ...
                         toHex8(uint8(data_u8)), toHex8(uint8(dataRead)));
               end

          catch ME
               rightPanel.BackgroundColor = warnRightBg;
               lblStatus.Text = ['Status: ERROR - write/readback failed: ' ME.message];
          end
     end

     % -----------------------------
     % Compute + display
     % -----------------------------
     function onCompute()
          try
               c = requireFinitePositive(edC_mps.Value,'Speed of sound c (m/s)');

               fIdx = find(strcmp(freqItems, ddFreq.Value),1);
               if isempty(fIdx), fIdx = 1; end
               f = f_kHz(fIdx) * 1e3;

               dIdx = find(strcmp(diamItems, ddDiam.Value),1);
               if isempty(dIdx), dIdx = 1; end
               d_m = d_mm(dIdx) * 1e-3;

               N = requirePositiveInteger(edCycles.Value,'Burst cycles N');
               t_ground_us = requireFiniteNonNegative(edGround_us.Value,'Ground time (µs)');

               lambda = c / f;
               R = (d_m*d_m) / (4 * lambda);

               t_rt = (2 * R) / c;         % seconds
               t_burst = N / f;            % seconds
               t_ground = t_ground_us * 1e-6;

               t_ground_start = t_burst;
               t_ground_end   = t_burst + t_ground;

               t_echo = t_rt;

               t_lead = max(4e-6, 0.05 * t_echo);

               t_rx_start = t_echo - t_lead;
               t_rx_dur   = t_burst;
               t_rx_end   = t_rx_start + t_rx_dur;

               % Engineering units
               R_mm = R * 1e3;
               R_mm_1dp = floor(R_mm * 10 + 0.5) / 10;

               t_rt_us     = t_rt * 1e6;
               t_burst_us  = t_burst * 1e6;
               t_echo_us   = t_echo * 1e6;
               t_gs_us     = t_ground_start * 1e6;
               t_ge_us     = t_ground_end * 1e6;

               t_lead_us   = t_lead * 1e6;
               t_rx_s_us   = t_rx_start * 1e6;
               t_rx_d_us   = t_rx_dur * 1e6;
               t_rx_e_us   = t_rx_end * 1e6;

               % Integer microseconds (truncate)
               rx_start_us_i = floor(t_rx_s_us);
               rx_dur_us_i   = floor(t_rx_d_us);
               burst_us_i    = floor(t_burst_us);

               % 8-bit register versions (clamp 0..255)
               rx_start_u8 = clampU8(rx_start_us_i);
               rx_dur_u8   = clampU8(rx_dur_us_i);
               burst_u8    = clampU8(burst_us_i);

               rx_start_hex = toHex8(rx_start_u8);
               rx_dur_hex   = toHex8(rx_dur_u8);
               burst_hex    = toHex8(burst_u8);

               % Update state + adjacent RX Start widgets
               state.rx_start_us_i = rx_start_us_i;
               state.rx_start_u8   = rx_start_u8;
               state.rx_start_hex  = rx_start_hex;

               lblRxStart_u8.Text  = sprintf('%d', double(rx_start_u8));
               lblRxStart_hex.Text = rx_start_hex;

               % Status / checks
               warn = false;
               warnMsg = '';

               if t_rx_start < 0
                    warn = true;
                    warnMsg = 'RX start < 0';
               end

               overlap = (t_rx_start < t_ground_end) && (t_rx_end > t_ground_start);
               if overlap
                    warn = true;
                    if isempty(warnMsg)
                         warnMsg = 'RX overlaps ground';
                    else
                         warnMsg = [warnMsg '; RX overlaps ground'];
                    end
               end

               % 8-bit overflow warnings
               if rx_start_us_i > 255 || rx_dur_us_i > 255 || burst_us_i > 255
                    warn = true;
                    if isempty(warnMsg)
                         warnMsg = '8-bit clamp applied';
                    else
                         warnMsg = [warnMsg '; 8-bit clamp applied'];
                    end
               end

               if warn
                    lblStatus.Text = ['Status: WARNING - ' warnMsg];
                    rightPanel.BackgroundColor = warnRightBg;
               else
                    if startsWith(lblStatus.Text,'Status: OK')
                         % preserve an "OK - Verified..." message from button
                         rightPanel.BackgroundColor = normalRightBg;
                    else
                         lblStatus.Text = 'Status: OK';
                         rightPanel.BackgroundColor = normalRightBg;
                    end
               end

               k = 2*pi/lambda;
               ka = k*(d_m/2);

               tbl.Data = {
                    'Medium',                      ddMedium.Value, '';
                    'Speed of sound (c)',          c,              'm/s';
                    'Frequency (f)',               f/1e6,          'MHz';
                    'Diameter (d)',                d_m*1e3,        'mm';

                    'Burst cycles (N)',            N,              '';
                    'Burst duration (N/f)',        t_burst_us,     'µs';
                    'Burst duration (int)',        burst_us_i,     'µs';
                    'Burst duration (u8)',         double(burst_u8), '';
                    'Burst duration (hex u8)',     burst_hex,      '';

                    'Ground time',                 t_ground_us,    'µs';
                    'Ground start',                t_gs_us,        'µs';
                    'Ground end',                  t_ge_us,        'µs';

                    'Wavelength (λ)',              lambda*1e3,     'mm';
                    'Focal distance (R)',          R_mm_1dp,       'mm';
                    'Round-trip time (2R/c)',      t_rt_us,        'µs';
                    'Expected echo arrival',       t_echo_us,      'µs';

                    'RX lead time',                t_lead_us,      'µs';
                    'RX start',                    t_rx_s_us,      'µs';
                    'RX duration',                 t_rx_d_us,      'µs';
                    'RX end',                      t_rx_e_us,      'µs';

                    'RX start (int)',              rx_start_us_i,  'µs';
                    'RX start (u8)',               double(rx_start_u8), '';
                    'RX start (hex u8)',           rx_start_hex,   '';

                    'RX duration (int)',           rx_dur_us_i,    'µs';
                    'RX duration (u8)',            double(rx_dur_u8), '';
                    'RX duration (hex u8)',        rx_dur_hex,     '';

                    'k·a',                         ka,             '';
                    };

          catch ME
               lblStatus.Text = ['Status: ERROR - ' ME.message];
               rightPanel.BackgroundColor = warnRightBg;
               tbl.Data = cell(0,3);
          end
     end

     % -----------------------------
     % UART helpers
     % -----------------------------
     function tx = makeReq(sync, op, addr, data)
          chk = bitxor(bitxor(bitxor(sync, op), addr), data);
          tx = uint8([sync op addr data chk]);
     end

     function rx = readExact(sp, n, budget_s)
          % Read exactly n bytes within budget_s seconds.
          % Force each read chunk to be a column vector so concatenation is always consistent.
          t0 = tic();
          buf = uint8([]);

          while numel(buf) < n
               if toc(t0) > budget_s
                    error('Timeout waiting for %d response bytes (got %d).', n, numel(buf));
               end

               avail = sp.NumBytesAvailable;
               if avail > 0
                    k = min(avail, n - numel(buf));
                    chunk = read(sp, k, "uint8");
                    chunk = uint8(chunk(:));          % <-- critical: force column
                    buf = [buf; chunk];               %#ok<AGROW>
               else
                    pause(0.005);
               end
          end

          rx = buf(1:n).';  % return 1xN row vector
     end


     function validateResp(rx, addrExpected)
          if numel(rx) ~= 5
               error('Invalid response length (%d).', numel(rx));
          end

          sync = uint8(rx(1));
          status = uint8(rx(2));
          addr = uint8(rx(3));
          data = uint8(rx(4));
          chk  = uint8(rx(5));

          if sync ~= uint8(hex2dec('56'))
               error('Bad response SYNC (0x%02X).', sync);
          end

          if addr ~= uint8(addrExpected)
               error('Bad response ADDR (0x%02X).', addr);
          end

          chkExp = bitxor(bitxor(bitxor(sync, status), addr), data);
          if chk ~= chkExp
               error('Bad response CHK (got 0x%02X, expected 0x%02X).', chk, chkExp);
          end
     end

     % -----------------------------
     % Misc helpers
     % -----------------------------
     function x = requireFinitePositive(x,label)
          if isempty(x) || ~isfinite(x) || x <= 0
               error('%s must be a finite number > 0.',label);
          end
     end

     function x = requireFiniteNonNegative(x,label)
          if isempty(x) || ~isfinite(x) || x < 0
               error('%s must be a finite number >= 0.',label);
          end
     end

     function n = requirePositiveInteger(x,label)
          if isempty(x) || ~isfinite(x) || x <= 0
               error('%s must be > 0.',label);
          end
          n = floor(x + 0.5);
          if n <= 0
               error('%s must be a positive integer.',label);
          end
     end

     function u = clampU8(v)
          vv = floor(double(v));
          vv = max(0, min(255, vv));
          u = uint8(vv);
     end

     function s = toHex8(u8)
          s = sprintf('0x%02X', uint8(u8));
     end

     function clearRxVerifyIndicators()
          % Remove "verified" green state (verification must be re-done after any input change)
          try
               lblRxStart_u8.BackgroundColor  = [1 1 1];
          catch
          end
          try
               lblRxStart_hex.BackgroundColor = [1 1 1];
          catch
          end
     end

     function setRxVerifyOk()
          try
               lblRxStart_u8.BackgroundColor  = okGreenBg;
          catch
          end
          try
               lblRxStart_hex.BackgroundColor = okGreenBg;
          catch
          end
     end

     % -----------------------------
     % Highlight utilities (persistent green)
     % -----------------------------
     function clearAllHighlights()
          for ii = 1:numel(highlightControls)
               try
                    highlightControls{ii}.BackgroundColor = [1 1 1];
               catch
               end
          end
     end

     function markTouched(ctrl)
          try
               ctrl.BackgroundColor = okGreenBg;
          catch
          end
     end
end
