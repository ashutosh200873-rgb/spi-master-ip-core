create_clock -name PCLK -period 20.000 [get_ports PCLK]
set_false_path -from [get_ports PRESETn]
set_false_path -to   [get_ports SCLK]
set_false_path -to   [get_ports MOSI]
set_false_path -to   [get_ports SS_N]
set_false_path -from [get_ports MISO]
# Constrain all remaining I/O ports (APB interface)
set_false_path -from [all_inputs]
set_false_path -to   [all_outputs]