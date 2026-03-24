%% 
function SmartSwitch_R63()
% =========================================================================
% SmartSwitch_R62 - Main Application (BASELINE)
% =========================================================================
% Revision History:
%   R60: Base revision (working baseline)
%   R62: BASELINE. LOCAL after TestLink/Download; timebase->CLK DIVISOR (0x20);
%        Convert writes 0x20,0x23,0x24; UART lookup rd then fig; Burst Frame = N x Timebase;
%        0-255 check on RX ON/OFF. Future work: R63.
% =========================================================================
% -------------------------------------------------------------------------
% TG5011A LAN Interface preferences (persistent across sessions)
% -------------------------------------------------------------------------
if ~ispref('SmartSwitch','TG5011A_IP')
     setpref('SmartSwitch','TG5011A_IP','192.168.0.100'); % default placeholder
end


if ~ispref('SmartSwitch','TG5011A_PORT')
     setpref('SmartSwitch','TG5011A_PORT',9221);
end

% ------------------------------------------------------------------------

% ------------------------------------------------------------
% SmartSwitch (R60) - Reference layout. Main Dashboard (Home) UI.
% R60: saved as reference; Programming pane widest; Open Smartswitch at bottom.
%
% This revision fixes the COM-port caching issue in the Link/Alive polling
% by looking up the live dropdown controls by Tag on each poll.
%
% This revision also fixes a timer cleanup bug: the COM enumeration timer
% was not being stopped/deleted on close, leaving background timers alive.
%
% Changes:
%  - Top-right buttons REMOVED (as requested).
%  - Launch near-maximised BUT resizable:
%       * Uses an INSET of 4 px (not 0/1) to avoid Windows treating the
%         window as maximised-by-size.
%       * Forces WindowState='normal' AFTER positioning.
%       * Applies Position twice with a drawnow between (helps on some
%         MATLAB/Windows/DPI combinations).
%
% Notes:
%  - Close via the window [X] control.
%  - No Java/AWT calls (fast startup).
%  - MATLAB formatting: no "%%" section dividers.
% ------------------------------------------------------------

     % Defensive cleanup: release any lingering MATLAB serial objects.
     % This prevents COM port lock issues after an unclean exit.
     try
          delete(serialportfind);
     catch
     end

     try
          SS_DeleteOrphanSmartSwitchTimers();
     catch
     end


     S = struct();
     
S.TG_OutputIsOn = false; % TG5011A output toggle state (false=OFF, true=ON)
S.Fig = [];
     S.UI  = struct();

     CreateFigure(S);

end

function CreateFigure(S)
     % Calculate 75% of screen size for initial window
     if ispc()
          ss = get(groot, 'ScreenSize'); % typically excludes taskbar on Windows
          screenW = ss(3);
          screenH = ss(4);
          screenX = ss(1);
          screenY = ss(2);
     else
          mp = get(groot, 'MonitorPositions');
          if isempty(mp)
               screenW = 1200;
               screenH = 800;
               screenX = 100;
               screenY = 100;
          else
               mon = mp(1, :);
               screenX = mon(1);
               screenY = mon(2);
               screenW = mon(3);
               screenH = mon(4);
          end
     end

     % Calculate 75% of screen dimensions
     figW = round(screenW * 0.75);
     figH = round(screenH * 0.75);
     
     % Minimum size: panes scale proportionally when smaller (see BuildCardsRow).
     minWidth  = 1000;
     minHeight = 620;
     if figW < minWidth,  figW = minWidth;  end
     if figH < minHeight, figH = minHeight; end
     
     % Center the window on screen (ensuring it doesn't go off-screen)
     figX = max(screenX, screenX + round((screenW - figW) / 2));
     figY = max(screenY, screenY + round((screenH - figH) / 2));

     S.Fig = uifigure( ...
          'Name', 'SmartSwitch', ...
          'Position', [figX figY figW figH], ...
          'Resize', 'on', ...
          'CloseRequestFcn', @(src,evt)SS_OnClose(src), ...
          'WindowState', 'normal');
     
     % Force layout refresh to ensure all fields are properly sized
     drawnow;

     root = uigridlayout(S.Fig);
     root.RowHeight     = {60, '1x'};
     root.ColumnWidth   = {'1x'};
     root.Padding       = [10 10 10 10];
     root.RowSpacing    = 10;
     root.ColumnSpacing = 10;

     BuildStatusBarLeftOnly(root, S.Fig);
     BuildCardsRow(root, S.Fig);

     % Comms poller (Connect button color: green when linked, red when not)
     SS_CommsInit(S.Fig);

     drawnow;  % force layout so all three panes are fully visible at startup
end

function BuildStatusBarLeftOnly(root, fig)
     bar = uigridlayout(root);
     bar.Layout.Row = 1;
     bar.Layout.Column = 1;

     bar.RowHeight     = {'1x'};
     bar.ColumnWidth   = {'1x'};   % left only
     bar.Padding       = [8 8 8 8];
     bar.RowSpacing    = 8;
     bar.ColumnSpacing = 12;

     left = uigridlayout(bar);
     left.Layout.Row = 1;
     left.Layout.Column = 1;

     left.RowHeight = {'1x'};
     left.ColumnWidth = {70, 120, 36, 55, 90, 100, 50, 150};
     left.Padding = [0 0 0 0];
     left.ColumnSpacing = 8;

     uilabel(left, 'Text', 'COM Port:', 'HorizontalAlignment', 'right');
     ddPort = uidropdown(left, 'Items', GetComPortList(), 'Value', GetDefaultComPort());
     ddPort.Tag = 'ComPortDropdown';
     btnRefreshCom = uibutton(left, 'Text', '↻', 'Tooltip', 'Refresh COM list (FTDI hot-plug). Runs once on click; avoids timer Run/Pause issue.');
     btnRefreshCom.ButtonPushedFcn = @(~,~) SS_OnRefreshComPortList(fig);

     uilabel(left, 'Text', 'Baud:', 'HorizontalAlignment', 'right');
     ddBaud = uidropdown(left, 'Items', {'9600','115200'}, 'Value', '9600');
     ddBaud.Tag = 'BaudDropdown';

     btnUartConnect = uibutton(left, 'Text', 'Connect', 'ButtonPushedFcn', @(src,~) SS_OnUartConnectDisconnect(fig, src));
     btnUartConnect.BackgroundColor = [0.85 0.20 0.20];

     uilabel(left, 'Text', 'Mode:', 'HorizontalAlignment', 'right');
     btnMode = uibutton(left, 'Text', 'Transmit', 'ButtonPushedFcn', @(src,~) SS_OnModeButtonPushed(fig, src));
     btnMode.Tag = 'ModeButton';
     btnMode.Tooltip = 'Click to toggle: Transmit (0) / Transmit & Receive (1).';
     btnMode.BackgroundColor = [1.0 0.75 0.80];  % Pink for mode 0

     % Persist handles for comms polling and Connect callback.
     if ~isstruct(fig.UserData)
          fig.UserData = struct();
     end
     if ~isfield(fig.UserData, 'UI') || ~isstruct(fig.UserData.UI)
          fig.UserData.UI = struct();
     end
     fig.UserData.UI.ComPortDropdown = ddPort;
     fig.UserData.UI.BaudDropdown    = ddBaud;
     fig.UserData.UI.BtnUartConnect  = btnUartConnect;
     fig.UserData.UI.ModeButton      = btnMode;
     fig.UserData.Mode               = '0';

     ddPort.ValueChangedFcn = @(src,evt)SS_OnPortChanged(fig, src);
     ddBaud.ValueChangedFcn = @(src,evt)SS_OnBaudChanged(fig, src);

end

function BuildCardsRow(root, fig)
     cards = uigridlayout(root);
     cards.Layout.Row = 2;
     cards.Layout.Column = 1;

     cards.RowHeight = {'1x'};
     % Six columns; Physics, SmartSwitch, TG5011A each 1x (equal width).
     %   [1] Physics (1x)
     %   [2] 30px spacer
     %   [3] Translate button (100)
     %   [4] SmartSwitch (1x)
     %   [5] 10px gap
     %   [6] TG5011A (1x)
     cards.ColumnWidth = {'1x', 30, 100, '1x', 10, '1x'};
     cards.Padding = [0 0 0 0];
     cards.ColumnSpacing = 10;

     BuildPhysicsCard(cards, fig);
     BuildTranslateButton(cards, fig);
     BuildProgrammingCard(cards, fig);
     BuildSigGenCard(cards);

end

function BuildTranslateButton(parent, fig)
     host = uigridlayout(parent);
     host.Layout.Row = 1;
     host.Layout.Column = 3;

     host.RowHeight = {'1x', 44, '1x'};
     host.ColumnWidth = {'1x'};
     host.Padding = [0 25 0 0];  % Moved left by 15 pixels (10 -> 25)

     btn = uibutton(host, 'push', 'Text', 'Convert ➜');
     btn.Layout.Row = 2;
     btn.Layout.Column = 1;
     btn.FontSize = 12;
     btn.FontWeight = 'bold';
     btn.BackgroundColor = [0.2 0.6 0.9];  % Attractive blue
     btn.FontColor = [1 1 1];  % White text
     btn.Tooltip = 'Translate Physics values into SmartSwitch integer register values.';
     btn.ButtonPushedFcn = @(~,~)OnTranslatePhysicsToRegisters(fig);

end

function OnTranslatePhysicsToRegisters(fig)
     % Convert button: Timebase -> CLK DIVISOR (0x20); Receive Switch ON/OFF -> 0x23, 0x24
     
     try
          % Check if Register Details window is open (optional - only update if open)
          rd = [];
          tbl = [];
          if isstruct(fig.UserData) && isfield(fig.UserData, 'RegisterDetailsFig') && ...
                    ~isempty(fig.UserData.RegisterDetailsFig) && isvalid(fig.UserData.RegisterDetailsFig)
               rd = fig.UserData.RegisterDetailsFig;
               if isfield(rd.UserData, 'Table') && ~isempty(rd.UserData.Table) && isvalid(rd.UserData.Table)
                    tbl = rd.UserData.Table;
               end
          end
          
          % ===== Timebase -> Register 0x20 (CLK DIVISOR) =====
          % Use ONLY the Physics pane timebase label (exact string match).
          % Map: "0.5"->0x06, "1.0"->0x0C, "2.0"->0x18, "5.0"->0x3C, "10.0"->0x78
          timebaseStr = '';
          card = [];
          if isstruct(fig.UserData) && isfield(fig.UserData, 'PhysicsCard') && ~isempty(fig.UserData.PhysicsCard) && isvalid(fig.UserData.PhysicsCard)
               card = fig.UserData.PhysicsCard;
          end
          if ~isempty(card)
               lb = findobj(card, 'Type', 'uilabel', 'Tag', 'phys_timebase_val');
          else
               lb = findobj(fig, 'Type', 'uilabel', 'Tag', 'phys_timebase_val');
          end
          if ~isempty(lb) && isvalid(lb(1))
               timebaseStr = strtrim(char(lb(1).Text));
          end
          switch timebaseStr
               case '0.5'
                    clkdivHex = uint8(hex2dec('06'));
               case {'1', '1.0'}
                    clkdivHex = uint8(hex2dec('0C'));
               case {'2', '2.0'}
                    clkdivHex = uint8(hex2dec('18'));
               case {'5', '5.0'}
                    clkdivHex = uint8(hex2dec('3C'));
               case {'10', '10.0'}
                    clkdivHex = uint8(hex2dec('78'));
               otherwise
                    clkdivHex = uint8(hex2dec('0C'));  % default 1 us
          end
          clkdivHexStr = sprintf('0x%02X', clkdivHex);
          targetAddrClk = '0x20';
          foundRowClk = [];
          if ~isempty(tbl)
               for row = 1:size(tbl.Data, 1)
                    addrInTable = char(tbl.Data{row, 2});
                    nameInTable = char(tbl.Data{row, 1});
                    if strcmpi(addrInTable, targetAddrClk) && contains(upper(nameInTable), 'CLK')
                         foundRowClk = row;
                         break;
                    end
               end
               if ~isempty(foundRowClk)
                    bitsClk = zeros(1, 8);
                    for bitIdx = 1:8
                         bitsClk(bitIdx) = bitget(clkdivHex, 9 - bitIdx);
                    end
                    for bitCol = 1:8
                         tbl.Data{foundRowClk, bitCol + 2} = sprintf('%d', bitsClk(bitCol));
                    end
                    tbl.Data{foundRowClk, 11} = clkdivHexStr;
                    tbl.Data = tbl.Data;
                    drawnow;
               end
          end
          
          % ===== Process Receive Switch ON Value -> Register 0x23 (RXD START TIME) =====
          rxOnLabel = findobj(fig, 'Tag', 'phys_rxon_val');
          if isempty(rxOnLabel) || ~isvalid(rxOnLabel)
               uialert(fig, 'Receive Switch ON Value not found. Please update Physics values first.', 'Convert Error', 'Icon', 'error');
               return;
          end
          
          rxOnStr = strtrim(rxOnLabel.Text);
          rxOnDecimal = str2double(rxOnStr);
          
          if isnan(rxOnDecimal) || rxOnDecimal < 0 || rxOnDecimal > 255
               uialert(fig, sprintf('Invalid Receive Switch ON Value: %s. Must be 0-255.', rxOnStr), 'Convert Error', 'Icon', 'error');
               return;
          end
          
          rxOnHex = uint8(rxOnDecimal);
          rxOnHexStr = sprintf('0x%02X', rxOnHex);
          
          % Find and update register 0x23 (RXD START TIME) if Register Details window is open
          targetAddrOn = '0x23';
          foundRowOn = [];
          if ~isempty(tbl)
               for row = 1:size(tbl.Data, 1)
                    addrInTable = char(tbl.Data{row, 2});
                    if strcmpi(addrInTable, targetAddrOn)
                         foundRowOn = row;
                         break;
                    end
               end
               
               if ~isempty(foundRowOn)
                    % Convert hex value to bits and update
                    bitsOn = zeros(1, 8);
                    for bitIdx = 1:8
                         bitsOn(bitIdx) = bitget(rxOnHex, 9-bitIdx);
                    end
                    for bitCol = 1:8
                         tbl.Data{foundRowOn, bitCol + 2} = sprintf('%d', bitsOn(bitCol));  % Format as string for left alignment
                    end
                    tbl.Data{foundRowOn, 11} = rxOnHexStr;
                    % Force table refresh by reassigning Data property and forcing redraw
                    tbl.Data = tbl.Data;
                    drawnow;
               end
          end
          
          % Update SmartSwitch panel with RXD START TIME value
          if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblRxdStart') && isvalid(fig.UserData.UI.LblRxdStart)
               fig.UserData.UI.LblRxdStart.Text = rxOnHexStr;
          end
          
          % ===== Process Receive Switch OFF Value -> Register 0x24 (RXD STOP TIME) =====
          rxOffLabel = findobj(fig, 'Tag', 'phys_rxoff_val');
          if isempty(rxOffLabel) || ~isvalid(rxOffLabel)
               uialert(fig, 'Receive Switch OFF Value not found. Please update Physics values first.', 'Convert Error', 'Icon', 'error');
               return;
          end
          
          rxOffStr = strtrim(rxOffLabel.Text);
          rxOffDecimal = str2double(rxOffStr);
          
          if isnan(rxOffDecimal) || rxOffDecimal < 0 || rxOffDecimal > 255
               uialert(fig, sprintf('Invalid Receive Switch OFF Value: %s. Must be 0-255.', rxOffStr), 'Convert Error', 'Icon', 'error');
               return;
          end
          
          rxOffHex = uint8(rxOffDecimal);
          rxOffHexStr = sprintf('0x%02X', rxOffHex);
          
          % Find and update register 0x24 (RXD STOP TIME) if Register Details window is open
          targetAddrOff = '0x24';
          foundRowOff = [];
          if ~isempty(tbl)
               for row = 1:size(tbl.Data, 1)
                    addrInTable = char(tbl.Data{row, 2});
                    if strcmpi(addrInTable, targetAddrOff)
                         foundRowOff = row;
                         break;
                    end
               end
               
               if ~isempty(foundRowOff)
                    % Convert hex value to bits and update
                    bitsOff = zeros(1, 8);
                    for bitIdx = 1:8
                         bitsOff(bitIdx) = bitget(rxOffHex, 9-bitIdx);
                    end
                    for bitCol = 1:8
                         tbl.Data{foundRowOff, bitCol + 2} = sprintf('%d', bitsOff(bitCol));  % Format as string for left alignment
                    end
                    tbl.Data{foundRowOff, 11} = rxOffHexStr;
                    % Force table refresh by reassigning Data property and forcing redraw
                    tbl.Data = tbl.Data;
                    drawnow;
               end
          end
          
          % Update SmartSwitch panel with RXD STOP TIME value
          if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblRxdStop') && isvalid(fig.UserData.UI.LblRxdStop)
               fig.UserData.UI.LblRxdStop.Text = rxOffHexStr;
          end
          
          % Update stored data if Register Details window is open
          if ~isempty(rd) && isstruct(rd.UserData)
               rd.UserData.RegisterData = tbl.Data;
          end
          
          % --- Methodical hardware write: 0x20 (CLK), 0x23 (RXD START), 0x24 (RXD STOP) ---
          % Use same UART lookup as READ/WRITE Selected: rd first, then fig. Sync rd from fig first.
          sp = [];
          if ~isempty(rd) && isvalid(rd) && isstruct(rd.UserData) && isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial')
               rd.UserData.UartSerial = fig.UserData.UartSerial;
          end
          if ~isempty(rd) && isvalid(rd) && isstruct(rd.UserData) && isfield(rd.UserData, 'UartSerial')
               sp = rd.UserData.UartSerial;
          end
          if isempty(sp) && isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial')
               sp = fig.UserData.UartSerial;
          end
          if isempty(sp)
               uialert(fig, 'Convert updated the table but no hardware write: not connected. Connect first, then Convert.', 'Convert', 'Icon', 'warning');
          else
               try
                    write_reg(sp, hex2dec('20'), parse_hexbyte(clkdivHexStr));
                    write_reg(sp, hex2dec('23'), parse_hexbyte(rxOnHexStr));
                    write_reg(sp, hex2dec('24'), parse_hexbyte(rxOffHexStr));
                    uialert(fig, 'Convert done. Wrote 0x20 (CLK), 0x23 (RXD START), 0x24 (RXD STOP) to hardware.', 'Convert', 'Icon', 'info');
               catch WE
                    uialert(fig, sprintf('Convert updated the table but hardware write failed:\n%s', WE.message), 'Convert', 'Icon', 'error');
               end
          end
          
          % Read SMART SWITCH BOARD ID and update SmartSwitch panel
          % Try multiple methods: hardware read, debug line parse, or Register Details table
          boardIdHexStr = [];
          
          % Method 1: Try reading from hardware if UART is connected
          if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial') && ...
                    ~isempty(fig.UserData.UartSerial) && isvalid(fig.UserData.UartSerial)
               sp = fig.UserData.UartSerial;
               if isa(sp, 'serialport')
                    try
                         [ok, ~, ~, data, ~, ~] = SS_UartRead8(sp, uint8(0));  % Read register 0x00
                         if ok && data ~= uint8(255)  % Valid data (not 0xFF which indicates no device)
                              boardIdHexStr = sprintf('0x%02X', data);
                         end
                    catch
                         % If hardware read fails, try other methods
                    end
               end
          end
          
          % Method 2: Try extracting from debug line (if hardware read failed)
          if isempty(boardIdHexStr)
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'Lbl8wrDebug')
                         debugText = fig.UserData.UI.Lbl8wrDebug.Text;
                         % Parse "8WR@0x00: ... data=0x##" format
                         match = regexp(debugText, 'data=0x([0-9A-Fa-f]{2})', 'tokens');
                         if ~isempty(match) && ~isempty(match{1})
                              hexVal = match{1}{1};
                              val = hex2dec(hexVal);
                              if val ~= 255  % Valid data
                                   boardIdHexStr = sprintf('0x%02X', val);
                              end
                         end
                    end
               catch
                    % If debug line parse fails, try table
               end
          end
          
          % Method 3: Try reading from Register Details table
          if isempty(boardIdHexStr) && ~isempty(tbl)
               targetAddrBoardId = '0x00';
               foundRowBoardId = [];
               for row = 1:size(tbl.Data, 1)
                    addrInTable = char(tbl.Data{row, 2});
                    if strcmpi(addrInTable, targetAddrBoardId)  % Column 2 is Address
                         foundRowBoardId = row;
                         break;
                    end
               end
               
               if ~isempty(foundRowBoardId)
                    % Get the hex value from column 11
                    boardIdVal = tbl.Data{foundRowBoardId, 11};
                    if ischar(boardIdVal) || isstring(boardIdVal)
                         boardIdHexStr = char(strtrim(boardIdVal));
                         if strcmpi(boardIdHexStr, '—') || strcmpi(boardIdHexStr, '-') || isempty(boardIdHexStr)
                              boardIdHexStr = [];  % Don't use empty or placeholder values
                         end
                    end
               end
          end
          
          % Update the SmartSwitch panel label
          if ~isempty(boardIdHexStr)
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblBoardId')
                         lbl = fig.UserData.UI.LblBoardId;
                         if isvalid(lbl)
                              lbl.Text = boardIdHexStr;
                              drawnow;  % Force UI update
                         end
                    end
               catch
                    % Silently fail if label update doesn't work
               end
          end
          
     catch ME
          uialert(fig, sprintf('Error during conversion: %s', ME.message), 'Convert Error', 'Icon', 'error');
     end

