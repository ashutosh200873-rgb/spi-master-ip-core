# =============================================================================
# sim.do  --  ModelSim Intel FPGA Edition (v10.5b compatible)
# Project : APB-Interfaced SPI Master IP Core
# Fix     : Removed -g2001 flag (Icarus-only, not valid in ModelSim)
# Note    : ModelSim ASE 10.5b does NOT support -cover / vcover commands.
#           Coverage section is commented out -- uncomment only if you have
#           ModelSim PE/SE or Questa-Intel FPGA (21.1+) with a valid license.
# Usage   : ModelSim Transcript > do sim.do
# =============================================================================

# ---- Clean and recreate work library ----
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# ---- Compile RTL ----
# NOTE: No -g2001 flag here. ModelSim's default Verilog parser is already
# Verilog-2001 compatible. SystemVerilog requires explicit -sv flag.
# We intentionally do NOT pass -sv so that any SV syntax causes a compile error.
echo ">>> Compiling RTL..."

vlog ../rtl/apb_slave_interface.v
vlog ../rtl/baud_rate_generator.v
vlog ../rtl/spi_slave_control_select.v
vlog ../rtl/shift_reg.v
vlog ../rtl/spi_master_top.v

# ---- Compile Testbench ----
vlog ../tb/spi_master_tb.v

echo ">>> Compilation done. Starting simulation..."

# ---- Launch Simulation ----
vsim -t 1ps work.spi_master_tb

# ---- Waveform Setup ----
add wave -divider "== APB =="
add wave sim:/spi_master_tb/PCLK
add wave sim:/spi_master_tb/PRESETn
add wave sim:/spi_master_tb/PADDR
add wave sim:/spi_master_tb/PSEL
add wave sim:/spi_master_tb/PENABLE
add wave sim:/spi_master_tb/PWRITE
add wave sim:/spi_master_tb/PWDATA
add wave sim:/spi_master_tb/PRDATA
add wave sim:/spi_master_tb/PREADY
add wave sim:/spi_master_tb/PSLVERR

add wave -divider "== SPI Pins =="
add wave sim:/spi_master_tb/SCLK
add wave sim:/spi_master_tb/MOSI
add wave sim:/spi_master_tb/MISO
add wave sim:/spi_master_tb/SS_N
add wave sim:/spi_master_tb/spi_interrupt_request

add wave -divider "== Block3 FSM =="
add wave sim:/spi_master_tb/dut/u_ctrl_sel/state
add wave sim:/spi_master_tb/dut/u_ctrl_sel/tip
add wave sim:/spi_master_tb/dut/u_ctrl_sel/receive_data
add wave sim:/spi_master_tb/dut/u_ctrl_sel/bit_counter

add wave -divider "== Block4 Shift =="
add wave sim:/spi_master_tb/dut/u_shift_reg/tx_shift
add wave sim:/spi_master_tb/dut/u_shift_reg/rx_shift

add wave -divider "== Baud Flags =="
add wave sim:/spi_master_tb/dut/u_baud_gen/flag_low
add wave sim:/spi_master_tb/dut/u_baud_gen/flags_low
add wave sim:/spi_master_tb/dut/u_baud_gen/flag_high
add wave sim:/spi_master_tb/dut/u_baud_gen/flags_high

# ---- Run Simulation ----
run -all

# ---- Zoom waveform to fit ----
wave zoom full

echo ">>> Simulation complete. Check transcript for PASS/FAIL summary."

# =============================================================================
# COVERAGE SECTION (uncomment ONLY if using Questa-Intel FPGA 21.1+ with license)
# =============================================================================
# To enable coverage: replace the vlog lines above with:
#   vlog -cover bcsf ../rtl/apb_slave_interface.v
#   vlog -cover bcsf ../rtl/baud_rate_generator.v
#   vlog -cover bcsf ../rtl/spi_slave_control_select.v
#   vlog -cover bcsf ../rtl/shift_reg.v
#   vlog -cover bcsf ../rtl/spi_master_top.v
#   vlog              ../tb/spi_master_tb.v
# And replace vsim line with:
#   vsim -coverage -novopt -t 1ps work.spi_master_tb
# After run -all, add:
#   coverage save -code bcfs ../sim/spi_master_cov.ucdb
#   vcover report ../sim/spi_master_cov.ucdb
#   vcover report -details -type statement -output ../sim/rpt_statement.txt ../sim/spi_master_cov.ucdb
#   vcover report -details -type branch    -output ../sim/rpt_branch.txt    ../sim/spi_master_cov.ucdb
#   vcover report -details -type fsm       -output ../sim/rpt_fsm.txt       ../sim/spi_master_cov.ucdb
# =============================================================================
