# ChatGPT Session Log

Project: UPduino
Topic: Simulink FTDI UART loopback
Date: 2026-01-06

Context:
- MATLAB R2025b
- Instrument Control Toolbox
- FTDI USB-UART
- Verified loopback: HELLO (0x48 0x45 0x4C 0x4C 0x4F 0x0A)

Notes:
- Simulink Serial Send / Receive confirmed working
- Data logged via To Workspace as timeseries
- ASCII conversion must be handled in MATLAB, not Display block
- Display block does not support %c formatting

Transcript / Key Commands:
(paste chat excerpts or commands here)

## Repository Structure Updates

- Created clean Git repo at:
  C:\Users\2923821P\OneDrive - University of Glasgow\Project\Upduino
- Established top-level separation:
  - Simulink/  → host-side models and FTDI tests
  - software/  → UPduino FPGA RTL, testbenches, constraints
- Git does not track empty directories; used .gitkeep placeholders