end


function BuildPhysicsCard(parent, fig)
     card = uipanel(parent, 'Title', '');
     card.BackgroundColor = [0.92 0.96 1.00];  % pastel blue
     card.Layout.Row = 1;
     card.Layout.Column = 1;
     fig.UserData.PhysicsCard = card;

     gl = uigridlayout(card);
     gl.BackgroundColor = card.BackgroundColor;
     gl.RowHeight = {34, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, '1x', 22, 36};
     gl.ColumnWidth = {205, '1x'};
     gl.Padding = [10 10 10 10];
     gl.RowSpacing = 6;
     gl.ColumnSpacing = 10;

     hdr = uilabel(gl, 'Text', 'Physics', 'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
     hdr.Layout.Row = 1;
     hdr.Layout.Column = [1 2];

     physAddTaggedRow(gl, 2, 'Medium:',          'phys_medium_val');
     physAddTaggedRow(gl, 3, 'Fundamental Frequency:',         'phys_f0_val');
          physAddTaggedRow(gl, 4, 'Diameter (mm):',              'phys_diam_val');
     physAddTaggedRow(gl, 5, 'Rayleigh Distance (mm):',     'phys_rayleigh_val');
     physAddTaggedRow(gl, 6, 'Time to Rayleigh Distance (us):', 'phys_ttr_val');
     physAddTaggedRow(gl, 7, 'Round-trip (us):',            'phys_rtt_val');
     physAddTaggedRow(gl, 8, 'Burst-time Round-trip (us):', 'phys_btrtt_val');
     physAddTaggedRow(gl, 9, 'Timebase (µs):', 'phys_timebase_val');
     physAddTaggedRow(gl, 10, 'Receive Switch ON Value...', 'phys_rxon_val');
     physAddTaggedRow(gl, 11, 'Receive Switch OFF Value...', 'phys_rxoff_val');
     lblUpdated = uilabel(gl, 'Text', 'Last updated: —', 'HorizontalAlignment', 'left', 'Tag', 'phys_lastupdate_val');
     lblUpdated.Layout.Row = 13;
     lblUpdated.Layout.Column = [1 2];

     btn = uibutton(gl, 'Text', 'Open Physics...', 'ButtonPushedFcn', @(src,evt)openPhysicsDialog(fig));
     btn.Layout.Row = 14;
     btn.Layout.Column = [1 2];
end

function physAddTaggedRow(gl, row, labelText, tagName)
     lab = uilabel(gl, 'Text', labelText, 'HorizontalAlignment', 'left', 'Tag', [tagName '_lab']);
     lab.Layout.Row = row;
     lab.Layout.Column = 1;
     val = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left', 'Tag', tagName);
     val.Layout.Row = row;
     val.Layout.Column = 2;
end



function addTaggedRow(gl, row, labelText, tagName)
     physAddTaggedRow(gl, row, labelText, tagName);
end
function BuildProgrammingCard(parent, fig)
     % SmartSwitch pane: Open Smartswitch (opens submenu) and status. Connect is on the main dashboard.
     % fig.UserData.UartSerial is set by SS_OnUartConnectDisconnect (dashboard Connect). LblUartStatus updated from there.
     card = uipanel(parent, 'Title', '');
     card.BackgroundColor = [0.93 0.98 0.94];
     card.Layout.Row = 1;
     card.Layout.Column = 4;

     gl = uigridlayout(card);
     gl.BackgroundColor = card.BackgroundColor;
     % R60: flexible row pushes Open Smartswitch to bottom of pane.
     gl.RowHeight = {34, 28, 28, 28, 28, 28, '1x', 36};
     gl.ColumnWidth = {200, '1x'};
     gl.Padding = [10 10 10 10];
     gl.RowSpacing = 6;
     gl.ColumnSpacing = 8;

     hdr = uilabel(gl, 'Text', 'SmartSwitch', 'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
     hdr.Layout.Row = 1;
     hdr.Layout.Column = [1 2];

     lblStatus = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left');
     lblStatus.Layout.Row = 2;
     lblStatus.Layout.Column = [1 2];

     lbl8wrDebug = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left', 'FontSize', 10);
     lbl8wrDebug.Layout.Row = 3;
     lbl8wrDebug.Layout.Column = [1 2];
     lbl8wrDebug.Tooltip = 'Last 8WR exchange on Connect (tx sent, rx received, ok, data at 0x00)';

     lblBoardId = uilabel(gl, 'Text', 'SMART SWITCH BOARD ID:', 'HorizontalAlignment', 'left', 'FontSize', 11);
     lblBoardId.Layout.Row = 4;
     lblBoardId.Layout.Column = 1;
     lblBoardIdVal = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left', 'FontSize', 11);
     lblBoardIdVal.Layout.Row = 4;
     lblBoardIdVal.Layout.Column = 2;

     lblRxdStart = uilabel(gl, 'Text', 'RXD START TIME:', 'HorizontalAlignment', 'left', 'FontSize', 11);
     lblRxdStart.Layout.Row = 5;
     lblRxdStart.Layout.Column = 1;
     lblRxdStartVal = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left', 'FontSize', 11);
     lblRxdStartVal.Layout.Row = 5;
     lblRxdStartVal.Layout.Column = 2;

     lblRxdStop = uilabel(gl, 'Text', 'RXD STOP TIME:', 'HorizontalAlignment', 'left', 'FontSize', 11);
     lblRxdStop.Layout.Row = 6;
     lblRxdStop.Layout.Column = 1;
     lblRxdStopVal = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left', 'FontSize', 11);
     lblRxdStopVal.Layout.Row = 6;
     lblRxdStopVal.Layout.Column = 2;

     btnRegisterDetails = uibutton(gl, 'Text', 'Open Smartswitch...', 'ButtonPushedFcn', @(~,~) OpenRegisterDetails(fig));
     btnRegisterDetails.Layout.Row = 8;
     btnRegisterDetails.Layout.Column = [1 2];

     if ~isstruct(fig.UserData), fig.UserData = struct(); end
     if ~isfield(fig.UserData, 'UI') || ~isstruct(fig.UserData.UI), fig.UserData.UI = struct(); end
     fig.UserData.UI.LblUartStatus = lblStatus;
     fig.UserData.UI.Lbl8wrDebug   = lbl8wrDebug;
     fig.UserData.UI.LblBoardId    = lblBoardIdVal;
     fig.UserData.UI.LblRxdStart   = lblRxdStartVal;
     fig.UserData.UI.LblRxdStop    = lblRxdStopVal;
end

function OpenRegisterDetails(fig)
     % Register Details submenu: Interactive table with Register Name, Address, Bit values (B7-B0), Hex Value.
     % Uses fig.UserData.UartSerial (set by main pane Connect) for READ/WRITE.
     try
          if isempty(fig) || ~isvalid(fig), return; end
          if isstruct(fig.UserData) && isfield(fig.UserData, 'RegisterDetailsFig') && ~isempty(fig.UserData.RegisterDetailsFig) && isvalid(fig.UserData.RegisterDetailsFig)
               rd = fig.UserData.RegisterDetailsFig;
               try
                    if isstruct(rd.UserData) && isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial')
                         rd.UserData.UartSerial = fig.UserData.UartSerial;
                    end
               catch
               end
               figure(rd);
               return;
          end

          rd = uifigure('Name', 'Register Details', 'Position', [100 100 900 720]);
          rd.UserData = struct('ParentFig', fig, 'UartSerial', []);
          try
               if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial')
                    rd.UserData.UartSerial = fig.UserData.UartSerial;
               end
          catch
          end
          if ~isstruct(fig.UserData), fig.UserData = struct(); end
          fig.UserData.RegisterDetailsFig = rd;
          rd.CloseRequestFcn = @(src,~) closeRegDetails(src, fig);

          gl = uigridlayout(rd);
          gl.RowHeight = {150, '1x', 30};  % Log area 5x deeper (30->150), table moves down
          gl.ColumnWidth = {'1x', 100, 100};
          gl.Padding = [10 10 10 10];
          gl.RowSpacing = 10;
          gl.ColumnSpacing = 10;

          % Load register data from spreadsheet
          [registerData, actionFlags] = loadRegisterData();
          
          % Determine editability based on ACTION column (R/W = editable, R/O = read-only)
          % Columns: Register Name, Address, B7, B6, B5, B4, B3, B2, B1, B0, Hex Value
          baseEditable = [false, false, true, true, true, true, true, true, true, true, true];
          columnEditable = baseEditable;
          % Bit columns (3-10) and Hex Value (11) should be editable only for R/W registers
          % This will be handled in the CellEditCallback
          
          % Create table with columns: Register Name, Address, B7, B6, B5, B4, B3, B2, B1, B0, Hex Value
          % Column widths: Register Name (200), Address (80), B7-B0 (31 each, 25% larger), Hex Value (80)
          % Bit columns (B7-B0) are 'char' format for left alignment
          tbl = uitable(gl, 'Data', registerData, ...
               'ColumnName', {'Register Name', 'Address', 'B7', 'B6', 'B5', 'B4', 'B3', 'B2', 'B1', 'B0', 'Hex Value'}, ...
               'ColumnEditable', columnEditable, ...
               'ColumnFormat', {'char', 'char', 'char', 'char', 'char', 'char', 'char', 'char', 'char', 'char', 'char'}, ...
               'ColumnWidth', {200, 80, 31, 31, 31, 31, 31, 31, 31, 31, 80}, ...
               'CellEditCallback', @onCellEdit, ...
               'CellSelectionCallback', @onCellSelection);
          tbl.Layout.Row = 2;
          tbl.Layout.Column = [1 3];
          rd.UserData.Table = tbl;
          rd.UserData.RegisterData = registerData;
          rd.UserData.ActionFlags = actionFlags;  % Store R/O, R/W, W/O flags
          rd.UserData.SelectedRows = [];  % Track selected rows

          % Buttons row
          btnRead = uibutton(gl, 'Text', 'READ Selected', 'ButtonPushedFcn', @onReadSelected);
          btnRead.Layout.Row = 3;
          btnRead.Layout.Column = 1;
          
          btnWrite = uibutton(gl, 'Text', 'WRITE Selected', 'ButtonPushedFcn', @onWriteSelected);
          btnWrite.Layout.Row = 3;
          btnWrite.Layout.Column = 2;
          
          btnWriteAll = uibutton(gl, 'Text', 'WRITE All', 'ButtonPushedFcn', @onWriteAll);
          btnWriteAll.Layout.Row = 3;
          btnWriteAll.Layout.Column = 3;
          rd.UserData.BtnWriteAll = btnWriteAll;

          txtLog = uitextarea(gl, 'Value', strings(0,1), 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 9);
          txtLog.Layout.Row = 1;
          txtLog.Layout.Column = [1 3];

     catch ME
          errMsg = sprintf('Error opening Register Details: %s\nLocation: %s\nLine: %d', ...
               ME.message, ME.stack(1).name, ME.stack(1).line);
          errordlg(errMsg);
     end

     function closeRegDetails(src, f)
          try, if isstruct(f.UserData) && isfield(f.UserData, 'RegisterDetailsFig'), f.UserData.RegisterDetailsFig = []; end; catch; end
          delete(src);
     end

     function log(msg)
          txtLog.Value = [txtLog.Value; string(msg)];
          drawnow;
     end

     function [data, actionFlags] = loadRegisterData()
          % Load register data from spreadsheet structure
          % Columns: Register Name, Address, Value (hex), Action (R/O, R/W, W/O), Visible (Y/N)
          % Only include rows where Visible = 'Y'
          % Returns: data (cell array for table), actionFlags (cell array of action strings)
          
          % Register data from spreadsheet (filtered to Visible='Y' only)
          rawData = {
               'SMART SWITCH BOARD ID', '0X00', '0X01', 'R/O', 'Y';
               'FPGA REVISION', '0X01', '0X00', 'R/O', 'Y';
               'PC - SS CONTROL', '0X02', '0X0C', 'R/W', 'Y';
               'PC - SS STATUS', '0X03', '0X00', 'R/O', 'Y';
               'CLK DIVISOR', '0X20', '0X00', 'R/W', 'Y';
               'PZT CLAMP START TIME', '0X21', '0X00', 'R/W', 'Y';
               'PZT CLAMP STOP TIME', '0X22', '0X00', 'R/W', 'Y';
               'RXD START TIME', '0X23', '0X00', 'R/W', 'Y';
               'RXD STOP TIME', '0X24', '0X00', 'R/W', 'Y';
               'SS - BB CONTROL', '0X30', '0X00', 'R/W', 'Y';
               'TXD', '0X38', '0X00', 'R/W', 'Y';
               'RXD', '0X39', '0X00', 'R/O', 'Y';
          };
          
          % Filter to only visible registers and convert to table format
          data = {};
          actionFlags = {};
          for i = 1:size(rawData, 1)
               if strcmpi(rawData{i, 5}, 'Y')  % Only include visible registers
                    regName = rawData{i, 1};
                    addrStr = upper(rawData{i, 2});  % Keep as 0X00 format
                    hexValStr = upper(rawData{i, 3});  % Keep as 0X01 format
                    action = rawData{i, 4};
                    
                    % Convert hex value to bits
                    hexValStrClean = hexValStr;
                    if length(hexValStrClean) > 2 && (strcmpi(hexValStrClean(1:2), '0X') || strcmpi(hexValStrClean(1:2), '0x'))
                         hexValStrClean = hexValStrClean(3:end);
                    end
                    hexVal = hex2dec(hexValStrClean);
                    bits = zeros(1, 8);
                    for bitIdx = 1:8
                         bits(bitIdx) = bitget(hexVal, 9-bitIdx); % B7 (MSB) to B0 (LSB)
                    end
                    
                    % Format address as lowercase 0x for consistency
                    addrFormatted = lower(addrStr);
                    
                    % Format bits as strings for left alignment
                    bitStrings = cell(1, 8);
                    for bitIdx = 1:8
                         bitStrings{bitIdx} = sprintf('%d', bits(bitIdx));
                    end
                    
                    % Build row: Register Name, Address, B7, B6, B5, B4, B3, B2, B1, B0, Hex Value
                    data(end+1, :) = {regName, addrFormatted, bitStrings{1}, bitStrings{2}, bitStrings{3}, bitStrings{4}, bitStrings{5}, bitStrings{6}, bitStrings{7}, bitStrings{8}, lower(hexValStr)};
                    actionFlags{end+1} = action;
               end
          end
     end

     function hexStr = bitsToHex(bits)
          % Convert bit array [B7 B6 B5 B4 B3 B2 B1 B0] to hex string
          value = 0;
          for i = 1:8
               if bits(i) ~= 0
                    value = value + bitshift(1, 8-i);
               end
          end
          hexStr = sprintf('0x%02X', value);
     end

     function onCellSelection(src, event)
          % Track selected rows when user clicks on table
          if ~isempty(event.Indices)
               % Get unique row indices from selection
               selectedRows = unique(event.Indices(:, 1));
               rd.UserData.SelectedRows = selectedRows;
          else
               rd.UserData.SelectedRows = [];
          end
     end

     function onCellEdit(src, event)
          % Handle edits to either bit columns (3-10) or hex value column (11)
          row = event.Indices(1);
          col = event.Indices(2);
          
          % Check if register is read-only (R/O) for any editable column
          if col >= 3 && col <= 11
               if isstruct(rd.UserData) && isfield(rd.UserData, 'ActionFlags')
                    if row <= length(rd.UserData.ActionFlags)
                         action = rd.UserData.ActionFlags{row};
                         if strcmpi(action, 'R/O')
                              % Revert change for read-only registers
                              src.Data{row, col} = event.PreviousData;
                              log(sprintf('Register "%s" is read-only (R/O). Change reverted.', src.Data{row, 1}));
                              return;
                         end
                    end
               end
          end
          
          % Handle bit column edits (columns 3-10)
          if col >= 3 && col <= 10
               % Parse new value (can be string or numeric)
               newValStr = char(event.NewData);
               newVal = str2double(newValStr);
               
               % Ensure value is 0 or 1
               if isnan(newVal) || (newVal ~= 0 && newVal ~= 1)
                    src.Data{row, col} = event.PreviousData; % Revert
                    log('Bit values must be 0 or 1. Change reverted.');
                    return;
               end
               
               % Update cell with string format for left alignment
               src.Data{row, col} = sprintf('%d', newVal);
               
               % Extract all bit values (convert strings to numbers)
               bits = zeros(1, 8);
               for bitCol = 3:10
                    bitStr = char(src.Data{row, bitCol});
                    bits(bitCol-2) = str2double(bitStr);
               end
               
               % Recalculate hex value from bits
               hexVal = bitsToHex(bits);
               src.Data{row, 11} = hexVal;
               
               % Update stored data
               rd.UserData.RegisterData = src.Data;
               
          % Handle hex value column edit (column 11)
          elseif col == 11
               % Parse the hex value - handle both string and numeric input
               newData = event.NewData;
               if isnumeric(newData)
                    % If it's a number, treat it as a decimal value (0-255)
                    if newData < 0 || newData > 255
                         src.Data{row, col} = event.PreviousData;
                         log(sprintf('Invalid value: %d. Must be 0 to 255. Change reverted.', newData));
                         return;
                    end
                    hexVal = uint8(newData);
               else
                    % If it's a string, parse as hex
                    hexStr = strtrim(char(newData));
                    try
                         hexVal = parse_hexbyte(hexStr);
                    catch ME
                         % Invalid hex value - revert
                         src.Data{row, col} = event.PreviousData;
                         log(sprintf('Invalid hex value: %s. Must be 0x00 to 0xFF (or 0-255). Change reverted.', hexStr));
                         return;
                    end
               end
               
               % Convert hex value to bits
               bits = zeros(1, 8);
               for bitIdx = 1:8
                    bits(bitIdx) = bitget(hexVal, 9-bitIdx); % B7 (MSB) to B0 (LSB)
               end
               
               % Update bit columns (assign each cell individually as strings for left alignment)
               for bitCol = 1:8
                    src.Data{row, bitCol + 2} = sprintf('%d', bits(bitCol));  % Columns 3-10 correspond to bits 1-8
               end
               
               % Format hex value consistently (lowercase 0x prefix)
               src.Data{row, 11} = sprintf('0x%02X', hexVal);
               
               % Update stored data
               rd.UserData.RegisterData = src.Data;
          end
     end

     function onReadSelected(~,~)
          try
               sp = [];
               if isstruct(rd.UserData) && isfield(rd.UserData, 'UartSerial'), sp = rd.UserData.UartSerial; end
               if isempty(sp) && isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial'), sp = fig.UserData.UartSerial; end
               if isempty(sp)
                    log('ERROR: Not connected. Connect from main pane first.'); return;
               end
               
               % Get selected rows from UserData (tracked by CellSelectionCallback)
               if isstruct(rd.UserData) && isfield(rd.UserData, 'SelectedRows')
                    selectedRows = rd.UserData.SelectedRows;
               else
                    selectedRows = [];
               end
               if isempty(selectedRows)
                    log('ERROR: No row selected. Click on a row in the table first.'); return;
               end
               
               % Disable CellEditCallback during programmatic updates so it doesn't overwrite
               % the hex column (e.g. CLK_DIVISOR) when updating bit cells
               cb = tbl.CellEditCallback;
               tbl.CellEditCallback = [];
               oc = onCleanup(@() set_cb(tbl, cb));
               
               for idx = 1:length(selectedRows)
                    row = selectedRows(idx);
                    addrStr = tbl.Data{row, 2};
                    addr = parse_hexbyte(addrStr);
                    [rx, tx] = read_reg(sp, addr);
                    log(sprintf('TX = %02X %02X %02X %02X %02X', tx));
                    log(sprintf('RX = %02X %02X %02X %02X %02X', rx));
                    [ok, msg, ~, raddr, rdata] = validate_resp(rx);
                    if ok
                         log(sprintf('READ  %s (0x%02X) -> 0x%02X  (STATUS=0x%02X)', tbl.Data{row, 1}, raddr, rdata, rx(2)));
                         % Update table with read value
                         bits = zeros(1, 8);
                         for bitIdx = 1:8
                              bits(bitIdx) = bitget(rdata, 9-bitIdx); % B7 (MSB) to B0 (LSB)
                         end
                         % Update bit columns (assign each cell individually as strings for left alignment)
                         for bitCol = 1:8
                              tbl.Data{row, bitCol + 2} = sprintf('%d', bits(bitCol));  % Columns 3-10 correspond to bits 1-8
                         end
                         tbl.Data{row, 11} = sprintf('0x%02X', rdata);
                         % Force table refresh
                         tbl.Data = tbl.Data;
                         drawnow;
                    else
                         log('ERROR: ' + string(msg));
                    end
               end
               rd.UserData.RegisterData = tbl.Data;
          catch ME, log('ERROR: ' + string(ME.message)); end
     end
     
     function set_cb(t, f)
          try, if isvalid(t), t.CellEditCallback = f; end; catch, end
     end

     function onWriteSelected(~,~)
          try
               sp = [];
               if isstruct(rd.UserData) && isfield(rd.UserData, 'UartSerial'), sp = rd.UserData.UartSerial; end
               if isempty(sp) && isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial'), sp = fig.UserData.UartSerial; end
               if isempty(sp)
                    log('ERROR: Not connected. Connect from main pane first.'); return;
               end
               
               % Get selected rows from UserData (tracked by CellSelectionCallback)
               if isstruct(rd.UserData) && isfield(rd.UserData, 'SelectedRows')
                    selectedRows = rd.UserData.SelectedRows;
               else
                    selectedRows = [];
               end
               if isempty(selectedRows)
                    log('ERROR: No row selected. Click on a row in the table first.'); return;
               end
               
               for idx = 1:length(selectedRows)
                    row = selectedRows(idx);
                    addrStr = tbl.Data{row, 2};
                    addr = parse_hexbyte(addrStr);
                    hexStr = tbl.Data{row, 11};
                    data = parse_hexbyte(hexStr);
                    rx = write_reg(sp, addr, data);
                    log(sprintf('RX = %02X %02X %02X %02X %02X', rx));
                    [ok, msg, ~, ~, rdata] = validate_resp(rx);
                    if ok
                         log(sprintf('WRITE %s (0x%02X) <- 0x%02X  (RESP=0x%02X, STATUS=0x%02X)', tbl.Data{row, 1}, addr, data, rdata, rx(2)));
                    else
                         log('ERROR: ' + string(msg));
                    end
               end
          catch ME, log('ERROR: ' + string(ME.message)); end
     end

     function onWriteAll(~,~)
          try
               sp = [];
               if isstruct(rd.UserData) && isfield(rd.UserData, 'UartSerial'), sp = rd.UserData.UartSerial; end
               if isempty(sp) && isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial'), sp = fig.UserData.UartSerial; end
               if isempty(sp)
                    log('ERROR: Not connected. Connect from main pane first.'); return;
               end
               
               numRows = size(tbl.Data, 1);
               for row = 1:numRows
                    addrStr = tbl.Data{row, 2};
                    addr = parse_hexbyte(addrStr);
                    hexStr = tbl.Data{row, 11};
                    data = parse_hexbyte(hexStr);
                    rx = write_reg(sp, addr, data);
                    [ok, msg, ~, ~, rdata] = validate_resp(rx);
                    if ok
                         log(sprintf('WRITE %s (0x%02X) <- 0x%02X  (RESP=0x%02X)', tbl.Data{row, 1}, addr, data, rdata));
                    else
                         log(sprintf('ERROR writing %s: %s', tbl.Data{row, 1}, string(msg)));
                    end
               end
          catch ME, log('ERROR: ' + string(ME.message)); end
     end
end

function b = parse_hexbyte(in)
     in = strtrim(char(in));
     inLower = lower(in);
     if length(inLower) > 2 && strcmp(inLower(1:2), '0x')
          v = hex2dec(in(3:end));
     else
          v = hex2dec(in);
     end
     if v < 0 || v > 255, error('Value out of range 0..255'); end
     b = uint8(v);
end

function Uart_cleanup_serial(fig)
     try
          if isempty(fig) || ~isvalid(fig), return; end
          if ~isstruct(fig.UserData) || ~isfield(fig.UserData, 'UartSerial'), return; end
          sp = fig.UserData.UartSerial;
          if isempty(sp) || ~isa(sp, 'serialport'), return; end
          try, flush(sp); delete(sp); catch; end
          fig.UserData.UartSerial = [];
     catch
     end
end

% ===== BEGIN SIGNAL GENERATOR PANE =====
function BuildSigGenCard(parent)
     card = uipanel(parent, 'Title', '');
     card.BackgroundColor = [1.00 0.94 0.96];  % pastel pink
     card.Layout.Row = 1;
     card.Layout.Column = 6;

     % Parent grid: box1 (params + Download button), box2 (Status), btnRow. Status 1x, box1 2x so Download stays visible.
     gl = uigridlayout(card);
     gl.BackgroundColor = card.BackgroundColor;
     gl.RowHeight = {'2x', '1x', 36};  % Status 1x (was 2x): ~17% further reduction
     gl.ColumnWidth = {'1x'};
     gl.Padding = [10 10 10 10];
     gl.RowSpacing = 10;
     gl.ColumnSpacing = 10;

     % Box 1: TG5011A (light pink), params + LAN + Download button
     box1 = uipanel(gl, 'Title', '');
     box1.BackgroundColor = [1.0 0.85 0.90];  % light pink background
     box1.BorderType = 'none';  % We'll draw custom rounded border
     box1.Layout.Row = 1;
     box1.Layout.Column = 1;

     gl_box1 = uigridlayout(box1);
     gl_box1.BackgroundColor = box1.BackgroundColor;
     gl_box1.RowHeight = {34, 22, 22, 22, 22, 10, 18, 22, 26, 36};  % row 10: Download button (replaces empty 1x)
     gl_box1.ColumnWidth = {170, 100, '1x'};  % label col, reduced-width value col (60% smaller), remaining space
     gl_box1.Padding = [10 10 10 10];
     gl_box1.RowSpacing = 6;
     gl_box1.ColumnSpacing = 10;

     hdr_box1 = uilabel(gl_box1, 'Text', 'TG5011A', 'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
     hdr_box1.Layout.Row = 1;
     hdr_box1.Layout.Column = [1 3];

     % Inherited dashboard value: must match Physics f0 exactly.
     lab_f0 = uilabel(gl_box1, 'Text', 'Fundamental Frequency:', 'HorizontalAlignment', 'left', 'Tag', 'siggen_f0_inherited_val_lab');
     lab_f0.Layout.Row = 2;
     lab_f0.Layout.Column = 1;
     val_f0 = uilabel(gl_box1, 'Text', '—', 'HorizontalAlignment', 'left', 'Tag', 'siggen_f0_inherited_val');
     val_f0.Layout.Row = 2;
     val_f0.Layout.Column = 2;

     lab_amp = uilabel(gl_box1, 'Text', 'Amplitude:', 'HorizontalAlignment', 'left');
     lab_amp.Layout.Row = 3;
     lab_amp.Layout.Column = 1;
     val_amp = uieditfield(gl_box1, 'numeric', 'Limits', [-50 50], 'Value', 1, 'Tag', 'siggen_amplitude_val');
     val_amp.Layout.Row = 3;
     val_amp.Layout.Column = 2;

     lab_offset = uilabel(gl_box1, 'Text', 'Offset:', 'HorizontalAlignment', 'left');
     lab_offset.Layout.Row = 4;
     lab_offset.Layout.Column = 1;
     val_offset = uieditfield(gl_box1, 'numeric', 'Limits', [-50 50], 'Value', 0, 'Tag', 'siggen_offset_val');
     val_offset.Layout.Row = 4;
     val_offset.Layout.Column = 2;

     lab_burst = uilabel(gl_box1, 'Text', 'Burst Cycle (N):', 'HorizontalAlignment', 'left');
     lab_burst.Layout.Row = 5;
     lab_burst.Layout.Column = 1;
     val_burst = uilabel(gl_box1, 'Text', '—', 'HorizontalAlignment', 'left', 'Tag', 'siggen_burst_mode_val');
     val_burst.Layout.Row = 5;
     val_burst.Layout.Column = 2;

     % --- LAN Interface (TG5011A) ----------------------------------------
     lab_lan_hdr = uilabel(gl_box1, 'Text', 'LAN Interface', 'FontWeight', 'bold', 'HorizontalAlignment', 'left');
     lab_lan_hdr.Layout.Row = 7;
     lab_lan_hdr.Layout.Column = [1 2];

     lab_ip = uilabel(gl_box1, 'Text', 'IP Address:', 'HorizontalAlignment', 'left');
     lab_ip.Layout.Row = 8;
     lab_ip.Layout.Column = 1;

     S.Edit_TG5011A_IP = uieditfield(gl_box1, 'text', 'Value', getpref('SmartSwitch','TG5011A_IP'));
     S.Edit_TG5011A_IP.Layout.Row = 8;
     S.Edit_TG5011A_IP.Layout.Column = 2;
     S.Edit_TG5011A_IP.ValueChangedFcn = @(src,~)setpref('SmartSwitch','TG5011A_IP', src.Value);

     lab_port = uilabel(gl_box1, 'Text', 'Port:', 'HorizontalAlignment', 'left');
     lab_port.Layout.Row = 9;
     lab_port.Layout.Column = 1;

     S.Label_TG5011A_Port = uilabel(gl_box1, 'Text', num2str(getpref('SmartSwitch','TG5011A_PORT')), 'HorizontalAlignment', 'left');
     S.Label_TG5011A_Port.Layout.Row = 9;
     S.Label_TG5011A_Port.Layout.Column = 2;

     figBtn = ancestor(parent, 'figure');
     btnConnect = uibutton(gl_box1, 'Text', 'Download Parameters to TG5011A');
     btnConnect.Layout.Row = 10;
     btnConnect.Layout.Column = [1 2];
     btnConnect.Tooltip = 'Download and configure Signal Generator parameters to the TG5011A and enable output.';
     btnConnect.ButtonPushedFcn = @(~,~)SS_TG5011A_Update(figBtn);
     if ~isfield(figBtn.UserData,'UI'), figBtn.UserData.UI = struct(); end
     figBtn.UserData.UI.BtnTGConnect = btnConnect;

     % Box 2: TG5011A Status (darker pink)
     box2 = uipanel(gl, 'Title', '');
     box2.BackgroundColor = [0.95 0.70 0.80];  % darker pink background
     box2.BorderType = 'none';  % We'll draw custom rounded border
     box2.Layout.Row = 2;
     box2.Layout.Column = 1;

     gl_box2 = uigridlayout(box2);
     gl_box2.BackgroundColor = box2.BackgroundColor;
     % Row 3: 95 for Instrument ID (Mfr, Model, Serial + Main, Remote, USB Flash Drive)
     gl_box2.RowHeight = {24, 22, 95, '1x'};
     gl_box2.ColumnWidth = {140, '1x'};
     gl_box2.Padding = [10 10 10 10];
     gl_box2.RowSpacing = 6;
     gl_box2.ColumnSpacing = 10;

     hdr_box2 = uilabel(gl_box2, 'Text', 'TG5011A Status', 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'left');
     hdr_box2.Layout.Row = 1;
     hdr_box2.Layout.Column = [1 2];

     lblTG = uilabel(gl_box2, 'Text', 'TG5011A Link:', 'HorizontalAlignment', 'left');
     lblTG.Layout.Row = 2;
     lblTG.Layout.Column = 1;

     lampTG = uilamp(gl_box2);
     lampTG.Layout.Row = 2;
     lampTG.Layout.Column = 2;
     lampTG.Color = [0.5 0.5 0.5];
     lampTG.Tag = 'LampTG5011A';

     fig2 = ancestor(parent, 'figure');
     if ~isempty(fig2) && isvalid(fig2)
          if ~isstruct(fig2.UserData)
               fig2.UserData = struct();
          end
          if ~isfield(fig2.UserData, 'UI') || ~isstruct(fig2.UserData.UI)
               fig2.UserData.UI = struct();
          end
          fig2.UserData.UI.LampTG5011A = lampTG;
     end

     lblInstrumentId = uilabel(gl_box2, 'Text', 'Instrument ID:', 'HorizontalAlignment', 'left');
     lblInstrumentId.Layout.Row = 3;
     lblInstrumentId.Layout.Column = 1;
     val_instrument_id = uilabel(gl_box2, 'Text', '—', 'HorizontalAlignment', 'left', 'Tag', 'siggen_instrument_id_val', 'WordWrap', 'on');
     val_instrument_id.Layout.Row = 3;
     val_instrument_id.Layout.Column = 2;

     btnRowSG = uigridlayout(gl, [1, 2]);
btnRowSG.Layout.Row = 3;
btnRowSG.Layout.Column = 1;
btnRowSG.ColumnWidth = {'1x','1x'};
btnRowSG.RowHeight = {32};
btnRowSG.Padding = [0 0 0 0];
btnRowSG.ColumnSpacing = 10;
btnRowSG.RowSpacing = 8;

btnOutput = uibutton(btnRowSG, 'Text', 'Output');
btnOutput.Layout.Row = 1;
btnOutput.Layout.Column = 2;
btnOutput.Tooltip = 'Toggle TG5011A output (OUTPUT ON/OFF).';
% TG5011A Output toggle state + UI handle storage
if ~isfield(figBtn.UserData,'TG')
     figBtn.UserData.TG = struct();
end
if ~isfield(figBtn.UserData,'UI')
     figBtn.UserData.UI = struct();
end
figBtn.UserData.UI.BtnTGOutput = btnOutput;

% Set initial (OFF) appearance
btnOutput.Text = 'Output OFF';
btnOutput.BackgroundColor = [0.85 0.25 0.25];
btnOutput.FontColor = [1 1 1];
btnOutput.ButtonPushedFcn = @SS_OnTGOutputPushed;

btnTest = uibutton(btnRowSG, 'Text', 'Reset & Test Link');
btnTest.Layout.Row = 1;
btnTest.Layout.Column = 1;
btnTest.Tooltip = 'Reset TG5011A, test TCP connection and update link indicator lamp.';
btnTest.ButtonPushedFcn = @(~,~)SS_TG5011A_TestLink(figBtn);
if ~isfield(figBtn.UserData,'UI'), figBtn.UserData.UI = struct(); end
figBtn.UserData.UI.BtnTGTest = btnTest;

     % Initialize default values if physics data doesn't exist
     fig = ancestor(parent, 'figure');
     if ~isempty(fig) && isvalid(fig)
          if ~isfield(fig.UserData, 'physics') || ~isstruct(fig.UserData.physics)
               % Set default physics values: Frequency = 1MHz, Burst = 3, Timebase = 1.0 us
               fig.UserData.physics = struct();
               fig.UserData.physics.f0_hz = 1e6;  % 1 MHz
               fig.UserData.physics.burst_n = 3;
               fig.UserData.physics.timebase_us = 1.0;  % Default timebase
               fig.UserData.physics.CLKDIV = timebaseToClkDiv(1.0);  % CLKDIV = 12 for 1.0 us
               fig.UserData.LastAppliedTimebaseUs = 1.0;
               % Update signal generator display fields with defaults
               [f0_num, f0_unit] = formatFrequencyParts(1e6);
               setLabelByTag(fig, 'siggen_f0_inherited_val_lab', sprintf('Fundamental Frequency %s:', f0_unit));
               setLabelByTag(fig, 'siggen_f0_inherited_val', f0_num);
               setLabelByTag(fig, 'siggen_burst_mode_val', '3');
               setLabelByTag(fig, 'phys_timebase_val', '1.0');
          end
          
          drawnow;  % Ensure UI is rendered first
          % Darker pink border for box 1 (to show against light pink background)
          drawRoundedBorder(box1, [0.90 0.60 0.75], 2, 8);  % darker pink border, 2px width, 8px radius
          % Even darker pink/red border for box 2 (to show against darker pink background)
          drawRoundedBorder(box2, [0.85 0.50 0.65], 2, 8);  % darker pink border, 2px width, 8px radius
     end


     % ---------------------------------------------------------------------
     % TG5011A OUTPUT toggle (Python-faithful: connect -> query -> toggle -> query -> close)
     % ---------------------------------------------------------------------
     function SS_OnTGOutputPushed(srcBtn, ~)
          % IMPORTANT: Do not query output state here.
          % The instrument often does not respond to OUTPUT? reliably, which causes
          % readline() timeout warnings. Instead, toggle based on last commanded
          % state and send OUTPUT ON/OFF (Python baseline).
          fig = ancestor(srcBtn, 'figure');
          if isempty(fig) || ~isvalid(fig)
               return;
          end

          % Ensure state container exists
          if ~isstruct(fig.UserData)
               fig.UserData = struct();
          end
          if ~isfield(fig.UserData, 'TG') || ~isstruct(fig.UserData.TG)
               fig.UserData.TG = struct();
          end
          if ~isfield(fig.UserData.TG, 'OutputIsOn')
               fig.UserData.TG.OutputIsOn = false;
          end

          % Toggle desired state
          desiredOn = ~logical(fig.UserData.TG.OutputIsOn);

          % Show AMBER immediately to acknowledge click (pending state)
          srcBtn.Text = 'Output...';
          srcBtn.BackgroundColor = [0.9 0.7 0.0];  % amber - pending
          srcBtn.FontColor = [0 0 0];  % black text
          drawnow('update');

          % Read connection info
          ip = '';
          try
               ip = getpref('SmartSwitch','TG5011A_IP','');
          catch
               ip = '';
          end
          port = 9221;
          try
               port = getpref('SmartSwitch','TG5011A_PORT');
          catch
               port = 9221;
          end

          if isempty(ip)
               % No IP configured -> revert to OFF (red)
               fig.UserData.TG.OutputIsOn = false;
               srcBtn.Text = 'Output OFF';
               srcBtn.BackgroundColor = [0.85 0.25 0.25];  % red
               srcBtn.FontColor = [1 1 1];
               drawnow('update');
               return;
          end

          % Send commands (no readline involved -> no timeout warning)
          try
               t = tcpclient(ip, port, 'Timeout', 2.0);
               cleanupObj = onCleanup(@()clear('t')); %#ok<NASGU>
               try
                    configureTerminator(t, "CR/LF");
                    flush(t);
               catch
               end

               if desiredOn
                    writeline(t, 'OUTPUT ON');
               else
                    writeline(t, 'OUTPUT OFF');
               end
               pause(0.1);
               writeline(t, 'LOCAL');

               % Commit commanded state and update button to final color
               fig.UserData.TG.OutputIsOn = desiredOn;
               
               % Update button to final state (green for ON, red for OFF)
               if desiredOn
                    srcBtn.Text = 'Output ON';
                    srcBtn.BackgroundColor = [0.2 0.8 0.2];  % green
                    srcBtn.FontColor = [0 0 0];  % black text
               else
                    srcBtn.Text = 'Output OFF';
                    srcBtn.BackgroundColor = [0.85 0.25 0.25];  % red
                    srcBtn.FontColor = [1 1 1];  % white text
               end
               drawnow('update');
          catch
               % If send fails, revert UI + state to previous value
               desiredOn = logical(fig.UserData.TG.OutputIsOn);
               if desiredOn
                    srcBtn.Text = 'Output ON';
                    srcBtn.BackgroundColor = [0.2 0.8 0.2];
                    srcBtn.FontColor = [0 0 0];
               else
                    srcBtn.Text = 'Output OFF';
                    srcBtn.BackgroundColor = [0.85 0.25 0.25];
                    srcBtn.FontColor = [1 1 1];
               end
               drawnow('update');
          end
     end

     function TG_Send(t, cmd)
          % Send SCPI command to TG5011A with robust line termination.
          % Prefer writeline/readline (terminator-aware) to avoid partial reads.
          try
               configureTerminator(t, "CR/LF");
          catch
          end

          try
               writeline(t, cmd);
          catch
               if ~endsWith(cmd, char(10))
                    cmd = [cmd char(10)];
               end
               write(t, uint8(cmd), "uint8");
          end

          % Small guard delay (device + LAN stack)
          pause(0.05);
     end

     function isOn = TG_QueryOutputState(t)
          % Query OUTPUT? and parse 0/1 or ON/OFF style responses.
          isOn = false;
          try
               TG_Send(t, ':OUTPut?');

               resp = '';
               try
                    resp = readline(t);
               catch
                    % Fallback: read whatever is currently available
                    pause(0.10);
                    n = 0;
                    try
                         n = t.NumBytesAvailable;
                    catch
                         n = 0;
                    end
                    if n > 0
                         data = read(t, n, "uint8");
                         resp = char(data(:).');
                    end
               end

               resp = upper(strtrim(resp));
               if strcmp(resp, '1') || contains(resp, 'ON')
                    isOn = true;
               elseif strcmp(resp, '0') || contains(resp, 'OFF')
                    isOn = false;
               end
          catch
               isOn = false;
          end
     end

end

function drawRoundedBorder(panel, borderColor, borderWidth, cornerRadius)
     % Draw a rounded rectangle border around a uipanel using uiaxes
     try
          if isempty(panel) || ~isvalid(panel)
               return;
          end
          
          % Wait for panel to be fully positioned
          drawnow;
          pause(0.05);
          
          % Get panel position in pixels
          pos = panel.Position;
          if isempty(pos) || any(pos(3:4) <= 0)
               return;
          end
          
          % Create a uiaxes overlay for the border
          ax = uiaxes(panel);
          ax.Units = 'pixels';
          ax.Position = [0 0 pos(3) pos(4)];  % Fill the panel
          ax.Visible = 'off';
          ax.XLim = [0 pos(3)];
          ax.YLim = [0 pos(4)];
          ax.XTick = [];
          ax.YTick = [];
          ax.Color = 'none';
          ax.HitTest = 'off';
          ax.PickableParts = 'none';
          ax.XColor = 'none';
          ax.YColor = 'none';
          
          % Create rounded rectangle path
          r = min(cornerRadius, min(pos(3), pos(4)) / 4);  % Limit radius
          bw2 = borderWidth / 2;
          x0 = bw2;
          y0 = bw2;
          w = pos(3) - borderWidth;
          h = pos(4) - borderWidth;
          
          % Generate points for rounded rectangle going clockwise from top-left
          % Top-left corner: from left edge (pi) to top edge (pi/2)
          theta_tl = linspace(pi, pi/2, 15);
          x_tl = x0 + r + r * cos(theta_tl);
          y_tl = y0 + h - r + r * sin(theta_tl);
          
          % Top edge (straight line)
          x_top = linspace(x0 + r, x0 + w - r, 5);
          y_top = repmat(y0 + h, 1, 5);
          
          % Top-right corner: from top edge (pi/2) to right edge (0)
          theta_tr = linspace(pi/2, 0, 15);
          x_tr = x0 + w - r + r * cos(theta_tr);
          y_tr = y0 + h - r + r * sin(theta_tr);
          
          % Right edge (straight line)
          x_right = repmat(x0 + w, 1, 5);
          y_right = linspace(y0 + h - r, y0 + r, 5);
          
          % Bottom-right corner: from right edge (0) to bottom edge (-pi/2)
          theta_br = linspace(0, -pi/2, 15);
          x_br = x0 + w - r + r * cos(theta_br);
          y_br = y0 + r + r * sin(theta_br);
          
          % Bottom edge (straight line)
          x_bottom = linspace(x0 + w - r, x0 + r, 5);
          y_bottom = repmat(y0, 1, 5);
          
          % Bottom-left corner: from bottom edge (-pi/2) to left edge (pi)
          theta_bl = linspace(-pi/2, pi, 15);
          x_bl = x0 + r + r * cos(theta_bl);
          y_bl = y0 + r + r * sin(theta_bl);
          
          % Left edge (straight line)
          x_left = repmat(x0, 1, 5);
          y_left = linspace(y0 + r, y0 + h - r, 5);
          
          % Combine all segments into closed path
          x_path = [x_tl, x_top(2:end), x_tr(2:end), x_right(2:end), x_br(2:end), x_bottom(2:end), x_bl(2:end), x_left(2:end)];
          y_path = [y_tl, y_top(2:end), y_tr(2:end), y_right(2:end), y_br(2:end), y_bottom(2:end), y_bl(2:end), y_left(2:end)];
          
          % Draw the border
          plot(ax, x_path, y_path, 'Color', borderColor, 'LineWidth', borderWidth);
          
     catch
          % Fallback: use simple rectangle border if rounded corners fail
          try
               panel.BorderType = 'line';
               panel.BorderWidth = borderWidth;
               panel.ForegroundColor = borderColor;
          catch
               % Silently fail
          end
     end
end
% ===== END SIGNAL GENERATOR PANE =====

function sigAddTaggedRow(gl, row, labelText, tagName)
     lab = uilabel(gl, 'Text', labelText, 'HorizontalAlignment', 'right');
     lab.Layout.Row = row;
     lab.Layout.Column = 1;
     val = uilabel(gl, 'Text', '—', 'HorizontalAlignment', 'left', 'Tag', tagName);
     val.Layout.Row = row;
     val.Layout.Column = 2;
end

function [lbl, val] = AddROField(gl, row, labelText, valueText)
     lbl = uilabel(gl, 'Text', labelText, 'HorizontalAlignment', 'right');
     lbl.Layout.Row = row;
     lbl.Layout.Column = 1;

     val = uilabel(gl, 'Text', valueText, 'HorizontalAlignment', 'left');
     val.Layout.Row = row;
     val.Layout.Column = 2;

end



% ------------------------------------------------------------
% Physics dialog (invoked by "Open Physics..." button)
% ------------------------------------------------------------
function openPhysicsDialog(fig)
     if ~isvalid(fig)
          return;
     end

     if isfield(fig.UserData, 'physics')
          phys = fig.UserData.physics;
     else
          phys = struct();
     end

     d = uifigure('Name', 'Physics', 'Position', [240 50 850 510]);
     d.Resize = 'on';

     d.Color = [0.92 0.96 1.00];
     g = uigridlayout(d, [9, 3]);
     g.BackgroundColor = d.Color;
     % Rows: controls fixed; row 7 '1x' grows/shrinks. Columns proportional.
     g.RowHeight = {34, 34, 34, 34, 34, 10, '1x', 12, 50};
     g.ColumnWidth = {'1x', '1x', 70};  % col 3: medium c (m/s) shortened
     g.Padding = [56 16 16 16];  % left +40px: shifts all 5 fields right
     g.RowSpacing = 10;
     g.ColumnSpacing = 12;

     fs = 16;  % default + 4pt for Physics dialog

     lbMedium = uilabel(g, 'Text', 'Medium', 'FontSize', fs);
     lbMedium.Layout.Row = 1;
     lbMedium.Layout.Column = 1;
     ddMedium = uidropdown(g, 'FontSize', fs, ...
          'Items', {'De-ionised Water', 'Water', 'Saline', 'Air', 'Custom'}, ...
          'Value', getField(phys, 'medium', 'De-ionised Water'));
     ddMedium.Layout.Row = 1;
     ddMedium.Layout.Column = 2;

     edC = uieditfield(g, 'numeric', 'FontSize', fs, ...
          'Limits', [0 inf], ...
          'Value', getField(phys, 'c_mps', 1480));
     edC.Layout.Row = 1;
     edC.Layout.Column = 3;
     edC.Tooltip = 'Speed of sound c (m/s) for Custom medium';

     lbF0 = uilabel(g, 'Text', 'Transducer Frequency (F₀)', 'FontSize', fs);
     lbF0.Layout.Row = 2;
     lbF0.Layout.Column = 1;
     ddF0 = uidropdown(g, 'FontSize', fs, ...
          'Items', {'500 kHz', '1 MHz', '2 MHz'}, ...
          'ItemsData', [5e5, 1e6, 2e6], ...
          'Value', getField(phys, 'f0_hz', 1e6));
     ddF0.Layout.Row = 2;
     ddF0.Layout.Column = 2;

     lbD = uilabel(g, 'Text', 'Transducer Active diameter D (mm)', 'FontSize', fs);
     lbD.Layout.Row = 3;
     lbD.Layout.Column = 1;
     ddD = uidropdown(g, 'FontSize', fs, ...
          'Items', {'10 mm', '23 mm', '32 mm'}, ...
          'ItemsData', [10, 23, 32], ...
          'Value', getField(phys, 'diam_mm', 23));
     ddD.Layout.Row = 3;
     ddD.Layout.Column = 2;

     lbBurst = uilabel(g, 'Text', 'Signal Burst Number (N)', 'FontSize', fs);
     lbBurst.Layout.Row = 4;
     lbBurst.Layout.Column = 1;
     edBurstN = uieditfield(g, 'numeric', 'FontSize', fs, ...
          'Limits', [1 inf], ...
          'RoundFractionalValues', 'on', ...
          'Value', getField(phys, 'burst_n', 1));
     edBurstN.Layout.Row = 4;
     edBurstN.Layout.Column = 2;
     edBurstN.Tooltip = 'Integer burst number (clamped to 1..floor(Round-trip µs))';

     lbTimebase = uilabel(g, 'Text', sprintf('Timebase (<span style="font-size:%dpx">µ</span>s)', fs+1), 'FontSize', fs, 'Interpreter', 'html');
     lbTimebase.Layout.Row = 5;
     lbTimebase.Layout.Column = 1;
     ddTimebase = uidropdown(g, 'FontSize', fs, ...
          'Items', {'0.5', '1', '2', '5', '10'}, ...
          'ItemsData', [0.5, 1, 2, 5, 10], ...
          'Value', getField(phys, 'timebase_us', 1));
     ddTimebase.Layout.Row = 5;
     ddTimebase.Layout.Column = 2;
     ddTimebase.Tooltip = 'Timebase in µs';

     infoP = uipanel(g, 'BorderType', 'none', 'BackgroundColor', d.Color);
     infoP.Layout.Row = 7;
     infoP.Layout.Column = [1 3];
     glInfo = uigridlayout(infoP, [16, 1]);
     glInfo.RowHeight = {20, 6, 20, 6, 20, 6, 20, 6, 20, 6, 20, 10, 20, 2, 50, 6};
     glInfo.ColumnWidth = {'1x'};
     glInfo.Padding = [10 25 10 10];
     glInfo.RowSpacing = 0;
     glInfo.BackgroundColor = d.Color;

     h = uilabel(glInfo, 'Text', '<u>Derived Parameters (current inputs):</u>', 'FontSize', fs, 'HorizontalAlignment', 'left', 'Interpreter', 'html'); h.Layout.Row = 1;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 2;
     lbC = uilabel(glInfo, 'Text', 'c = — m/s', 'FontSize', fs+1, 'FontAngle', 'italic', 'HorizontalAlignment', 'left'); lbC.Layout.Row = 3;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 4;
     lbLambda = uilabel(glInfo, 'Text', 'λ = c/F₀ = — m', 'FontSize', fs+1, 'FontAngle', 'italic', 'HorizontalAlignment', 'left'); lbLambda.Layout.Row = 5;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 6;
     lbR = uilabel(glInfo, 'Text', 'Rayleigh distance R = — mm', 'FontSize', fs, 'HorizontalAlignment', 'left'); lbR.Layout.Row = 7;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 8;
     lbRTT = uilabel(glInfo, 'Text', 'Source-Target-Source Time = — µs', 'FontSize', fs, 'Interpreter', 'html', 'HorizontalAlignment', 'left'); lbRTT.Layout.Row = 9;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 10;
     lbBurst = uilabel(glInfo, 'Text', 'Burst number = —', 'FontSize', fs, 'HorizontalAlignment', 'left'); lbBurst.Layout.Row = 11;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 12;
     % Row 13: Burst Frame Duration
     lbBurstFrame = uilabel(glInfo, 'Text', 'Burst Frame Duration = — s', 'FontSize', fs, 'Interpreter', 'html', 'HorizontalAlignment', 'left'); lbBurstFrame.Layout.Row = 13;
     h = uilabel(glInfo, 'Text', '', 'HorizontalAlignment', 'left'); h.Layout.Row = 14;
     % Row 15: Burst-time round-trip label on left, four boxes on right
     burstRttRow = uigridlayout(glInfo, [1, 5]);
     burstRttRow.BackgroundColor = d.Color;
     burstRttRow.Layout.Row = 15;
     burstRttRow.Layout.Column = 1;
     burstRttRow.ColumnWidth = {250, 205, 100, 205, 100};
     burstRttRow.RowHeight = {30};
     burstRttRow.Padding = [0 0 0 0];
     burstRttRow.ColumnSpacing = 2;
     lbBurstRtt = uilabel(burstRttRow, 'Text', 'Burst-time round-trip = — µs', 'FontSize', fs, 'Interpreter', 'html', 'HorizontalAlignment', 'left'); lbBurstRtt.Layout.Row = 1; lbBurstRtt.Layout.Column = 1;
     lbRxOn = uilabel(burstRttRow, 'Text', 'Receive Switch ON Value...', 'FontSize', fs, 'HorizontalAlignment', 'right', 'WordWrap', 'off');
     lbRxOn.Layout.Row = 1; lbRxOn.Layout.Column = 2;
     lbRxOnVal = uilabel(burstRttRow, 'Text', '—', 'FontSize', fs, 'HorizontalAlignment', 'left');
     lbRxOnVal.Layout.Row = 1; lbRxOnVal.Layout.Column = 3;
     lbRxOff = uilabel(burstRttRow, 'Text', 'Receive Switch OFF Value...', 'FontSize', fs, 'HorizontalAlignment', 'right', 'WordWrap', 'off');
     lbRxOff.Layout.Row = 1; lbRxOff.Layout.Column = 4;
     lbRxOffVal = uilabel(burstRttRow, 'Text', '—', 'FontSize', fs, 'HorizontalAlignment', 'left');
     lbRxOffVal.Layout.Row = 1; lbRxOffVal.Layout.Column = 5;

     btnRow = uigridlayout(g, [1, 4]);
     btnRow.BackgroundColor = d.Color;
     btnRow.Layout.Row = 9;
     btnRow.Layout.Column = [1 3];
     btnRow.ColumnWidth = {'1x', 120, 120, 120};
     btnRow.RowHeight = {32};
     btnRow.Padding = [0 0 0 0];
     btnRow.ColumnSpacing = 10;

     uilabel(btnRow, 'Text', '', 'FontSize', fs);
     uibutton(btnRow, 'Text', 'Cancel', 'FontSize', fs, 'ButtonPushedFcn', @(s,e)delete(d));
     uibutton(btnRow, 'Text', 'Apply',  'FontSize', fs, 'ButtonPushedFcn', @(s,e)applyPhysics(false));
     uibutton(btnRow, 'Text', 'OK',     'FontSize', fs, 'ButtonPushedFcn', @(s,e)applyPhysics(true));
ddF0.ValueChangedFcn     = @(s,e)refreshDerived();
     ddD.ValueChangedFcn      = @(s,e)refreshDerived();
     edC.ValueChangedFcn       = @(s,e)refreshDerived();

     edBurstN.ValueChangedFcn  = @(s,e)refreshDerived();
     ddTimebase.ValueChangedFcn = @(s,e)refreshDerived();
     ddMedium.ValueChangedFcn  = @(s,e)mediumChanged();

     mediumChanged();
     refreshDerived();

     function mediumChanged()
          c_def = mediumToC(ddMedium.Value, edC.Value);
          if strcmp(ddMedium.Value, 'Custom')
               edC.Editable = 'on';
               edC.Enable = 'on';
          else
               edC.Value = c_def;
               edC.Editable = 'off';
               edC.Enable = 'off';
          end
          refreshDerived();
     end

     function [valStr, suffix] = formatWithSuffix(value, baseUnit)
          % Convert a value to scientific suffix format (k, M, µ, m, n, p, etc.)
          % value: numeric value in base units
          % baseUnit: base unit string (e.g., 'm', 's', 'Hz')
          % Returns: formatted string with suffix and unit
          
          absVal = abs(value);
          if absVal == 0 || ~isfinite(value)
               valStr = sprintf('%.3f', value);
               suffix = baseUnit;
               return;
          end
          
          % Determine appropriate suffix
          if absVal >= 1e12
               valStr = sprintf('%.3f', value / 1e12);
               suffix = ['T' baseUnit];
          elseif absVal >= 1e9
               valStr = sprintf('%.3f', value / 1e9);
               suffix = ['G' baseUnit];
          elseif absVal >= 1e6
               valStr = sprintf('%.3f', value / 1e6);
               suffix = ['M' baseUnit];
          elseif absVal >= 1e3
               valStr = sprintf('%.3f', value / 1e3);
               suffix = ['k' baseUnit];
          elseif absVal >= 1
               valStr = sprintf('%.3f', value);
               suffix = baseUnit;
          elseif absVal >= 1e-3
               valStr = sprintf('%.3f', value / 1e-3);
               suffix = ['m' baseUnit];
          elseif absVal >= 1e-6
               valStr = sprintf('%.3f', value / 1e-6);
               suffix = ['µ' baseUnit];
          elseif absVal >= 1e-9
               valStr = sprintf('%.3f', value / 1e-9);
               suffix = ['n' baseUnit];
          elseif absVal >= 1e-12
               valStr = sprintf('%.3f', value / 1e-12);
               suffix = ['p' baseUnit];
          else
               valStr = sprintf('%.3e', value);
               suffix = baseUnit;
          end
     end

     function refreshDerived()
          c_mps = mediumToC(ddMedium.Value, edC.Value);
          f0_hz = max(ddF0.Value, eps);
          diam_m = max(ddD.Value, 0) * 1e-3;
          a_m = diam_m / 2;

          lambda_m = c_mps / f0_hz;
          zR_m = (a_m * a_m) / max(lambda_m, eps);   % Rayleigh distance
          rtt_s = (2 * zR_m) / c_mps;                % round-trip to zR
          rtt_us = rtt_s * 1e6;


          maxBurst = max(1, floor(rtt_us));
          if edBurstN.Value < 1
               edBurstN.Value = 1;
          end
          if edBurstN.Value > maxBurst
               edBurstN.Value = maxBurst;
          end
          edBurstN.Limits = [1 maxBurst];
          lbC.Text = sprintf('c = %.1f m/s', c_mps);
          % Format lambda with scientific suffix (e.g. 1.480 mm instead of 1.480×10⁻³ m)
          [lambdaVal, lambdaSuffix] = formatWithSuffix(lambda_m, 'm');
          lbLambda.Text = sprintf('λ = c/F₀ = %s %s', lambdaVal, lambdaSuffix);
          lbR.Text = sprintf('Rayleigh distance R = %.1f mm', zR_m * 1e3);
          lbRTT.Text = sprintf('Source-Target-Source Time = %.1f <span style="font-size:%dpx">µ</span>s', rtt_us, fs+1);
          lbBurst.Text = sprintf('Burst number = %d (limit 1..%d)', round(edBurstN.Value), maxBurst);
          lbBurstRtt.Text = sprintf('Burst-time round-trip = %.1f <span style="font-size:%dpx">µ</span>s', rtt_us + (1e6/max(ddF0.Value,eps))*round(edBurstN.Value), fs+1);
          
          % Calculate Burst Frame Duration = (Signal Burst Number N) x (Timebase) with scientific suffix
          burstFrameDuration_us = ddTimebase.Value * round(edBurstN.Value);
          burstFrameDuration_s = burstFrameDuration_us * 1e-6;
          [bfdVal, bfdSuffix] = formatWithSuffix(burstFrameDuration_s, 's');
          lbBurstFrame.Text = sprintf('Burst Frame Duration = %s %s', bfdVal, bfdSuffix);
          
          % Update Receive Switch boxes (divided by timebase and rounded)
          rxOnVal = round(rtt_us / ddTimebase.Value);  % Source-Target-Source divided by timebase, rounded
          lbRxOnVal.Text = sprintf('%d', rxOnVal);
          rxOff_us = rtt_us + (ddTimebase.Value * round(edBurstN.Value));  % Source-Target-Source + (Timebase x N)
          rxOffVal = round(rxOff_us / ddTimebase.Value);  % Divided by timebase, rounded
          lbRxOffVal.Text = sprintf('%d', rxOffVal);

          % Persist selected timebase so Convert uses it even if user cancels (no Apply/OK)
          if isstruct(fig.UserData) && isfield(fig.UserData, 'physics')
               fig.UserData.physics.timebase_us = ddTimebase.Value;
          end
     end

     function applyPhysics(closeAfter)
          if nargin < 1
               closeAfter = false;
          end

          phys.medium = ddMedium.Value;
          phys.f0_hz = ddF0.Value;
          phys.diam_mm = ddD.Value;

          phys.burst_n = round(edBurstN.Value);
          phys.timebase_us = ddTimebase.Value;
          phys.CLKDIV = timebaseToClkDiv(phys.timebase_us);  % Calculate CLKDIV from timebase
          phys.c_mps = mediumToC(phys.medium, edC.Value);

          if strcmp(phys.medium, 'Custom')
               phys.c_mps = edC.Value;
          end

          diam_m = max(phys.diam_mm, 0) * 1e-3;
          a_m = diam_m / 2;
          phys.lambda_m = phys.c_mps / max(phys.f0_hz, eps);
          phys.rayleigh_m = (a_m * a_m) / max(phys.lambda_m, eps);
          phys.rtt_us = (2 * phys.rayleigh_m / phys.c_mps) * 1e6;

          phys.ttr_us = (phys.rayleigh_m / phys.c_mps) * 1e6;
          maxBurst = max(1, floor(phys.rtt_us));
          if phys.burst_n < 1
               phys.burst_n = 1;
          end
          if phys.burst_n > maxBurst
               phys.burst_n = maxBurst;
          end

          burst_period_us = 1e6 / max(phys.f0_hz, eps);
          phys.burst_period_us = burst_period_us;
          phys.burst_time_roundtrip_us = phys.rtt_us + (burst_period_us * phys.burst_n);

          phys.last_update = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
          fig.UserData.physics = phys;
          fig.UserData.LastAppliedTimebaseUs = phys.timebase_us;

          setLabelByTag(fig, 'phys_medium_val',   phys.medium);
          [f0_num, f0_unit] = formatFrequencyParts(phys.f0_hz);
          setLabelByTag(fig, 'phys_f0_val_lab', sprintf('Fundamental Frequency %s:', f0_unit));
          setLabelByTag(fig, 'phys_f0_val', f0_num);
          % Signal Generator pane inherits f0 from the dashboard/Physics pane.
          setLabelByTag(fig, 'siggen_f0_inherited_val_lab', sprintf('Fundamental Frequency %s:', f0_unit));
          setLabelByTag(fig, 'siggen_f0_inherited_val', f0_num);
          % Signal Generator pane inherits burst number from Physics pane.
          setLabelByTag(fig, 'siggen_burst_mode_val', sprintf('%d', phys.burst_n));
          setLabelByTag(fig, 'phys_diam_val',     sprintf('%.2f', phys.diam_mm));
          setLabelByTag(fig, 'phys_rayleigh_val', sprintf('%.1f', phys.rayleigh_m * 1e3));
                    setLabelByTag(fig, 'phys_ttr_val', sprintf('%.1f', phys.ttr_us));
          setLabelByTag(fig, 'phys_rtt_val',      sprintf('%.1f', phys.rtt_us));
          setLabelByTag(fig, 'phys_btrtt_val', sprintf('%.1f', phys.burst_time_roundtrip_us));
          setLabelByTag(fig, 'phys_timebase_val', sprintf('%.1f', phys.timebase_us));  % Timebase inherited from Physics submenu
          rxOnVal = round(phys.rtt_us / phys.timebase_us);  % Receive Switch ON: divided by timebase, rounded
          setLabelByTag(fig, 'phys_rxon_val', sprintf('%d', rxOnVal));
          rxOff_us = phys.rtt_us + (phys.timebase_us * phys.burst_n);  % Source-Target-Source + (Timebase x N)
          rxOffVal = round(rxOff_us / phys.timebase_us);  % Receive Switch OFF: divided by timebase, rounded
          setLabelByTag(fig, 'phys_rxoff_val', sprintf('%d', rxOffVal));
          setLabelByTag(fig, 'phys_lastupdate_val', ['Last updated: ' phys.last_update]);

          if closeAfter
               delete(d);
          end
     end
end

function c = mediumToC(medium, customDefault)
     switch medium
          case {'De-ionised Water','Water'}
               c = 1480;
          case 'Saline'
               c = 1530;
          case 'Air'
               c = 343;
          otherwise
               c = customDefault;
     end
end

function clkdiv = timebaseToClkDiv(timebase_us)
     % Convert timebase (µs) to CLK DIVISOR hex value (decimal form for storage)
     % Mapping: 0.5 => 0x06, 1 => 0x0C, 2 => 0x18, 5 => 0x3C, 10 => 0x78
     tol = 1e-6;
     if abs(timebase_us - 0.5) < tol
          clkdiv = hex2dec('06');  % 0x06
     elseif abs(timebase_us - 1.0) < tol
          clkdiv = hex2dec('0C');  % 0x0C
     elseif abs(timebase_us - 2.0) < tol
          clkdiv = hex2dec('18');  % 0x18
     elseif abs(timebase_us - 5.0) < tol
          clkdiv = hex2dec('3C');  % 0x3C
     elseif abs(timebase_us - 10.0) < tol
          clkdiv = hex2dec('78');  % 0x78
     else
          clkdiv = hex2dec('0C');  % Default 1 µs => 0x0C
     end
end

function v = getField(s, name, defaultVal)
     if isstruct(s) && isfield(s, name)
          v = s.(name);
     else
          v = defaultVal;
     end
end

function [numStr, unitStr] = formatFrequencyParts(f0_hz)
     % Return numeric string and engineering unit for frequency display.
     if ~isfinite(f0_hz)
          numStr = '—';
          unitStr = 'Hz';
          return;
     end
     if f0_hz >= 1e6
          unitStr = 'MHz';
          f0_disp = f0_hz / 1e6;
     elseif f0_hz >= 1e3
          unitStr = 'kHz';
          f0_disp = f0_hz / 1e3;
     else
          unitStr = 'Hz';
          f0_disp = f0_hz;
     end
     if abs(f0_disp - round(f0_disp)) < 1e-9
          numStr = sprintf('%.0f', f0_disp);
     else
          numStr = sprintf('%.3g', f0_disp);
     end
end

function txt = formatFrequencyText(f0_hz)
     if ~isfinite(f0_hz)
          txt = '-';
          return;
     end

     if f0_hz >= 1e6
          v = f0_hz / 1e6;
          if abs(v - round(v)) < 1e-9
               txt = sprintf('%.0f MHz', v);
          else
               txt = sprintf('%.3f MHz', v);
          end
          return;
     end

     if f0_hz >= 1e3
          v = f0_hz / 1e3;
          if abs(v - round(v)) < 1e-9
               txt = sprintf('%.0f kHz', v);
          else
               txt = sprintf('%.3f kHz', v);
          end
          return;
     end

     if abs(f0_hz - round(f0_hz)) < 1e-9
          txt = sprintf('%.0f Hz', f0_hz);
     else
          txt = sprintf('%.3f Hz', f0_hz);
     end
end

function setLabelByTag(fig, tag, txt)
     try
          h = findobj(fig, 'Type', 'uilabel', 'Tag', tag);
          if ~isempty(h) && isvalid(h(1))
               h(1).Text = txt;
          end
     catch
     end
end

function SS_CommsInit(fig)
     if ~isstruct(fig.UserData)
          fig.UserData = struct();
     end
     if ~isfield(fig.UserData, 'Comms') || ~isstruct(fig.UserData.Comms)
          fig.UserData.Comms = struct();
     end

     fig.UserData.Comms.Serial = [];
     fig.UserData.Comms.ForceReconnect = true;
     fig.UserData.Comms.LastError = "";
     fig.UserData.Comms.EnumPollRunning = false;  % Guard flag to prevent overlapping timer executions

     % Seed selected port/baud from current dropdowns (prevents stale defaults).
     try
          ui = fig.UserData.UI;
          if isfield(ui, 'ComPortDropdown') && isvalid(ui.ComPortDropdown)
               fig.UserData.Comms.SelectedPort = char(ui.ComPortDropdown.Value);
          end
          if isfield(ui, 'BaudDropdown') && isvalid(ui.BaudDropdown)
               b = str2double(char(ui.BaudDropdown.Value));
               if ~isnan(b) && b > 0
                    fig.UserData.Comms.SelectedBaud = b;
               else
                    fig.UserData.Comms.SelectedBaud = 9600;
               end
          else
               fig.UserData.Comms.SelectedBaud = 9600;
          end
     catch
          fig.UserData.Comms.SelectedBaud = 9600;
     end

     % Background enumeration: keep the COM dropdown in sync with hot-plug
     % of the *external FTDI cable only* (VID_0403/PID_6001).
     % DISABLED: SS_EnumPoll -> SS_GetFtdiCablePorts uses system(powershell) which
     % causes MATLAB Run/Pause toggle when run from a timer. Timer is created
     % (for cleanup) but NOT started. Use the "Refresh" button next to the COM
     % dropdown to update the list after hot-plug.
     tEnum = timer('ExecutionMode', 'fixedSpacing', 'Period', 10.0, 'BusyMode', 'drop');
     tEnum.Name = 'SmartSwitch_TimerEnum';
     tEnum.TimerFcn = @(~,~)SS_EnumPoll(fig, tEnum);
     fig.UserData.Comms.TimerEnum = tEnum;
     % do NOT start(tEnum)

     % Comms poller (Link + Alive lamps)
     t = timer('ExecutionMode', 'fixedSpacing', 'Period', 1.0, 'BusyMode', 'drop');
     t.Name = 'SmartSwitch_TimerComms';
     t.TimerFcn = @(~,~)SS_CommsPoll(fig, t);
     fig.UserData.Comms.Timer = t;

     start(t);
     
end

function SS_EnumPoll(fig, tSelf)
     % Silently refresh COM dropdown items based on the external FTDI cable.
     % Guard against overlapping executions to prevent blocking MATLAB
     try
          if isempty(fig) || ~isvalid(fig)
               SS_StopDeleteTimerSafe(tSelf);
               return;
          end
          
          % Check if previous execution is still running
          if ~isstruct(fig.UserData)
               fig.UserData = struct();
          end
          if ~isfield(fig.UserData.Comms, 'EnumPollRunning')
               fig.UserData.Comms.EnumPollRunning = false;
          end
          if fig.UserData.Comms.EnumPollRunning
               return;  % Skip if previous call still running
          end
          
          fig.UserData.Comms.EnumPollRunning = true;
          
          if ~isfield(fig.UserData, 'UI')
               fig.UserData.Comms.EnumPollRunning = false;
               return;
          end

          ui = fig.UserData.UI;
          if ~isfield(ui, 'ComPortDropdown') || isempty(ui.ComPortDropdown) || ~isvalid(ui.ComPortDropdown)
               fig.UserData.Comms.EnumPollRunning = false;
               return;
          end

          newItems = SS_GetFtdiCablePorts();
          if isempty(newItems)
               newItems = {'None'};
          end

          dd = ui.ComPortDropdown;
          oldItems = dd.Items;
          oldVal   = char(dd.Value);

          % Update list only when it actually changes.
          if ~isequal(string(oldItems), string(newItems))
               dd.Items = newItems;
          end

          % Preserve selection if still valid; otherwise set to 'None'.
          if any(strcmpi(dd.Items, oldVal))
               % keep
          else
               if any(strcmpi(dd.Items, 'None'))
                    dd.Value = 'None';
               else
                    dd.Value = dd.Items{1};
               end

               % Force reconnect/close on disappearance.
               try
                    if ~isfield(fig.UserData, 'Comms') || ~isstruct(fig.UserData.Comms)
                         fig.UserData.Comms = struct();
                    end
                    fig.UserData.Comms.SelectedPort = char(dd.Value);
                    fig.UserData.Comms.ForceReconnect = true;
               catch
               end
          end
          fig.UserData.Comms.EnumPollRunning = false;  % Clear flag on successful completion
     catch
          try
               if isstruct(fig.UserData) && isstruct(fig.UserData.Comms)
                    fig.UserData.Comms.EnumPollRunning = false;  % Clear flag on error
               end
          catch
          end
     end
end

function SS_CommsForceReconnect(fig)
     try
          if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms') && isstruct(fig.UserData.Comms)
               fig.UserData.Comms.ForceReconnect = true;
          end
     catch
     end
end

function SS_OnRefreshComPortList(fig)
     % Manual refresh of COM dropdown (FTDI hot-plug). Uses SS_GetFtdiCablePorts
     % on button click instead of a timer to avoid Run/Pause from system(powershell).
     try
          if isempty(fig) || ~isvalid(fig), return; end
          ui = fig.UserData.UI;
          if ~isfield(ui, 'ComPortDropdown') || ~isvalid(ui.ComPortDropdown), return; end
          dd = ui.ComPortDropdown;
          newItems = SS_GetFtdiCablePorts();
          if isempty(newItems), newItems = {'None'}; end
          oldVal = char(dd.Value);
          dd.Items = newItems;
          if ~any(strcmpi(dd.Items, oldVal))
               if any(strcmpi(dd.Items, 'None'))
                    dd.Value = 'None';
               else
                    dd.Value = dd.Items{1};
               end
               if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms')
                    fig.UserData.Comms.SelectedPort = char(dd.Value);
                    fig.UserData.Comms.ForceReconnect = true;
               end
          end
     catch
     end
end

function SS_OnPortChanged(fig, src)
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end
          if ~isstruct(fig.UserData)
               fig.UserData = struct();
          end
          if ~isfield(fig.UserData, 'Comms') || ~isstruct(fig.UserData.Comms)
               fig.UserData.Comms = struct();
          end
          fig.UserData.Comms.SelectedPort = char(src.Value);
          fig.UserData.Comms.ForceReconnect = true;
     catch
     end
end

function SS_OnBaudChanged(fig, src)
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end
          if ~isstruct(fig.UserData)
               fig.UserData = struct();
          end
          if ~isfield(fig.UserData, 'Comms') || ~isstruct(fig.UserData.Comms)
               fig.UserData.Comms = struct();
          end
          fig.UserData.Comms.SelectedBaud = str2double(char(src.Value));
          if isnan(fig.UserData.Comms.SelectedBaud) || fig.UserData.Comms.SelectedBaud <= 0
               fig.UserData.Comms.SelectedBaud = 9600;
          end
          fig.UserData.Comms.ForceReconnect = true;
     catch
     end
end

function SS_OnModeButtonPushed(fig, btn)
     % Toggle Mode 0 (Transmit, pink) <-> Mode 1 (Transmit & Receive, blue).
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end
          if ~isstruct(fig.UserData)
               fig.UserData = struct();
          end
          if isfield(fig.UserData, 'Mode') && strcmp(fig.UserData.Mode, '1')
               fig.UserData.Mode = '0';
               btn.Text = 'Transmit';
               btn.BackgroundColor = [1.0 0.75 0.80];  % Pink
          else
               fig.UserData.Mode = '1';
               btn.Text = 'Transmit & Receive';
               btn.BackgroundColor = [0.65 0.78 1.0];  % Blue
          end
     catch
     end
end

function SS_OnUartConnectDisconnect(fig, btn)
     % Connect/Disconnect to serial using COM Port and Baud from the main dashboard.
     % Use button Text to decide Connect vs Disconnect; ancestor(btn,'Figure') for fig.
     try
          try
               f = ancestor(btn, 'Figure');
               if ~isempty(f) && isvalid(f), fig = f; end
          catch
          end

          if strcmpi(strtrim(string(btn.Text)), 'Disconnect')
               % Disconnect: amber, release serial, clear state, red, "Connect"
               sp = [];
               try, if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial'), sp = fig.UserData.UartSerial; end; catch; end
               try, SS_SetConnectButtonColor(fig, 'amber'); catch; end
               if ~isempty(sp)
                    try, if isa(sp, 'serialport'), flush(sp); delete(sp); end; catch; end
               end
               try, if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial'), fig.UserData.UartSerial = []; end; catch; end
               try, if isstruct(fig.UserData) && isfield(fig.UserData, 'RegisterDetailsFig') && ~isempty(fig.UserData.RegisterDetailsFig) && isvalid(fig.UserData.RegisterDetailsFig), fig.UserData.RegisterDetailsFig.UserData.UartSerial = []; end; catch; end
               try, if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms'), fig.UserData.Comms.SmartSwitchLinkUp = false; end; catch; end
               try, SS_SetConnectButtonColor(fig, false); catch; end
               btn.Text = 'Connect';
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblUartStatus') && isvalid(fig.UserData.UI.LblUartStatus)
                         fig.UserData.UI.LblUartStatus.Text = 'Disconnected. Port released.';
                    end
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'Lbl8wrDebug') && isvalid(fig.UserData.UI.Lbl8wrDebug)
                         fig.UserData.UI.Lbl8wrDebug.Text = '—';
                    end
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblBoardId') && isvalid(fig.UserData.UI.LblBoardId)
                         fig.UserData.UI.LblBoardId.Text = '—';
                    end
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblRxdStart') && isvalid(fig.UserData.UI.LblRxdStart)
                         fig.UserData.UI.LblRxdStart.Text = '—';
                    end
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblRxdStop') && isvalid(fig.UserData.UI.LblRxdStop)
                         fig.UserData.UI.LblRxdStop.Text = '—';
                    end
               catch
               end
          else
               % Connect: clear any stale handle, then open and 8WR
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial') && ~isempty(fig.UserData.UartSerial)
                         try, flush(fig.UserData.UartSerial); delete(fig.UserData.UartSerial); catch; end
                    end
               catch
               end
               port = ''; baud = 9600;
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI')
                         if isfield(fig.UserData.UI, 'ComPortDropdown') && isvalid(fig.UserData.UI.ComPortDropdown)
                              port = string(fig.UserData.UI.ComPortDropdown.Value);
                         end
                         if isfield(fig.UserData.UI, 'BaudDropdown') && isvalid(fig.UserData.UI.BaudDropdown)
                              b = str2double(char(fig.UserData.UI.BaudDropdown.Value));
                              if ~isnan(b) && b > 0, baud = b; end
                         end
                    end
               catch
               end
               if isempty(port) || strlength(strtrim(port)) == 0, port = string(GetDefaultComPort()); end
               if strcmpi(strtrim(port), 'None'), port = 'COM4'; end
               sp = serialport(port, baud, 'DataBits', 8, 'Parity', 'none', 'StopBits', 1);
               configureTerminator(sp, uint8(0));
               sp.Timeout = 1.0;
               flush(sp);
               if ~isstruct(fig.UserData), fig.UserData = struct(); end
               fig.UserData.UartSerial = sp;
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'RegisterDetailsFig') && ~isempty(fig.UserData.RegisterDetailsFig) && isvalid(fig.UserData.RegisterDetailsFig)
                         fig.UserData.RegisterDetailsFig.UserData.UartSerial = sp;
                    end
               catch
               end
               btn.Text = 'Disconnect';
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblUartStatus') && isvalid(fig.UserData.UI.LblUartStatus)
                         fig.UserData.UI.LblUartStatus.Text = sprintf('Connected to %s @ %d baud', port, baud);
                    end
               catch
               end
               try, if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms'), fig.UserData.Comms.LastError = ''; end; catch; end
               try, if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms'), fig.UserData.Comms.SmartSwitchLinkUp = false; end; catch; end
               % 8WR read at 0x00: if data ~= 0xFF assume SmartSwitch connected; set Link and Comms.SmartSwitchLinkUp
               pause(0.1);
               okLink = false;
               try
                    [ok, ~, ~, data, tx, rx] = SS_UartRead8(sp, uint8(0));
                    okLink = (ok && data ~= uint8(255));
                    % Show tx/rx in SmartSwitch pane for debugging
                    if numel(tx) >= 5
                         stx = sprintf('tx: %02X %02X %02X %02X %02X', tx(1), tx(2), tx(3), tx(4), tx(5));
                    else
                         stx = 'tx: (none)';
                    end
                    if numel(rx) >= 5
                         srx = sprintf('  rx: %02X %02X %02X %02X %02X', rx(1), rx(2), rx(3), rx(4), rx(5));
                    else
                         srx = '  rx: (timeout/err)';
                    end
                    s8 = sprintf('8WR@0x00: %s%s  ok=%d data=0x%02X', stx, srx, uint8(ok), data);
                    try
                         if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'Lbl8wrDebug') && isvalid(fig.UserData.UI.Lbl8wrDebug)
                              fig.UserData.UI.Lbl8wrDebug.Text = s8;
                         end
                         % Don't update BOARD ID on Connect - only update on Convert button
                    catch
                    end
               catch
               end
               if ~isstruct(fig.UserData), fig.UserData = struct(); end
               if ~isfield(fig.UserData, 'Comms') || ~isstruct(fig.UserData.Comms), fig.UserData.Comms = struct(); end
               fig.UserData.Comms.SmartSwitchLinkUp = okLink;
               try, SS_SetConnectButtonColor(fig, okLink); catch; end
          end
     catch ME
          try, if exist('sp', 'var') && ~isempty(sp) && isa(sp, 'serialport'), delete(sp); end; catch; end
          try, if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial'), fig.UserData.UartSerial = []; end; catch; end
          try, if isstruct(fig.UserData) && isfield(fig.UserData, 'RegisterDetailsFig') && ~isempty(fig.UserData.RegisterDetailsFig) && isvalid(fig.UserData.RegisterDetailsFig), fig.UserData.RegisterDetailsFig.UserData.UartSerial = []; end; catch; end
          try, if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms'), fig.UserData.Comms.SmartSwitchLinkUp = false; end; catch; end
          try, SS_SetConnectButtonColor(fig, false); catch; end
          btn.Text = 'Connect';
          try
               if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'LblUartStatus') && isvalid(fig.UserData.UI.LblUartStatus)
                    fig.UserData.UI.LblUartStatus.Text = 'ERROR: ' + string(ME.message);
               end
               if isstruct(fig.UserData) && isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'Lbl8wrDebug') && isvalid(fig.UserData.UI.Lbl8wrDebug)
                    fig.UserData.UI.Lbl8wrDebug.Text = '—';
               end
          catch
          end
          try, if isstruct(fig.UserData) && isfield(fig.UserData, 'Comms'), fig.UserData.Comms.LastError = char(ME.message); end; catch; end
     end
