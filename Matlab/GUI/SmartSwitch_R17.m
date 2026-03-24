function SmartSwitch_R17()
% ------------------------------------------------------------
% SmartSwitch (R0) - Main Dashboard (Home) UI skeleton
%
% This revision fixes the "cannot size-reduce" issue.
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

     S = struct();
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
     
     % Ensure minimum width to accommodate fixed-width columns:
     % Physics(320) + Translate(100) + Programming(360) + Signal Gen(420) + spacing(50) = ~1250
     minWidth = 1300;
     if figW < minWidth
          figW = minWidth;
     end
     
     % Center the window on screen (ensuring it doesn't go off-screen)
     figX = max(screenX, screenX + round((screenW - figW) / 2));
     figY = max(screenY, screenY + round((screenH - figH) / 2));

     S.Fig = uifigure( ...
          'Name', 'SmartSwitch', ...
          'Position', [figX figY figW figH], ...
          'Resize', 'on', ...
          'WindowState', 'normal');
     
     % Force layout refresh to ensure all fields are properly sized
     drawnow;

     root = uigridlayout(S.Fig);
     root.RowHeight     = {60, '1x'};
     root.ColumnWidth   = {'1x'};
     root.Padding       = [10 10 10 10];
     root.RowSpacing    = 10;
     root.ColumnSpacing = 10;

     BuildStatusBarLeftOnly(root);
     BuildCardsRow(root, S.Fig);

end

function BuildStatusBarLeftOnly(root)
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
     left.ColumnWidth = {70, 120, 55, 90, 60, 120, 70, 120};
     left.Padding = [0 0 0 0];
     left.ColumnSpacing = 8;

     uilabel(left, 'Text', 'COM Port:', 'HorizontalAlignment', 'right');
     uidropdown(left, 'Items', {'COM4'}, 'Value', 'COM4');

     uilabel(left, 'Text', 'Baud:', 'HorizontalAlignment', 'right');
     uidropdown(left, 'Items', {'9600','115200'}, 'Value', '9600');

     uilabel(left, 'Text', 'Link:', 'HorizontalAlignment', 'right');
     lampLink = uilamp(left);
     lampLink.Color = [0.5 0.5 0.5];

     uilabel(left, 'Text', 'FPGA Alive:', 'HorizontalAlignment', 'right');
     lampAlive = uilamp(left);
     lampAlive.Color = [0.5 0.5 0.5];

end

function BuildCardsRow(root, fig)
     cards = uigridlayout(root);
     cards.Layout.Row = 2;
     cards.Layout.Column = 1;

     cards.RowHeight = {'1x'};
     % Five columns:
     %   [1] Physics (smaller)
     %   [2] Translate button (narrow)
     %   [3] SmartSwitch Programming (smaller)
     %   [4] Signal Generator (fixed/original width)
     %   [5] Spacer (absorbs any extra width so SigGen stays fixed)
     cards.ColumnWidth = {320, 100, 360, '1x', 420};
     cards.Padding = [0 0 0 0];
     cards.ColumnSpacing = 10;

     BuildPhysicsCard(cards, fig);
     BuildTranslateButton(cards, fig);
     BuildProgrammingCard(cards);
     BuildSigGenCard(cards);

end

function BuildTranslateButton(parent, fig)
     host = uigridlayout(parent);
     host.Layout.Row = 1;
     host.Layout.Column = 2;

     host.RowHeight = {'1x', 44, '1x'};
     host.ColumnWidth = {'1x'};
     host.Padding = [0 0 0 0];

     btn = uibutton(host, 'push', 'Text', 'Translate ->');
     btn.Layout.Row = 2;
     btn.Layout.Column = 1;
     btn.Tooltip = 'Translate Physics values into SmartSwitch integer register values.';
     btn.ButtonPushedFcn = @(~,~)OnTranslatePhysicsToRegisters(fig);

end

function OnTranslatePhysicsToRegisters(fig)
     % Mark the figure as having a pending/available translation step.
     if ~isstruct(fig.UserData)
          fig.UserData = struct();
     end
     fig.UserData.TranslatePhysicsToRegisters_Requested = true;

     % If the SmartSwitch pane exposed a handle for its plan/status field,
     % update it now so the button has a visible effect (even before the
     % full translation logic is implemented).
     try
          if isfield(fig.UserData, 'UI') && isstruct(fig.UserData.UI) && isfield(fig.UserData.UI, 'PlanStatusValue')
               if isvalid(fig.UserData.UI.PlanStatusValue)
                    fig.UserData.UI.PlanStatusValue.Text = 'Translate requested (stub)';
               end
          end
     catch
     end

     msg = [ ...
          'This button is the handoff between the Physics pane and the SmartSwitch Programming pane.' newline ...
          newline ...
          'Intended behavior (next step):' newline ...
          '  1) Read the current Physics inputs/derived values.' newline ...
          '  2) Convert timing (us) to integer ticks using the selected CLK DIV / tick duration.' newline ...
          '  3) Populate the SmartSwitch register fields (e.g., clamp start/stop, RX start/stop) with the computed integers.' newline ...
          newline ...
          'At present, this is a stub callback so the layout can be validated first.' ...
          ];

     uialert(fig, msg, 'Translate Physics -> Registers');

end


function BuildPhysicsCard(parent, fig)
     card = uipanel(parent, 'Title', '');
     card.BackgroundColor = [0.92 0.96 1.00];  % pastel blue
     card.Layout.Row = 1;
     card.Layout.Column = 1;

     gl = uigridlayout(card);
     gl.BackgroundColor = card.BackgroundColor;
     gl.RowHeight = {34, 22, 22, 22, 22, 22, 22, 22, 22, '1x', 22, 36};
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
     lblUpdated = uilabel(gl, 'Text', 'Last updated: —', 'HorizontalAlignment', 'left', 'Tag', 'phys_lastupdate_val');
     lblUpdated.Layout.Row = 11;
     lblUpdated.Layout.Column = [1 2];

     btn = uibutton(gl, 'Text', 'Open Physics...', 'ButtonPushedFcn', @(src,evt)openPhysicsDialog(fig));
     btn.Layout.Row = 12;
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
function BuildProgrammingCard(parent)
     card = uipanel(parent, 'Title', '');
     card.BackgroundColor = [0.93 0.98 0.94];  % pastel green
     card.Layout.Row = 1;
     card.Layout.Column = 3;

     gl = uigridlayout(card);
     gl.BackgroundColor = card.BackgroundColor;
     gl.RowHeight = {34, 22, 22, 22, 22, 22, 22, '1x', 36};
     gl.ColumnWidth = {205, '1x'};
     gl.Padding = [10 10 10 10];
     gl.RowSpacing = 6;
     gl.ColumnSpacing = 10;

     hdr = uilabel(gl, 'Text', 'SmartSwitch Programming', 'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
     hdr.Layout.Row = 1;
     hdr.Layout.Column = [1 2];

     AddROField(gl, 2, 'CLK DIV:', '—');
     AddROField(gl, 3, 'Tick (us):', '—');
     AddROField(gl, 4, 'PZT clamp:', '—');
     AddROField(gl, 5, 'RX window:', '—');
     [~, planStatusVal] = AddROField(gl, 6, 'Plan status:', '—');
     AddROField(gl, 7, 'Last verify:', '—');

     % Expose a handle so the Translate button can update the UI.
     fig = ancestor(parent, 'figure');
     if ~isempty(fig) && isvalid(fig)
          if ~isstruct(fig.UserData)
               fig.UserData = struct();
          end
          if ~isfield(fig.UserData, 'UI') || ~isstruct(fig.UserData.UI)
               fig.UserData.UI = struct();
          end
          fig.UserData.UI.PlanStatusValue = planStatusVal;
     end

     lblNote = uilabel(gl, 'Text', 'Notes: —', 'HorizontalAlignment', 'left');
     lblNote.Layout.Row = 8;
     lblNote.Layout.Column = [1 2];

     btn = uibutton(gl, 'Text', 'Open SmartSwitch Programming...');
     btn.Layout.Row = 9;
     btn.Layout.Column = [1 2];

end

% ===== BEGIN SIGNAL GENERATOR PANE =====
function BuildSigGenCard(parent)
     card = uipanel(parent, 'Title', '');
     card.BackgroundColor = [1.00 0.94 0.96];  % pastel pink
     card.Layout.Row = 1;
     card.Layout.Column = 5;

     % Parent grid with two separate boxes and button
     gl = uigridlayout(card);
     gl.BackgroundColor = card.BackgroundColor;
     gl.RowHeight = {'2x', 10, '1x', 36};
     gl.ColumnWidth = {'1x'};
     gl.Padding = [10 10 10 10];
     gl.RowSpacing = 10;
     gl.ColumnSpacing = 10;

     % Box 1: Signal Generator (light pink)
     box1 = uipanel(gl, 'Title', '');
     box1.BackgroundColor = [1.0 0.85 0.90];  % light pink background
     box1.BorderType = 'none';  % We'll draw custom rounded border
     box1.Layout.Row = 1;
     box1.Layout.Column = 1;

     gl_box1 = uigridlayout(box1);
     gl_box1.BackgroundColor = box1.BackgroundColor;
     gl_box1.RowHeight = {24, 22, 22, 22, 22, '1x'};
     gl_box1.ColumnWidth = {205, '1x'};
     gl_box1.Padding = [10 10 10 10];
     gl_box1.RowSpacing = 6;
     gl_box1.ColumnSpacing = 10;

     hdr_box1 = uilabel(gl_box1, 'Text', 'Signal Generator', 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
     hdr_box1.Layout.Row = 1;
     hdr_box1.Layout.Column = [1 2];

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
     val_amp = uieditfield(gl_box1, 'numeric', 'Limits', [-50 50], 'Value', 0, 'Tag', 'siggen_amplitude_val');
     val_amp.Layout.Row = 3;
     val_amp.Layout.Column = 2;

     lab_offset = uilabel(gl_box1, 'Text', 'Offset:', 'HorizontalAlignment', 'left');
     lab_offset.Layout.Row = 4;
     lab_offset.Layout.Column = 1;
     val_offset = uieditfield(gl_box1, 'numeric', 'Limits', [-50 50], 'Value', 0, 'Tag', 'siggen_offset_val');
     val_offset.Layout.Row = 4;
     val_offset.Layout.Column = 2;

     lab_burst = uilabel(gl_box1, 'Text', 'Burst Mode:', 'HorizontalAlignment', 'left');
     lab_burst.Layout.Row = 5;
     lab_burst.Layout.Column = 1;
     val_burst = uilabel(gl_box1, 'Text', '—', 'HorizontalAlignment', 'left', 'Tag', 'siggen_burst_mode_val');
     val_burst.Layout.Row = 5;
     val_burst.Layout.Column = 2;

     % Box 2: Signal Generator Status (darker pink)
     box2 = uipanel(gl, 'Title', '');
     box2.BackgroundColor = [0.95 0.70 0.80];  % darker pink background
     box2.BorderType = 'none';  % We'll draw custom rounded border
     box2.Layout.Row = 3;
     box2.Layout.Column = 1;

     gl_box2 = uigridlayout(box2);
     gl_box2.BackgroundColor = box2.BackgroundColor;
     gl_box2.RowHeight = {24, 22, 22, '1x'};
     gl_box2.ColumnWidth = {205, '1x'};
     gl_box2.Padding = [10 10 10 10];
     gl_box2.RowSpacing = 6;
     gl_box2.ColumnSpacing = 10;

     hdr_box2 = uilabel(gl_box2, 'Text', 'Signal Generator Status', 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'left');
     hdr_box2.Layout.Row = 1;
     hdr_box2.Layout.Column = [1 2];

     lblApplied = uilabel(gl_box2, 'Text', 'Last applied:', 'HorizontalAlignment', 'left');
     lblApplied.Layout.Row = 2;
     lblApplied.Layout.Column = 1;
     val_applied = uilabel(gl_box2, 'Text', '—', 'HorizontalAlignment', 'left');
     val_applied.Layout.Row = 2;
     val_applied.Layout.Column = 2;

     lblStatus1 = uilabel(gl_box2, 'Text', 'Status 1:', 'HorizontalAlignment', 'left');
     lblStatus1.Layout.Row = 3;
     lblStatus1.Layout.Column = 1;
     val_status1 = uilabel(gl_box2, 'Text', '—', 'HorizontalAlignment', 'left');
     val_status1.Layout.Row = 3;
     val_status1.Layout.Column = 2;

     btn = uibutton(gl, 'Text', 'Open Signal Generator...');
     btn.Layout.Row = 4;
     btn.Layout.Column = 1;

     % Draw rounded borders after UI is rendered
     fig = ancestor(parent, 'figure');
     if ~isempty(fig) && isvalid(fig)
          drawnow;  % Ensure UI is rendered first
          % Darker pink border for box 1 (to show against light pink background)
          drawRoundedBorder(box1, [0.90 0.60 0.75], 2, 8);  % darker pink border, 2px width, 8px radius
          % Even darker pink/red border for box 2 (to show against darker pink background)
          drawRoundedBorder(box2, [0.85 0.50 0.65], 2, 8);  % darker pink border, 2px width, 8px radius
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

     d = uifigure('Name', 'Physics', 'Position', [240 220 640 420]);
     d.Resize = 'off';

     

     d.Color = [0.92 0.96 1.00];
g = uigridlayout(d, [8, 3]);
     
     g.BackgroundColor = d.Color;
g.RowHeight = {34, 34, 34, 34, 10, '1x', 12, 40};
     g.ColumnWidth = {240, '1x', 140};
     g.Padding = [16 16 16 16];
     g.RowSpacing = 10;
     g.ColumnSpacing = 12;

     uilabel(g, 'Text', 'Medium');
     ddMedium = uidropdown(g, ...
          'Items', {'De-ionised Water', 'Water', 'Saline', 'Air', 'Custom'}, ...
          'Value', getField(phys, 'medium', 'De-ionised Water'));

     
     ddMedium.Layout.Row = 1;
     ddMedium.Layout.Column = 2;

     % Custom speed of sound (enabled only when Medium = Custom)
     edC = uieditfield(g, 'numeric', ...
          'Limits', [0 inf], ...
          'Value', getField(phys, 'c_mps', 1480));
     edC.Layout.Row = 1;
     edC.Layout.Column = 3;
     edC.Tooltip = 'Speed of sound c (m/s) for Custom medium';
uilabel(g, 'Text', 'Transducer frequency');
     ddF0 = uidropdown(g, ...
          'Items', {'500 kHz', '1 MHz', '2 MHz'}, ...
          'ItemsData', [5e5, 1e6, 2e6], ...
          'Value', getField(phys, 'f0_hz', 1e6));

     ddF0.Layout.Row = 2;
     ddF0.Layout.Column = [2 3];
uilabel(g, 'Text', 'Transducer Active diameter D (mm)');
     ddD = uidropdown(g, ...
          'Items', {'10 mm', '23 mm', '32 mm'}, ...
          'ItemsData', [10, 23, 32], ...
          'Value', getField(phys, 'diam_mm', 23));

     ddD.Layout.Row = 3;
     ddD.Layout.Column = [2 3];


     uilabel(g, 'Text', 'Signal burst number');
     edBurstN = uieditfield(g, 'numeric', ...
          'Limits', [1 inf], ...
          'RoundFractionalValues', 'on', ...
          'Value', getField(phys, 'burst_n', 1));
     edBurstN.Layout.Row = 4;
     edBurstN.Layout.Column = [2 3];
     edBurstN.Tooltip = 'Integer burst number (clamped to 1..floor(Round-trip us))';
info = uitextarea(g, 'Editable', 'off');
     
     info.BackgroundColor = d.Color;
info.Layout.Row = 6;
     info.Layout.Column = [1 3];

     btnRow = uigridlayout(g, [1, 4]);
     
     btnRow.BackgroundColor = d.Color;
btnRow.Layout.Row = 8;
     btnRow.Layout.Column = [1 3];
     btnRow.ColumnWidth = {'1x', 120, 120, 120};
     btnRow.RowHeight = {32};
     btnRow.Padding = [0 0 0 0];
     btnRow.ColumnSpacing = 10;

     uilabel(btnRow, 'Text', '');
     uibutton(btnRow, 'Text', 'Cancel', 'ButtonPushedFcn', @(s,e)delete(d));
     uibutton(btnRow, 'Text', 'Apply',  'ButtonPushedFcn', @(s,e)applyPhysics(false));
     uibutton(btnRow, 'Text', 'OK',     'ButtonPushedFcn', @(s,e)applyPhysics(true));
ddF0.ValueChangedFcn     = @(s,e)refreshDerived();
     ddD.ValueChangedFcn      = @(s,e)refreshDerived();
     edC.ValueChangedFcn       = @(s,e)refreshDerived();

     edBurstN.ValueChangedFcn  = @(s,e)refreshDerived();
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
refreshDerived();

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
          info.Value = { ...
               'Derived (current inputs):', ...
               sprintf('  c = %.1f m/s', c_mps), ...
               sprintf('  lambda = %.6g m', lambda_m), ...
               sprintf('  Rayleigh distance z_R = %.1f mm', zR_m * 1e3), ...
               sprintf('  Round-trip time to z_R = %.1f us', rtt_us), ...
               sprintf('  Burst number = %d (limit 1..%d)', round(edBurstN.Value), maxBurst), ...
               sprintf('  Burst-time round-trip = %.1f us', rtt_us + (1e6/max(ddF0.Value,eps))*round(edBurstN.Value)), ...
               '', ...
               'Definitions:', ...
               '  z_R = a^2 / lambda  (a = D/2)', ...
               '  RTT = 2*z_R / c' ...
          };
     end

     function applyPhysics(closeAfter)
          if nargin < 1
               closeAfter = false;
          end

          phys.medium = ddMedium.Value;
          phys.f0_hz = ddF0.Value;
          phys.diam_mm = ddD.Value;

          phys.burst_n = round(edBurstN.Value);
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
