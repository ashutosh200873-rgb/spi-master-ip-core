# APB-Interfaced SPI Master IP Core

A fully synthesizable SPI Master IP Core implemented.

## Features
- AMBA APB Slave Interface
- All 4 SPI Modes (CPOL/CPHA)
- Programmable Baud Rate: (SPPR+1) x 2^(SPR+1)
- Run / Wait / Stop Power Modes
- LSB/MSB First Support
- 22-test Directed Testbench (38/38 PASS)

## Tools
- Simulation: ModelSim Intel FPGA Edition
- Synthesis: Quartus Prime Lite (Intel MAX 10)

## Structure
- rtl/     - Verilog RTL files
- tb/      - Testbench
- sim/     - ModelSim scripts
- quartus/ - Quartus project files