end

function SS_CommsPoll(fig, tSelf)
     if isempty(fig) || ~isvalid(fig)
          SS_StopDeleteTimerSafe(tSelf);
          return;
     end

     ui = [];
     comms = [];
     try
          if isstruct(fig.UserData)
               if isfield(fig.UserData, 'UI')
                    ui = fig.UserData.UI;
               end
               if isfield(fig.UserData, 'Comms')
                    comms = fig.UserData.Comms;
               end
          end
     catch
     end

     if isempty(ui) || ~isstruct(ui)
          return;
     end
     if isempty(comms) || ~isstruct(comms)
          return;
     end

     % Button color is set only by Connect/Disconnect handler. CommsPoll does not override it.
end

function SS_SetLampGrey(ui, fieldName)
     try
          if ~isfield(ui, fieldName)
               return;
          end
          h = ui.(fieldName);
          if isempty(h) || ~isvalid(h)
               return;
          end
          h.Color = [0.50 0.50 0.50];
     catch
     end
end

function SS_SetConnectButtonColor(fig, kind)
     % kind: true/'green' -> green, false/'red' -> red, 'amber' -> amber (disconnecting)
     try
          if ~isstruct(fig.UserData) || ~isfield(fig.UserData, 'UI') || ~isfield(fig.UserData.UI, 'BtnUartConnect')
               return;
          end
          btn = fig.UserData.UI.BtnUartConnect;
          if isempty(btn) || ~isvalid(btn)
               return;
          end
          if (ischar(kind) || isstring(kind)) && strcmpi(string(kind), 'amber')
               btn.BackgroundColor = [1.0 0.70 0.0];
          elseif kind
               btn.BackgroundColor = [0.10 0.70 0.20];
          else
               btn.BackgroundColor = [0.85 0.20 0.20];
          end
     catch
     end
