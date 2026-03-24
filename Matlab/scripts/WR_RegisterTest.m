clear; clc;

port = "COM4";
baud = 9600;

op   = uint8(0x01);   % 0x01=READ8, 0x02=WRITE8
addr = uint8(0x30);
data = uint8(0x00);   % for WRITE8, set this to your value

s = serialport(port, baud, "DataBits", 8, "Parity", "none", "StopBits", 1);
configureTerminator(s, uint8(0));
s.Timeout = 1.0;
flush(s);

chk = bitxor(bitxor(bitxor(uint8(0x55), op), addr), data);
tx  = uint8([0x55 op addr data chk]);

write(s, tx, "uint8");
pause(0.1);

% Sync on 0x56 response header
sof = [];
for k = 1:200
     b = read(s, 1, "uint8");
     if b == uint8(0x56)
          sof = b;
          break;
     end
end

if isempty(sof)
     clear s;
     error("No 0x56 start-of-frame seen.");
end

rest = read(s, 4, "uint8");
rx   = [uint8(sof) rest(:)'];

clear s;

disp("TX (hex):");
disp(upper(join(string(dec2hex(tx,2)),' ')));
disp("RX (hex):");
disp(upper(join(string(dec2hex(rx,2)),' ')));

% Parse response
status = rx(2);
raddr  = rx(3);
rdata  = rx(4);
rchk   = rx(5);

fprintf("status=0x%02X addr=0x%02X data=0x%02X chk=0x%02X\n", status, raddr, rdata, rchk);
