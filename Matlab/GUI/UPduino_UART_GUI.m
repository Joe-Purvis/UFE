% ------------------------------------------------------------
% UPduino_UART_GUI.m
% ------------------------------------------------------------
% Purpose:
%   Simple MATLAB GUI for interactive UART register access on UPduino.
%
% Features:
%   - Connect to UART (COM port, baud)
%   - READ8: specify register address
%   - WRITE8: specify register address + data
%   - Live TX/RX log window
%
% UART framing:
%   Request : 55 OP ADDR DATA CHK
%   Response: 56 STATUS ADDR DATA CHK
%   CHK = XOR of first 4 bytes
%
% Notes:
%   - Uses uifigure (no App Designer required)
%   - No MATLAB section dividers (no %%)
% ------------------------------------------------------------

function UPduino_UART_GUI

     % ----------------------------
     % Defaults
     % ----------------------------
     defaultPort = "COM4";
     defaultBaud = 9600;

     % ----------------------------
     % Build GUI
     % ----------------------------
     fig = uifigure("Name", "UPduino UART Console", ...
                    "Position", [100 100 520 420]);

     uilabel(fig, "Text", "Port:", ...
             "Position", [20 380 50 22]);
     edtPort = uieditfield(fig, "text", ...
             "Position", [70 380 100 22], ...
             "Value", defaultPort);

     uilabel(fig, "Text", "Baud:", ...
             "Position", [190 380 50 22]);
     edtBaud = uieditfield(fig, "numeric", ...
             "Position", [240 380 100 22], ...
             "Value", defaultBaud);

     btnConnect = uibutton(fig, "Text", "Connect", ...
             "Position", [360 378 120 26], ...
             "ButtonPushedFcn", @onConnect);

     % Register controls
     uilabel(fig, "Text", "Register (hex):", ...
             "Position", [20 330 100 22]);
     edtAddr = uieditfield(fig, "text", ...
             "Position", [130 330 80 22], ...
             "Value", "20");

     uilabel(fig, "Text", "Data (hex):", ...
             "Position", [230 330 80 22]);
     edtData = uieditfield(fig, "text", ...
             "Position", [310 330 80 22], ...
             "Value", "0C");

     btnRead = uibutton(fig, "Text", "READ", ...
             "Position", [410 328 80 26], ...
             "Enable", "off", ...
             "ButtonPushedFcn", @onRead);

     btnWrite = uibutton(fig, "Text", "WRITE", ...
             "Position", [410 295 80 26], ...
             "Enable", "off", ...
             "ButtonPushedFcn", @onWrite);

     % Log window
     txtLog = uitextarea(fig, ...
             "Position", [20 20 470 250], ...
             "Editable", "off");

     % ----------------------------
     % State
     % ----------------------------
     s = [];
     cleanupObj = [];

     % ----------------------------
     % Callbacks
     % ----------------------------
     function onConnect(~, ~)
          try
               if ~isempty(s)
                    clear s;
               end

               port = string(edtPort.Value);
               baud = edtBaud.Value;

               s = serialport(port, baud, ...
                    "DataBits", 8, ...
                    "Parity", "none", ...
                    "StopBits", 1);

               configureTerminator(s, uint8(0));
               s.Timeout = 1.0;
               flush(s);

               cleanupObj = onCleanup(@() cleanup_serial());

               btnRead.Enable  = "on";
               btnWrite.Enable = "on";

               log(sprintf("Connected to %s @ %d baud", port, baud));
          catch ME
               log("ERROR: " + ME.message);
          end
     end

     function onRead(~, ~)
          try
               addr = parse_hexbyte(edtAddr.Value);
               rx = read_reg(addr);
               log_rx(rx);

               [ok, msg, status, raddr, rdata] = validate_resp(rx);
               if ok
                    log(sprintf("READ  0x%02X -> 0x%02X  (STATUS=0x%02X)", ...
                         raddr, rdata, status));
               else
                    log("ERROR: " + msg);
               end
          catch ME
               log("ERROR: " + ME.message);
          end
     end

     function onWrite(~, ~)
          try
               addr = parse_hexbyte(edtAddr.Value);
               data = parse_hexbyte(edtData.Value);

               rx = write_reg(addr, data);
               log_rx(rx);

               [ok, msg, status, raddr, rdata] = validate_resp(rx);
               if ok
                    log(sprintf("WRITE 0x%02X <- 0x%02X  (RESP=0x%02X, STATUS=0x%02X)", ...
                         addr, data, rdata, status));
               else
                    log("ERROR: " + msg);
               end
          catch ME
               log("ERROR: " + ME.message);
          end
     end

     % ----------------------------
     % UART helpers
     % ----------------------------
     function rx = read_reg(addr)
          OP_READ8 = uint8(1);
          tx = uint8([hex2dec('55'), OP_READ8, addr, 0, 0]);
          tx(5) = bitxor(bitxor(bitxor(tx(1),tx(2)),tx(3)),tx(4));
          flush(s);
          write(s, tx, "uint8");
          rx = read(s, 5, "uint8");
     end

     function rx = write_reg(addr, data)
          OP_WRITE8 = uint8(2);
          tx = uint8([hex2dec('55'), OP_WRITE8, addr, data, 0]);
          tx(5) = bitxor(bitxor(bitxor(tx(1),tx(2)),tx(3)),tx(4));
          flush(s);
          write(s, tx, "uint8");
          rx = read(s, 5, "uint8");
     end

     % ----------------------------
     % Utilities
     % ----------------------------
     function log(msg)
          txtLog.Value = [txtLog.Value; string(msg)];
          drawnow;
     end

     function log_rx(rx)
          log(sprintf("RX = %02X %02X %02X %02X %02X", rx));
     end

     function b = parse_hexbyte(in)
          in = string(strtrim(in));
          if startsWith(lower(in), "0x")
               v = hex2dec(extractAfter(in,2));
          else
               v = hex2dec(in);
          end
          if v < 0 || v > 255
               error("Value out of range 0..255");
          end
          b = uint8(v);
     end

     function [ok, msg, status, addr, data] = validate_resp(rx)
          ok=false; msg="";
          if numel(rx) ~= 5
               msg="Bad length"; return;
          end
          sof=rx(1); status=rx(2); addr=rx(3); data=rx(4); chk=rx(5);
          if sof ~= hex2dec('56')
               msg="Bad SOF"; return;
          end
          if chk ~= bitxor(bitxor(bitxor(sof,status),addr),data)
               msg="Bad CHK"; return;
          end
          ok=true;
     end

     function cleanup_serial
          try
               flush(s);
          catch
          end
     end

end