end

function ok = SS_EnsureSerialOpen(fig)
     % Link is open only when the dashboard Connect has established an active
     % serial (fig.UserData.UartSerial). UartSerial is set by the dashboard
     % Connect (SS_OnUartConnectDisconnect) and used by comms poll.
     ok = false;
     try
          if ~isstruct(fig.UserData) || ~isfield(fig.UserData, 'UartSerial')
               return;
          end
          sp = fig.UserData.UartSerial;
          if isempty(sp) || ~isa(sp, 'serialport') || ~isvalid(sp)
               return;
          end
          ok = true;
     catch
          ok = false;
     end
end

function sp = SS_OpenSerial(fig, port, baud)
     sp = [];
     try
          % Defensive cleanup: release any lingering handle on the same port.
          try
               delete(serialportfind("Port", port));
          catch
          end
          sp = serialport(port, baud, "DataBits", 8, "Parity", "none", "StopBits", 1);
          configureTerminator(sp, uint8(0));
          sp.Timeout = 1.0;
          flush(sp);
          try
               fig.UserData.Comms.LastError = "";
          catch
          end
     catch ME
          sp = [];
          try
               fig.UserData.Comms.LastError = char(ME.message);
          catch
          end
     end
end

function sp = SS_CloseSerial(sp)
     % Properly release the serialport so the COM port is not left locked.
     try
          if ~isempty(sp) && isa(sp, "serialport")
               try
                    flush(sp);
               catch
               end
               try
                    delete(sp);
               catch
               end
          end
     catch
     end
     sp = [];
