function crc = crc8_ll5k(data)
% crc8_ll5k  CRC-8 for LL5K protocol
% Poly=0x07, init=0x00, refin=false, refout=false, xorout=0x00
% CRC is computed over bytes OP..payload (SYNC excluded)

crc = uint8(0);

data = uint8(data(:).');   % row vector of uint8

for n = 1:numel(data)
     crc = bitxor(crc, data(n));
     for k = 1:8
          if bitand(crc, uint8(128)) ~= 0
               crc = bitand(bitxor(bitshift(crc, 1), uint8(7)), uint8(255));
          else
               crc = bitand(bitshift(crc, 1), uint8(255));
          end
     end
end
end
