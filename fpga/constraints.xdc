# Nexys A7-100T Constraints
# Only pins fot rtl/top.sv

set_property PACKAGE_PIN E3    [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.00 -name clk [get_ports clk]

# RESET (CPU_RESET button)
set_property PACKAGE_PIN C12   [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# START (BTNC)
set_property PACKAGE_PIN E16   [get_ports start]
set_property IOSTANDARD LVCMOS33 [get_ports start]

# WR_EN_A/B (Pmod/switches - FIXED names)
set_property PACKAGE_PIN G17   [get_ports wr_en_a]
set_property PACKAGE_PIN G19   [get_ports wr_en_b]
set_property IOSTANDARD LVCMOS33 [get_ports wr_en_*]

# WR_ADDR[7:0] (Pmod JA3-10)
set_property PACKAGE_PIN {N18 L18 T18 P17 R17 P18 R18 W19} [get_ports {wr_addr[*]}]

# WR_DATA[127:0] → SW0-15 (demo subset)
set_property PACKAGE_PIN {J15 L16 J17 J18 T9 H17 T10 T11} [get_ports {wr_data[127:120]}]
set_property IOSTANDARD LVCMOS33 [get_ports {wr_data[*]}]

# RD_ROW/COL (BTNA/D)
set_property PACKAGE_PIN {D19 D20} [get_ports {rd_row[1:0]}]
set_property PACKAGE_PIN {C20 E18} [get_ports {rd_col[1:0]}]

# OUTPUTS: RESULT/DONE/ERROR → LEDs 0-7
set_property PACKAGE_PIN {U16 E19 U19 V19 W7 W17 W15 U8} \
    [get_ports {result[47:40] done error_detected controller_error sa_error}]

set_property IOSTANDARD LVCMOS33 [all_ports]

# TIMING (100MHz target)
set_input_delay -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]
set_false_path -from [get_ports rst_n]

puts "Constraints valid for [get_property PART [current_project]]"