end

function ok = SS_ProbeAlive(fig)
     ok = false;
     try
          sp = [];
          if isstruct(fig.UserData) && isfield(fig.UserData, 'UartSerial')
               sp = fig.UserData.UartSerial;
               if isempty(sp) || ~isa(sp, 'serialport') || ~isvalid(sp)
                    sp = [];
               end
          end
          if isempty(sp)
               return;
          end
          [good, ~, ~, ~] = SS_UartRead8(sp, uint8(hex2dec('00')));
          ok = good;
     catch
          ok = false;
     end
end

% --- read_reg / write_reg / validate_resp (UPduino_UART_GUI 5-byte frame) ---
function [rx, tx] = read_reg(sp, addr)
     addr = uint8(addr);
     OP_READ8 = uint8(1);
     tx = uint8([hex2dec('55'), OP_READ8, addr, 0, 0]);
     tx(5) = bitxor(bitxor(bitxor(tx(1), tx(2)), tx(3)), tx(4));
     flush(sp); write(sp, tx, 'uint8');
     rx = read(sp, 5, 'uint8');
end

function rx = write_reg(sp, addr, data)
     addr = uint8(addr); data = uint8(data);
     OP_WRITE8 = uint8(2);
     tx = uint8([hex2dec('55'), OP_WRITE8, addr, data, 0]);
     tx(5) = bitxor(bitxor(bitxor(tx(1), tx(2)), tx(3)), tx(4));
     flush(sp); write(sp, tx, 'uint8');
     rx = read(sp, 5, 'uint8');
