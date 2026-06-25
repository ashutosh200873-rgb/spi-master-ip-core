# 🔌 APB-Interfaced SPI Master IP Core

<div align="center">

![Language](https://img.shields.io/badge/Language-Verilog-blue?style=for-the-badge&logo=v)
![Tool](https://img.shields.io/badge/Synthesis-Quartus%20Prime%20Lite-red?style=for-the-badge)
![Sim](https://img.shields.io/badge/Simulation-ModelSim-green?style=for-the-badge)
![Device](https://img.shields.io/badge/Target-Intel%20MAX%2010-orange?style=for-the-badge)
![Tests](https://img.shields.io/badge/Tests-38%2F38%20PASS-brightgreen?style=for-the-badge)


**A fully synthesizable, AMBA APB-interfaced SPI Master IP Core**  
*Designed from scratch in strict Verilog | Verified with 22 directed test cases | Synthesized on Intel MAX 10 FPGA*

</div>

---

## 📋 Table of Contents
- [Overview](#-overview)
- [Features](#-features)
- [Architecture](#-architecture)
- [Register Map](#-register-map)
- [SPI Modes](#-spi-modes)
- [FSM](#-fsm---block-3)
- [File Structure](#-file-structure)
- [Simulation](#-how-to-simulate)
- [Synthesis Results](#-synthesis-results)
- [Waveforms](#-simulation-waveforms)
- [Tools](#-tools-used)

---

## 🔍 Overview

This project implements a complete **SPI Master IP Core** with an **AMBA APB Slave Interface**, designed for SoC integration. The core is partitioned into **4 modular RTL blocks**, each independently verifiable, following industry-standard design practices.

> **Protocol:** Motorola SPI V03.06  
> **Bus Interface:** AMBA APB (Advanced Peripheral Bus)  
> **HDL Standard:** Strict Verilog-2001 (NO SystemVerilog)  
> **Target:** Intel MAX 10 FPGA (10M50DAF484C7G)

---

## ✨ Features

| Feature | Details |
|---------|---------|
| 🕐 **SPI Modes** | All 4 modes — Mode 0, 1, 2, 3 (CPOL/CPHA configurable) |
| ⚡ **Baud Rate** | Programmable: `(SPPR+1) × 2^(SPR+1)` — PCLK/2 to PCLK/2048 |
| 📊 **Data Order** | MSB-first and LSB-first (LSBFE bit) |
| 🔋 **Power Modes** | Run / Wait / Stop with immediate hard clock gating |
| 🛡️ **APB Interface** | Zero-wait-state slave, PSLVERR for illegal addresses |
| 🔔 **Interrupts** | SPIF (transfer complete) + SPTEF (TX buffer empty) |
| ⚠️ **Mode Fault** | MODF detection with auto MSTR demotion |
| 🔄 **Reset** | Asynchronous active-low reset (PRESETn) |

---

## 🏗️ Architecture

```
<img width="2532" height="1044" alt="Screenshot 2026-06-25 125701" src="https://github.com/user-attachments/assets/86cb7640-45c8-4177-b6a6-6d07dbda3212" />
┘
```

### Block Descriptions

| Block | Module | Function |
|-------|--------|----------|
| **Block 1** | `apb_slave_interface.v` | APB slave protocol, 5-register file (SPICR1/2, SPIBR, SPISR, SPIDR), interrupt logic, power mode control |
| **Block 2** | `baud_rate_generator.v` | SCLK generation with Motorola V03.06 formula, hard clock gating, CPOL/CPHA phase flags |
| **Block 3** | `spi_slave_control_select.v` | 3-state FSM (IDLE→TRANSFER→DONE), SS_N control, transfer timing, abort on Stop/Wait |
| **Block 4** | `shift_reg.v` | Serial TX/RX engine, CPHA=0 pre-drive, LSB/MSB-first shifting, MOSI/MISO |

---

## 📝 Register Map

| PADDR | Register | Access | Bit Fields |
|-------|----------|--------|------------|
| `3'h0` | **SPICR1** | R/W | `[7]SPIE [6]SPE [5]SPTIE [4]MSTR [3]CPOL [2]CPHA [1]SSOE [0]LSBFE` |
| `3'h1` | **SPICR2** | R/W | `[7:6]MODE [4]MODFEN [3]BIDIROE [1]SPISWAI [0]SPC0` |
| `3'h2` | **SPIBR** | R/W | `[6:4]SPPR [2:0]SPR` |
| `3'h3` | **SPISR** | R only | `[7]SPIF [5]SPTEF [4]MODF` |
| `3'h4` | **SPIDR** | R/W | Write=TX byte, Read=RX byte |
| `3'h5-7` | Reserved | — | Illegal access → `PSLVERR=1` |

> **MODE field (SPICR2[7:6]):** `00`=RUN `01`=WAIT `10`=STOP `11`=Reserved(STOP)  
> **Reset Default:** STOP mode (safe power-up — no transfers until software enables)

---

## 🔄 SPI Modes

| Mode | CPOL | CPHA | SCLK Idle | Sample Edge | Drive Edge |
|------|------|------|-----------|-------------|------------|
| **Mode 0** | 0 | 0 | LOW | Rising ↑ | Falling ↓ |
| **Mode 1** | 0 | 1 | LOW | Falling ↓ | Rising ↑ |
| **Mode 2** | 1 | 0 | HIGH | Falling ↓ | Rising ↑ |
| **Mode 3** | 1 | 1 | HIGH | Rising ↑ | Falling ↓ |

---

## 🧠 FSM — Block 3

```
                    PRESETn=0 (async)
                         │
              ┌──────────▼──────────┐
    ─────────►│      S_IDLE         │◄─────────────────────────┐
              │      (2'b00)        │◄─────────┐               │
              │  SS_N=1, TIP=0      │          │               │
              └──────────┬──────────┘     STOP/WAIT+SWAI  unconditional
                         │                  (ABORT)      (next cycle)
              send_data=1 AND                  │               │
              mstr=1 AND                       │               │
              run_enable=1                     │               │
                         │            ┌────────┴────────┐      │
                         ▼            │                 │      │
              ┌──────────────────┐    │  S_TRANSFER     │      │
              │   S_TRANSFER     │────┘    (2'b01)      │      │
              │    (2'b01)       │    SS_N=0, TIP=1     │      │
              │  SS_N=0, TIP=1   │                      │      │
              └──────────┬───────┘                      │      │
                         │                              │      │
              bit_counter=7 AND                         │      │
              bit_period_done=1                         │      │
                         │                              │      │
                         ▼                              │      │
              ┌──────────────────┐                      │      │
              │     S_DONE       │──────────────────────┘      │
              │    (2'b10)       │                             │
              │ SS_N=1, TIP=0    │─────────────────────────────┘
              │ receive_data=1   │
              └──────────────────┘
```

---

## 📁 File Structure

```
spi-master-ip-core/
│
├── 📁 rtl/                          # RTL Design Files
│   ├── apb_slave_interface.v        # Block 1: APB Slave + Register File
│   ├── baud_rate_generator.v        # Block 2: SPI Clock Generator
│   ├── spi_slave_control_select.v   # Block 3: Slave Select FSM
│   ├── shift_reg.v                  # Block 4: TX/RX Shift Register
│   └── spi_master_top.v             # Top-Level Integration
│
├── 📁 tb/                           # Verification
│   └── spi_master_tb.v              # 22-test Directed Testbench
│
├── 📁 sim/                          # Simulation Scripts
│   └── sim.do                       # ModelSim run script
│
├── 📁 quartus/                      # Synthesis Project
│   ├── spi_master_ip.qpf            # Quartus Project File
│   ├── spi_master_top.qsf           # Settings File
│   └── spi_master_ip.sdc            # Timing Constraints (50 MHz)
│
├── .gitignore
└── README.md
```

---

## ▶️ How to Simulate

### ModelSim

```tcl
# Open ModelSim, navigate to sim/ folder
cd sim/
do sim.do
```

The script automatically:
1. Compiles all RTL + testbench
2. Launches simulation
3. Adds waveforms
4. Runs all 22 test cases

**Expected Output:**
```
================================================
  SPI Master IP Core - Testbench Summary
================================================
  TOTAL PASS : 38
  TOTAL FAIL : 0
  STATUS     : ALL TESTS PASSED
================================================
```

### Test Cases Coverage

| Test | Description | FSM Path |
|------|-------------|----------|
| T01 | Async Reset | — |
| T02-T03 | APB Register R/W + SPISR no-op | — |
| T04 | Illegal address → PSLVERR | — |
| T05-T08 | All 4 SPI Modes (Mode 0/1/2/3) | IDLE→TRANSFER→DONE |
| T09 | LSB-First transfer | IDLE→TRANSFER→DONE |
| T10-T11 | Edge cases (0x00, 0xFF) | IDLE→TRANSFER→DONE |
| **T12** | **STOP mid-transfer ABORT** | **TRANSFER→IDLE** |
| **T13** | **WAIT+SPISWAI=1 ABORT** | **TRANSFER→IDLE** |
| T14 | WAIT+SPISWAI=0 (continues) | IDLE→TRANSFER→DONE |
| T15 | Write while TIP=1 (blocked) | — |
| **T16** | **Async reset mid-transfer** | **TRANSFER→IDLE** |
| **T17** | **mstr=0 (slave mode blocked)** | **IDLE→IDLE** |
| T18-T19 | SPIF + SPTEF interrupts | — |
| T20 | SPIF 2-step clear sequence | — |
| T21 | Mode fault (MODF) | — |
| T22 | Back-to-back transfers | — |

---

## 📊 Synthesis Results

> **Tool:** Intel Quartus Prime Lite 17.1  
> **Device:** Intel MAX 10 — `10M50DAF484C7G`  
> **Frequency:** 50 MHz

### Timing Analysis (Slow 1200mV 85°C Model)

| Parameter | Result | Status |
|-----------|--------|--------|
| Setup Slack | **+7.340 ns** | ✅ PASS |
| Hold Slack | **+0.340 ns** | ✅ PASS |
| Setup TNS | **0.000 ns** | ✅ No Violations |
| Hold TNS | **0.000 ns** | ✅ No Violations |

### Resource Utilization

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| Logic Elements | **232** | 49,760 | < 1% |
| Registers | **99** | 49,760 | ~0.2% |
| Memory Bits | 0 | 1,677,312 | 0% |
| Multipliers | 0 | — | 0% |

---

## 📸 Simulation Waveforms

### Normal SPI Transfer (Mode 0)
<img width="1694" height="462" alt="Normal Transfer" src="https://github.com/user-attachments/assets/322ec00c-92a0-48b9-a675-c01792a9485b" />

> SS_N asserts → 8 SCLK pulses → SS_N deasserts | FSM: `00→01→10→00`

### Mid-Transfer STOP Abort (T12)
<img width="1156" height="416" alt="Abort T12" src="https://github.com/user-attachments/assets/b0692e71-216c-4602-8862-872160643f8b" />

> STOP mode asserted mid-transfer → SS_N immediately deasserts | FSM: `00→01→00` (S_DONE bypassed)

### Async Reset Mid-Transfer (T16)
<img width="1296" height="416" alt="Async Reset" src="https://github.com/user-attachments/assets/a11f657f-4f03-491f-bc93-7b0820c1942e" />

> PRESETn=0 asserted during transfer → SS_N and SCLK immediately gate off (no clock edge needed)

---

## 🛠️ Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| Intel Quartus Prime Lite | 17.1 | Synthesis + Timing Analysis |
| ModelSim Intel FPGA Edition | 10.5b | Simulation + Verification |




<div align="center">

**Designed as part of B.Tech Project — Electronics & Communication Engineering**

*Strict Verilog-2001 | AMBA APB | Motorola SPI V03.06 | Intel MAX 10*

</div>
