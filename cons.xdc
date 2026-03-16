# =====================================================
# Nexys A7 - TRNG Project Constraints
# Clock = 100 MHz
# =====================================================

# -------------------------------
# Clock input (100 MHz)
# -------------------------------
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]


# Create 100 MHz clock constraint
create_clock -period 10.000 -name sys_clk [get_ports clk]


# -------------------------------
# Reset
# -------------------------------
set_property PACKAGE_PIN V10 [get_ports rst]


# -------------------------------
# LEDs
# -------------------------------
set_property PACKAGE_PIN V14 [get_ports {led[3]}]
set_property PACKAGE_PIN V15 [get_ports {led[2]}]
set_property PACKAGE_PIN T16 [get_ports {led[1]}]
set_property PACKAGE_PIN U14 [get_ports {led[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_out]


# -------------------------------
# TRNG Ring Oscillator
# Allow intentional combinational loops
# -------------------------------
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical *ro_out*]
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical]
set_property DONT_TOUCH true [get_cells -hierarchical *RO_BLOCK*]

set_property PACKAGE_PIN D4 [get_ports uart_tx_out]