end

function [ok, msg, status, raddr, rdata] = validate_resp(rx)
     ok = false; msg = ""; status = uint8(0); raddr = uint8(0); rdata = uint8(0);
     if numel(rx) ~= 5, msg = "Bad length"; return; end
     sof = rx(1); status = rx(2); raddr = rx(3); rdata = rx(4); chk = rx(5);
     if sof ~= hex2dec('56'), msg = "Bad SOF"; return; end
     if chk ~= bitxor(bitxor(bitxor(sof, status), raddr), rdata), msg = "Bad CHK"; return; end
     ok = true;
end

function [ok, status, addr, data, tx, rx] = SS_UartRead8(sp, addr)
     ok = false;
     status = uint8(0);
     data = uint8(0);
     tx = uint8([]);
     rx = uint8([]);

     try
          sync = uint8(hex2dec('55'));
          op   = uint8(1);              % READ8
          dataTx = uint8(0);
          chk = bitxor(bitxor(bitxor(sync, op), addr), dataTx);
          tx = uint8([sync, op, addr, dataTx, chk]);

          flush(sp);
          write(sp, tx, 'uint8');

          rx = read(sp, 5, 'uint8');
          if numel(rx) ~= 5
               return;
          end
          if rx(1) ~= uint8(hex2dec('56'))
               return;
          end

          status = rx(2);
          addr   = rx(3);
          data   = rx(4);
          chkRx  = rx(5);
          chkExp = bitxor(bitxor(bitxor(rx(1), rx(2)), rx(3)), rx(4));
          if chkRx ~= chkExp
               return;
          end

          ok = true;
     catch
          ok = false;
          sync = uint8(hex2dec('55'));
          op   = uint8(1);
          dataTx = uint8(0);
          chk = bitxor(bitxor(bitxor(sync, op), addr), dataTx);
          tx = uint8([sync, op, addr, dataTx, chk]);
          rx = uint8([]);
     end
end

function SS_SetLampSafe(ui, fieldName, isOk)
     try
          if ~isfield(ui, fieldName)
               return;
          end
          h = ui.(fieldName);
          if isempty(h) || ~isvalid(h)
               return;
          end

          if isOk
               h.Color = [0.10 0.70 0.20];
          else
               h.Color = [0.85 0.20 0.20];
          end
     catch
     end
end

function SS_SetLampTooltip(fig, ui, fieldName)
     try
          if ~isfield(ui, fieldName)
               return;
          end
          h = ui.(fieldName);
          if isempty(h) || ~isvalid(h)
               return;
          end

          msg = "";
          try
               if isstruct(fig.UserData) && isfield(fig.UserData, "Comms") && isfield(fig.UserData.Comms, "LastError")
                    msg = string(fig.UserData.Comms.LastError);
               end
          catch
          end

          if strlength(strtrim(msg)) == 0
               % Link and Alive use fig.UserData.UartSerial (set by FPGA pane onConnect).
               isOpen = false;
               try
                    if isstruct(fig.UserData) && isfield(fig.UserData, "UartSerial")
                         sp = fig.UserData.UartSerial;
                         if ~isempty(sp) && isa(sp, "serialport") && isvalid(sp)
                              isOpen = true;
                         end
                    end
               catch
               end

               if strcmp(fieldName, "LampLink")
                    if isOpen
                         h.Tooltip = "Link: Serial Port Open";
                    else
                         h.Tooltip = "Link: Not connected (use Connect)";
                    end
               else
                    if isOpen
                         h.Tooltip = "FPGA Alive: READ8 probe @ 0x00";
                    else
                         h.Tooltip = "FPGA Alive: (not connected)";
                    end
               end
          else
               if strcmp(fieldName, "LampLink")
                    h.Tooltip = "Link error: " + msg;
               else
                    h.Tooltip = "Alive error: " + msg;
               end
          end
     catch
     end
end

function SS_OnClose(fig)
     try
          if isvalid(fig)
               SS_CommsCleanup(fig);
          end
     catch
     end
     delete(fig);
end

function SS_CommsCleanup(fig)
     SS_DeleteOrphanSmartSwitchTimers();
     try
          Uart_cleanup_serial(fig);
     catch
     end
     try
          if isstruct(fig.UserData) && isfield(fig.UserData, 'RegisterDetailsFig') && ~isempty(fig.UserData.RegisterDetailsFig) && isvalid(fig.UserData.RegisterDetailsFig)
               delete(fig.UserData.RegisterDetailsFig);
               fig.UserData.RegisterDetailsFig = [];
          end
     catch
     end
     try
          if ~isstruct(fig.UserData) || ~isfield(fig.UserData, 'Comms')
               return;
          end

          comms = fig.UserData.Comms;

          % Stop/delete BOTH timers (enum + comms poll). R26 only deleted one.
          try
               if isfield(comms, 'TimerEnum') && ~isempty(comms.TimerEnum) && isvalid(comms.TimerEnum)
                    stop(comms.TimerEnum);
                    delete(comms.TimerEnum);
               end
          catch
          end

          try
               if isfield(comms, 'Timer') && ~isempty(comms.Timer) && isvalid(comms.Timer)
                    stop(comms.Timer);
                    delete(comms.Timer);
               end
          catch
          end
          
          


          try
               if isfield(comms, 'Serial')
                    fig.UserData.Comms.Serial = SS_CloseSerial(comms.Serial);
               end
          catch
          end
     catch
     end
end

function items = GetComPortList()
     % Only show the external FTDI cable UART (VID_0403 & PID_6001).
     %
     % Rationale:
     %   - serialportlist("available") is slow/unreliable on this host and
     %     returns ports that are not part of the SmartSwitch system (e.g.
     %     Intel AMT SOL, Bluetooth).
     %   - We must ONLY expose the external FTDI TTL-232 cable.
     %
     % Behaviour:
     %   - Return {'None'} when the cable is absent.
     %   - Return {'COMx'} (single item) when present.
     items = SS_GetFtdiCablePorts();
end

function val = GetDefaultComPort()
     items = GetComPortList();
     if any(strcmpi(items, 'COM4'))
          val = 'COM4';
     else
          val = items{1};
     end
end

function items = SS_GetFtdiCablePorts()
     % SS_GetFtdiCablePorts()
     %
     % Returns a 1-element cell array containing the COM port associated
     % with the external FTDI cable (VID_0403 & PID_6001), || {'None'} if
     % not present.
     %
     % Implementation note:
     %   On this host, querying Win32_SerialPort via Get-CimInstance from
     %   MATLAB can return empty results. Get-PnpDevice is reliable.
     %   Note: This function uses blocking system() call which can cause
     %   MATLAB Run/Pause toggle if called too frequently from timers.
     try
          cmd = [ ...
               'powershell -NoProfile -Command "', ...
               'Get-PnpDevice -PresentOnly | ', ...
               '? { $_.InstanceId -match ''VID_0403'' -and $_.InstanceId -match ''PID_6001'' } | ', ...
               'Select-Object -ExpandProperty FriendlyName"' ...
          ];
          [st,out] = system(cmd);
          if st ~= 0
               items = {'None'};
               return;
          end

          % Parse FriendlyName lines like: "USB Serial Port (COM4)"
          lines = regexp(string(out), "\r\n|\n|\r", 'split');
          port = "";
          for k = 1:numel(lines)
               s = strtrim(lines(k));
               if strlength(s) == 0
                    continue;
               end
               tok = regexp(s, "\((COM\d+)\)", 'tokens', 'once');
               if ~isempty(tok)
                    port = string(tok{1});
                    break;
               end
          end

          if strlength(port) == 0
               items = {'None'};
          else
               items = {char(port)};
          end
     catch
          items = {'None'};
     end
end

function SS_SetLinkLamps(fig, okLink, okAlive, errMsg)
     % SS_SetLinkLamps(fig, okLink, okAlive, errMsg)
     % Compatibility helper: older init/error paths call this function.
     % It updates LastError and the Link/Alive lamps consistently.
     try
          if isempty(fig) || ~isvalid(fig)
               SS_StopDeleteTimerSafe(tSelf);
               return;
          end

          try
               if ~isstruct(fig.UserData)
                    fig.UserData = struct();
               end
               if ~isfield(fig.UserData, 'Comms') || ~isstruct(fig.UserData.Comms)
                    fig.UserData.Comms = struct();
               end
               fig.UserData.Comms.LastError = string(errMsg);
          catch
          end

          ui = [];
          try
               if isstruct(fig.UserData) && isfield(fig.UserData, 'UI')
                    ui = fig.UserData.UI;
               end
          catch
               ui = [];
          end

          if isempty(ui) || ~isstruct(ui)
               return;
          end

          try, SS_SetConnectButtonColor(fig, logical(okLink)); catch; end
     catch
     end
end


function SS_DeleteOrphanSmartSwitchTimers()
     % Stop/delete any SmartSwitch timers that may have survived an unclean exit.
     try
          t = timerfindall;
          for k = 1:numel(t)
               try
                    if isprop(t(k), 'Name')
                         nm = char(t(k).Name);
                    else
                         nm = '';
                    end
                    if strcmp(nm, 'SmartSwitch_TimerEnum') || strcmp(nm, 'SmartSwitch_TimerComms')
                         SS_StopDeleteTimerSafe(t(k));
                    end
               catch
               end
          end
     catch
     end
end

function SS_StopDeleteTimerSafe(tObj)
     % Stop/delete a timer handle without throwing.
     try
          if isempty(tObj)
               return;
          end
          if isvalid(tObj)
               try, stop(tObj); catch, end
               try, delete(tObj); catch, end
          end
     catch
     end
end

function SS_TG5011A_TestLink(fig)
     % Attempts TCP connection to the TG5011A and performs a simple "*IDN?" query.
     % Updates the TG5011A link lamp in the UI.

     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end

          ip = '';
          try
               ip = getpref('SmartSwitch','TG5011A_IP');
          catch
               ip = '';
          end

          port = 9221;
          try
               port = getpref('SmartSwitch','TG5011A_PORT');
          catch
               port = 9221;
          end

          if isempty(ip)
               SS_TG5011A_SetLamp(fig, [1 0 0]);
               return;
          end

          SS_TG5011A_SetLamp(fig, [0.9 0.7 0.0]); % amber while attempting

          % Get button reference and set to amber
          btnTest = [];
          try
               if isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'BtnTGTest')
                    btnTest = fig.UserData.UI.BtnTGTest;
                    if isvalid(btnTest)
                         btnTest.BackgroundColor = [1.0 0.65 0.0]; % amber
                    end
               end
          catch
          end

          % Use tcpclient (no Instrument Control Toolbox required)
          % Step 1: Establish communication with the instrument
          c = tcpclient(ip, port, 'Timeout', 3);
          cleanupObj = onCleanup(@()clear('c'));

          % Step 2: Clear any stale status or error conditions
          try
               writeline(c, '*CLS');
               pause(0.1);
          catch
               % If CLS fails, set button to red and return
               if isvalid(btnTest)
                    btnTest.BackgroundColor = [0.85 0.25 0.25]; % red
               end
               SS_TG5011A_SetLamp(fig, [1 0 0]);
               return;
          end

          % Step 3: Command the instrument to reset
          try
               writeline(c, '*RST');
          catch
               % If reset fails, set button to red and return
               if isvalid(btnTest)
                    btnTest.BackgroundColor = [0.85 0.25 0.25]; % red
               end
               SS_TG5011A_SetLamp(fig, [1 0 0]);
               return;
          end

          % Step 4: Issue *OPC? command - this blocks until reset is complete
          % The instrument will not respond until all operations are finished,
          % then it sends "1\n". MATLAB's readline() blocks until that arrives.
          try
               writeline(c, '*OPC?');
               % Blocking read - waits until instrument sends "1\n"
               opcResponse = strtrim(char(readline(c)));
               % opcResponse should be "1" when reset is complete
          catch
               % If OPC? fails, set button to red and return
               if isvalid(btnTest)
                    btnTest.BackgroundColor = [0.85 0.25 0.25]; % red
               end
               SS_TG5011A_SetLamp(fig, [1 0 0]);
               return;
          end

          % Step 5: Query *IDN? (Manufacturer, Model, Serial, XX.xx–YY.yy–ZZ.zz); show in Instrument ID.
          % Fourth field parsed as Main, Remote, USB Flash Drive revisions.
          try
               writeline(c, '*IDN?');
               pause(0.2);
               if c.NumBytesAvailable > 0
                    idn = strtrim(char(readline(c)));
                    if ~isempty(idn)
                         parts = strsplit(idn, ',');
                         parts = cellfun(@strtrim, parts, 'UniformOutput', false);
                         lines = parts(1:min(3,numel(parts)));
                         if numel(parts) >= 4
                              v = regexp(strtrim(parts{4}), '[\d.]+', 'match');
                              if numel(v) >= 3
                                   lines{end+1} = ['Main: ' v{1}];
                                   lines{end+1} = ['Remote: ' v{2}];
                                   lines{end+1} = ['USB Flash Drive: ' v{3}];
                              else
                                   lines{end+1} = parts{4};
                              end
                         end
                         displayStr = strjoin(lines, newline);
                         setLabelByTag(fig, 'siggen_instrument_id_val', displayStr);
                    else
                         setLabelByTag(fig, 'siggen_instrument_id_val', '—');
                    end
               else
                    setLabelByTag(fig, 'siggen_instrument_id_val', '—');
               end
          catch
               try, setLabelByTag(fig, 'siggen_instrument_id_val', '—'); catch, end
          end

          % Return control to front panel
          try
               writeline(c, 'LOCAL');
               pause(0.2);
          catch
          end

          % Success - set button to green
          if isvalid(btnTest)
               btnTest.BackgroundColor = [0.2 0.7 0.2]; % green
          end
          SS_TG5011A_SetLamp(fig, [0 1 0]);

     catch
          % Failure - set button to red if available
          try
               if isfield(fig.UserData, 'UI') && isfield(fig.UserData.UI, 'BtnTGTest')
                    btnTest = fig.UserData.UI.BtnTGTest;
                    if isvalid(btnTest)
                         btnTest.BackgroundColor = [0.85 0.25 0.25]; % red
                    end
               end
          catch
          end
          SS_TG5011A_SetLamp(fig, [1 0 0]);
          try, setLabelByTag(fig, 'siggen_instrument_id_val', '—'); catch, end
     end
end


function SS_TG5011A_Update(fig)
     % Reads the current Signal Generator pane parameters (inherited + local)
     % and applies them to the TG5011A over TCP.
     %
     % Inherited:
     %   - Fundamental Frequency (Hz) from fig.UserData.physics.f0_hz
     %   - Burst number from fig.UserData.physics.burst_n (display-only today)
     %
     % Local:
     %   - Amplitude (Vpp) from numeric field Tag='siggen_amplitude_val'
     %   - Offset (V)   from numeric field Tag='siggen_offset_val'

     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end

          % Pull IP/port
          ip = '';
          try
               ip = getpref('SmartSwitch','TG5011A_IP');
          catch
               ip = '';
          end

          port = 9221;
          try
               port = getpref('SmartSwitch','TG5011A_PORT');
          catch
               port = 9221;
          end

          if isempty(ip)
               SS_TG5011A_SetLamp(fig, [1 0 0]);
               return;
          end

          % Read inherited physics values
          f0_hz = NaN;
          burst_n = NaN;
          try
               if isstruct(fig.UserData) && isfield(fig.UserData,'physics')
                    phys = fig.UserData.physics;
                    if isfield(phys,'f0_hz')
                         f0_hz = double(phys.f0_hz);
                    end
                    if isfield(phys,'burst_n')
                         burst_n = double(phys.burst_n);
                    end
               end
          catch
          end

          if ~isfinite(f0_hz) || f0_hz <= 0
               % Fall back: attempt to parse display text (numeric only)
               try
                    h = findobj(fig, 'Tag', 'siggen_f0_inherited_val');
                    if ~isempty(h) && isprop(h(1),'Text')
                         f0_display = str2double(regexprep(char(h(1).Text), '[^0-9\.eE\+\-]', ''));
                         if isfinite(f0_display)
                              % NOTE: display is scaled (kHz/MHz label is in the *label*), so this fallback is limited.
                              % Prefer fig.UserData.physics.f0_hz.
                              f0_hz = f0_display;
                         end
                    end
               catch
               end
          end

          % Read local SigGen fields
          amp_vpp = 0.0;
          offs_v  = 0.0;
          try
               hAmp = findobj(fig, 'Tag', 'siggen_amplitude_val');
               if ~isempty(hAmp) && isprop(hAmp(1),'Value')
                    amp_vpp = double(hAmp(1).Value);
               end
          catch
          end
          try
               hOff = findobj(fig, 'Tag', 'siggen_offset_val');
               if ~isempty(hOff) && isprop(hOff(1),'Value')
                    offs_v = double(hOff(1).Value);
               end
          catch
          end
          
          % Fallback: try to parse burst_n from display label if not in physics data
          if ~isfinite(burst_n) || burst_n <= 0
               try
                    hBurst = findobj(fig, 'Tag', 'siggen_burst_mode_val');
                    if ~isempty(hBurst) && isprop(hBurst(1),'Text')
                         burst_display = str2double(regexprep(char(hBurst(1).Text), '[^0-9]', ''));
                         if isfinite(burst_display) && burst_display > 0
                              burst_n = burst_display;
                         end
                    end
               catch
               end
          end

          % Lamp amber while applying
          SS_TG5011A_SetLamp(fig, [0.9 0.7 0.0]);
          
          % Update Connect button to show it's working (amber)
          try
               if isfield(fig.UserData,'UI') && isfield(fig.UserData.UI,'BtnTGConnect')
                    btnConnect = fig.UserData.UI.BtnTGConnect;
                    if ~isempty(btnConnect) && isvalid(btnConnect)
                         btnConnect.BackgroundColor = [0.9 0.7 0.0];  % amber - downloading
                         btnConnect.FontColor = [0 0 0];
                         drawnow('update');
                    end
               end
          catch
          end

          c = tcpclient(ip, port, 'Timeout', 3);
          cleanupObj = onCleanup(@()clear('c'));

          % Initialize instrument: Reset and clear status
          % This must be done first before setting parameters
          try
               configureTerminator(c, "CR/LF");
               flush(c);
               writeline(c, '*RST');
               pause(1.0);  % Longer delay after reset to allow instrument to initialize
               writeline(c, '*CLS');
               pause(0.5);  % Delay after clear status
          catch ME
               % If initialization fails, log but continue
               % Instrument may still be usable
          end

          % Commands for burst operation
          cmds = { ...
               'WAVE SINE', ...
               sprintf('FREQ %.12g', f0_hz), ...
               'AMPUNIT VPP', ...
               sprintf('AMPL %.12g', amp_vpp), ...
               sprintf('DCOFFS %.12g', offs_v), ...
               'BST NCYC', ...
               'BSTTRGSRC INT' ...
          };
          
          % Add burst count (N) command if valid value is available
          if isfinite(burst_n) && burst_n > 0
               cmds{end+1} = sprintf('BSTCOUNT %d', round(burst_n));
          end

          for k = 1:numel(cmds)
               try
                    writeline(c, cmds{k});
               catch
               end
               pause(0.5);
          end

          % Return control to front panel
          try
               writeline(c, 'LOCAL');
               pause(0.2);
          catch
          end

          SS_TG5011A_SetLamp(fig, [0 1 0]);
          
          % Update Connect button to green (success)
          try
               if isfield(fig.UserData,'UI') && isfield(fig.UserData.UI,'BtnTGConnect')
                    btnConnect = fig.UserData.UI.BtnTGConnect;
                    if ~isempty(btnConnect) && isvalid(btnConnect)
                         btnConnect.BackgroundColor = [0.2 0.8 0.2];  % green - success
                         btnConnect.FontColor = [0 0 0];  % black text
                         drawnow('update');
                    end
               end
          catch
          end

     catch
          SS_TG5011A_SetLamp(fig, [1 0 0]);
          
          % Update Connect button to red (failure)
          try
               if isfield(fig.UserData,'UI') && isfield(fig.UserData.UI,'BtnTGConnect')
                    btnConnect = fig.UserData.UI.BtnTGConnect;
                    if ~isempty(btnConnect) && isvalid(btnConnect)
                         btnConnect.BackgroundColor = [0.85 0.25 0.25];  % red - failure
                         btnConnect.FontColor = [1 1 1];  % white text
                         drawnow('update');
                    end
               end
          catch
          end
     end
end



function SS_TG5011A_OutputOn(fig)
     % Backwards-compat wrapper
     SS_TG5011A_ToggleOutput(fig);
end
function SS_TG5011A_SetLamp(fig, rgb)
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end
          if isfield(fig.UserData,'UI') && isfield(fig.UserData.UI,'LampTG5011A')
               lamp = fig.UserData.UI.LampTG5011A;
               if ~isempty(lamp) && isvalid(lamp)
                    lamp.Color = rgb;
               end
          end
     catch
     end

function resp = SS_TG5011A_Query(fig, cmd)
     % Query SCPI command. Command terminated with CRLF; responses typically CRLF terminated.
     resp = '';
     if isempty(fig) || ~isvalid(fig)
          return;
     end
     ok = SS_TG5011A_EnsureConnected(fig);
     if ~ok
          return;
     end

     if ~(endsWith(cmd, char([13 10])) || endsWith(cmd, char(10)))
          cmd = [cmd char([13 10])]; %#ok<AGROW>
     elseif endsWith(cmd, char(10)) && ~endsWith(cmd, char([13 10]))
          cmd = [cmd(1:end-1) char([13 10])]; %#ok<AGROW>
     end

     % Ensure CR/LF terminator and flush stale bytes before the query
     try
          configureTerminator(fig.UserData.TG.tcp, "CR/LF");
     catch
     end
     try
          n = fig.UserData.TG.tcp.NumBytesAvailable;
          if n > 0
               read(fig.UserData.TG.tcp, n, "uint8");
          end
     catch
     end

     write(fig.UserData.TG.tcp, uint8(cmd), "uint8");
     pause(0.25);

     try
          resp = readline(fig.UserData.TG.tcp);
          resp = strtrim(resp);
     catch
          resp = '';
     end
end


function SS_TG5011A_Send(fig, cmd)
     % Send a single SCPI command with CRLF terminator (matches working Python baseline)
     % and include a short delay after each command.
     if isempty(fig) || ~isvalid(fig)
          return;
     end
     ok = SS_TG5011A_EnsureConnected(fig);
     if ~ok
          error('TG5011A not connected');
     end

     if ~(endsWith(cmd, char([13 10])) || endsWith(cmd, char(10)))
          cmd = [cmd char([13 10])]; %#ok<AGROW>
     elseif endsWith(cmd, char(10)) && ~endsWith(cmd, char([13 10]))
          % If LF only, still prefer CRLF
          cmd = [cmd(1:end-1) char([13 10])]; %#ok<AGROW>
     end

     write(fig.UserData.TG.tcp, uint8(cmd), "uint8");
     pause(0.5);
end


function ok = SS_TG5011A_EnsureConnected(fig)
     ok = false;
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end
          if ~isfield(fig.UserData,'TG')
               fig.UserData.TG = struct();
          end
          if isfield(fig.UserData.TG,'tcp')
               t = fig.UserData.TG.tcp;
               try
                    if ~isempty(t) && isvalid(t)
                         ok = true;
                         return;
                    end
               catch
               end
          end

          ip = '';
          try
               ip = getpref('SmartSwitch','TG5011A_IP','');
          catch
               ip = '';
          end
          if isempty(ip)
               return;
          end

          % TG5011A uses raw TCP socket (per working Python baseline)
          port = 9221;
          t = tcpclient(ip, port, 'Timeout', 5.0);
          try
               configureTerminator(t, "CR/LF");
          catch
          end
          fig.UserData.TG.tcp = t;

          ok = true;
     catch
          ok = false;
     end
end

function SS_TG5011A_SyncOutputState(fig, fallbackState)
     % Query OUTPUT? and update stored state + button appearance.
     isOn = fallbackState;
     try
          % Ensure we have IP configured before attempting query
          ip = '';
          try
               ip = getpref('SmartSwitch','TG5011A_IP','');
          catch
          end
          if isempty(ip)
               return;  % No IP configured, can't query
          end
          
          q = SS_TG5011A_Query(fig,':OUTPut?');
          if ~isempty(q)
               qUp = upper(strtrim(q));
               if contains(qUp,'ON') || strcmp(qUp,'1') || contains(qUp,'NORMAL') || contains(qUp,'INVERT')
                    isOn = true;
               elseif contains(qUp,'OFF') || strcmp(qUp,'0')
                    isOn = false;
               end
          end
     catch ME
          % If query fails, keep fallback state
          isOn = fallbackState;
     end

     try
          if ~isfield(fig.UserData,'TG')
               fig.UserData.TG = struct();
          end
          % Always update stored state and button (even if unchanged, to ensure sync)
          oldState = false;
          if isfield(fig.UserData.TG,'OutputIsOn')
               oldState = logical(fig.UserData.TG.OutputIsOn);
          end
          fig.UserData.TG.OutputIsOn = isOn;
          
          % Always update button to ensure it reflects instrument state
          SS_TG5011A_SetOutputButton(fig, isOn);
     catch
     end
end

function SS_TG5011A_SetOutputButton(fig, isOn)
     % Update the output button appearance based on state
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end
          if ~isfield(fig.UserData,'UI') || ~isfield(fig.UserData.UI,'BtnTGOutput')
               return;
          end
          btn = fig.UserData.UI.BtnTGOutput;
          if isempty(btn) || ~isvalid(btn)
               return;
          end
          
          if isOn
               btn.Text = 'Output ON';
               btn.BackgroundColor = [0.2 0.8 0.2];  % green
               btn.FontColor = [0 0 0];  % black text
          else
               btn.Text = 'Output OFF';
               btn.BackgroundColor = [0.85 0.25 0.25];  % red
               btn.FontColor = [1 1 1];  % white text
          end
          drawnow('update');
     catch
     end
end

function SS_TG5011A_ToggleOutput(src, ~)
     % Output toggle callback. src is the button handle.
     fig = [];
     try
          fig = ancestor(src,'figure');
     catch
          fig = [];
     end
     SS_TG5011A_ToggleOutputCore(fig);
end

function SS_TG5011A_ToggleOutputCore(fig)
     try
          if isempty(fig) || ~isvalid(fig)
               return;
          end

          if ~isfield(fig.UserData,'TG')
               fig.UserData.TG = struct();
          end
          if ~isfield(fig.UserData.TG,'OutputIsOn')
               fig.UserData.TG.OutputIsOn = false;
          end

          desiredState = ~logical(fig.UserData.TG.OutputIsOn);

          ok = SS_TG5011A_EnsureConnected(fig);
          if ~ok
               fig.UserData.TG.OutputIsOn = false;
               SS_TG5011A_SetOutputButton(fig, false);
               SS_TG5011A_SetLamp(fig, [1 0 0]);
               return;
          end

          % Known-good command set from working Python baseline
          if desiredState
               SS_TG5011A_Send(fig,':OUTPut ON');
          else
               SS_TG5011A_Send(fig,':OUTPut OFF');
          end
          SS_TG5011A_Send(fig,'LOCAL');

          % Sync UI from instrument response if available
          SS_TG5011A_SyncOutputState(fig, desiredState);
     catch
          try
               fig.UserData.TG.OutputIsOn = false;
               SS_TG5011A_SetOutputButton(fig, false);
               SS_TG5011A_SetLamp(fig, [1 0 0]);
          catch
          end
     end
end


end