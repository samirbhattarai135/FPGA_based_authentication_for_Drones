####################################################################################
## FPGA Constraints File for Key Generator
## 
## This file contains pin assignments and timing constraints for the FPGA
## implementation of the key generation system.
##
## Target Boards (uncomment the section for your board):
##   - Basys3 (Artix-7 35T)
##   - Nexys A7-50T / A7-100T
##   - Arty A7-35T / A7-100T
####################################################################################

####################################################################################
## BASYS3 BOARD CONSTRAINTS
## Uncomment this section for Basys3
####################################################################################

## Clock (100 MHz)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK100MHZ]

## Reset (BTNU - mapped to CPU_RESETN)
set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]

## Buttons
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports BTNC]
set_property -dict { PACKAGE_PIN T17  IOSTANDARD LVCMOS33 } [get_ports BTNU]
set_property -dict { PACKAGE_PIN U17  IOSTANDARD LVCMOS33 } [get_ports BTND]

## Switches
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {SW[0]}]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {SW[1]}]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports {SW[2]}]
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports {SW[3]}]
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports {SW[4]}]
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports {SW[5]}]
set_property -dict { PACKAGE_PIN W14  IOSTANDARD LVCMOS33 } [get_ports {SW[6]}]
set_property -dict { PACKAGE_PIN W13  IOSTANDARD LVCMOS33 } [get_ports {SW[7]}]
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports {SW[8]}]
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports {SW[9]}]
set_property -dict { PACKAGE_PIN T2   IOSTANDARD LVCMOS33 } [get_ports {SW[10]}]
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports {SW[11]}]
set_property -dict { PACKAGE_PIN W2   IOSTANDARD LVCMOS33 } [get_ports {SW[12]}]
set_property -dict { PACKAGE_PIN U1   IOSTANDARD LVCMOS33 } [get_ports {SW[13]}]
set_property -dict { PACKAGE_PIN T1   IOSTANDARD LVCMOS33 } [get_ports {SW[14]}]
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports {SW[15]}]

## LEDs
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {LED[0]}]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {LED[1]}]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports {LED[2]}]
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports {LED[3]}]
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports {LED[4]}]
set_property -dict { PACKAGE_PIN U15  IOSTANDARD LVCMOS33 } [get_ports {LED[5]}]
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports {LED[6]}]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {LED[7]}]
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports {LED[8]}]
set_property -dict { PACKAGE_PIN V3   IOSTANDARD LVCMOS33 } [get_ports {LED[9]}]
set_property -dict { PACKAGE_PIN W3   IOSTANDARD LVCMOS33 } [get_ports {LED[10]}]
set_property -dict { PACKAGE_PIN U3   IOSTANDARD LVCMOS33 } [get_ports {LED[11]}]
set_property -dict { PACKAGE_PIN P3   IOSTANDARD LVCMOS33 } [get_ports {LED[12]}]
set_property -dict { PACKAGE_PIN N3   IOSTANDARD LVCMOS33 } [get_ports {LED[13]}]
set_property -dict { PACKAGE_PIN P1   IOSTANDARD LVCMOS33 } [get_ports {LED[14]}]
set_property -dict { PACKAGE_PIN L1   IOSTANDARD LVCMOS33 } [get_ports {LED[15]}]

## 7-Segment Display Segments
set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports {SEG[0]}]
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports {SEG[1]}]
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports {SEG[2]}]
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports {SEG[3]}]
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports {SEG[4]}]
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports {SEG[5]}]
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports {SEG[6]}]

## 7-Segment Display Decimal Point
set_property -dict { PACKAGE_PIN V7   IOSTANDARD LVCMOS33 } [get_ports DP]

## 7-Segment Display Anodes
set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports {AN[0]}]
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports {AN[1]}]
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports {AN[2]}]
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports {AN[3]}]


####################################################################################
## NEXYS A7 BOARD CONSTRAINTS (50T/100T)
## Uncomment this section for Nexys A7
####################################################################################

## Clock (100 MHz)
# set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
# create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK100MHZ]

## Reset (CPU_RESETN)
# set_property -dict { PACKAGE_PIN C12  IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]

## Buttons
# set_property -dict { PACKAGE_PIN E16  IOSTANDARD LVCMOS33 } [get_ports BTNC]
# set_property -dict { PACKAGE_PIN F15  IOSTANDARD LVCMOS33 } [get_ports BTNU]
# set_property -dict { PACKAGE_PIN V10  IOSTANDARD LVCMOS33 } [get_ports BTND]

## Switches (SW0-SW15)
# set_property -dict { PACKAGE_PIN J15  IOSTANDARD LVCMOS33 } [get_ports {SW[0]}]
# set_property -dict { PACKAGE_PIN L16  IOSTANDARD LVCMOS33 } [get_ports {SW[1]}]
# set_property -dict { PACKAGE_PIN M13  IOSTANDARD LVCMOS33 } [get_ports {SW[2]}]
# set_property -dict { PACKAGE_PIN R15  IOSTANDARD LVCMOS33 } [get_ports {SW[3]}]
# set_property -dict { PACKAGE_PIN R17  IOSTANDARD LVCMOS33 } [get_ports {SW[4]}]
# set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports {SW[5]}]
# set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports {SW[6]}]
# set_property -dict { PACKAGE_PIN R13  IOSTANDARD LVCMOS33 } [get_ports {SW[7]}]
# set_property -dict { PACKAGE_PIN T8   IOSTANDARD LVCMOS18 } [get_ports {SW[8]}]
# set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS18 } [get_ports {SW[9]}]
# set_property -dict { PACKAGE_PIN R16  IOSTANDARD LVCMOS33 } [get_ports {SW[10]}]
# set_property -dict { PACKAGE_PIN T13  IOSTANDARD LVCMOS33 } [get_ports {SW[11]}]
# set_property -dict { PACKAGE_PIN H6   IOSTANDARD LVCMOS33 } [get_ports {SW[12]}]
# set_property -dict { PACKAGE_PIN U12  IOSTANDARD LVCMOS33 } [get_ports {SW[13]}]
# set_property -dict { PACKAGE_PIN U11  IOSTANDARD LVCMOS33 } [get_ports {SW[14]}]
# set_property -dict { PACKAGE_PIN V10  IOSTANDARD LVCMOS33 } [get_ports {SW[15]}]

## LEDs (LED0-LED15)
# set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports {LED[0]}]
# set_property -dict { PACKAGE_PIN K15  IOSTANDARD LVCMOS33 } [get_ports {LED[1]}]
# set_property -dict { PACKAGE_PIN J13  IOSTANDARD LVCMOS33 } [get_ports {LED[2]}]
# set_property -dict { PACKAGE_PIN N14  IOSTANDARD LVCMOS33 } [get_ports {LED[3]}]
# set_property -dict { PACKAGE_PIN R18  IOSTANDARD LVCMOS33 } [get_ports {LED[4]}]
# set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {LED[5]}]
# set_property -dict { PACKAGE_PIN U17  IOSTANDARD LVCMOS33 } [get_ports {LED[6]}]
# set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {LED[7]}]
# set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {LED[8]}]
# set_property -dict { PACKAGE_PIN T15  IOSTANDARD LVCMOS33 } [get_ports {LED[9]}]
# set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports {LED[10]}]
# set_property -dict { PACKAGE_PIN T16  IOSTANDARD LVCMOS33 } [get_ports {LED[11]}]
# set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports {LED[12]}]
# set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {LED[13]}]
# set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports {LED[14]}]
# set_property -dict { PACKAGE_PIN V11  IOSTANDARD LVCMOS33 } [get_ports {LED[15]}]

## 7-Segment Display Segments
# set_property -dict { PACKAGE_PIN T10  IOSTANDARD LVCMOS33 } [get_ports {SEG[0]}]
# set_property -dict { PACKAGE_PIN R10  IOSTANDARD LVCMOS33 } [get_ports {SEG[1]}]
# set_property -dict { PACKAGE_PIN K16  IOSTANDARD LVCMOS33 } [get_ports {SEG[2]}]
# set_property -dict { PACKAGE_PIN K13  IOSTANDARD LVCMOS33 } [get_ports {SEG[3]}]
# set_property -dict { PACKAGE_PIN P15  IOSTANDARD LVCMOS33 } [get_ports {SEG[4]}]
# set_property -dict { PACKAGE_PIN T11  IOSTANDARD LVCMOS33 } [get_ports {SEG[5]}]
# set_property -dict { PACKAGE_PIN L18  IOSTANDARD LVCMOS33 } [get_ports {SEG[6]}]

## 7-Segment Display Decimal Point
# set_property -dict { PACKAGE_PIN H15  IOSTANDARD LVCMOS33 } [get_ports DP]

## 7-Segment Display Anodes
# set_property -dict { PACKAGE_PIN J17  IOSTANDARD LVCMOS33 } [get_ports {AN[0]}]
# set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports {AN[1]}]
# set_property -dict { PACKAGE_PIN T9   IOSTANDARD LVCMOS33 } [get_ports {AN[2]}]
# set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports {AN[3]}]


####################################################################################
## TIMING CONSTRAINTS
####################################################################################

## Input delay constraints (relative to clock)
set_input_delay -clock [get_clocks sys_clk_pin] -min 0.000 [get_ports -filter { NAME =~ "*" && DIRECTION == "IN" }]
set_input_delay -clock [get_clocks sys_clk_pin] -max 2.000 [get_ports -filter { NAME =~ "*" && DIRECTION == "IN" }]

## Output delay constraints (relative to clock)
set_output_delay -clock [get_clocks sys_clk_pin] -min -1.000 [get_ports -filter { NAME =~ "*" && DIRECTION == "OUT" }]
set_output_delay -clock [get_clocks sys_clk_pin] -max 2.000 [get_ports -filter { NAME =~ "*" && DIRECTION == "OUT" }]

## Clock uncertainty
set_clock_uncertainty -setup 0.200 [get_clocks sys_clk_pin]
set_clock_uncertainty -hold 0.100 [get_clocks sys_clk_pin]

####################################################################################
## CONFIGURATION SETTINGS
####################################################################################

## Configuration bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Bitstream settings
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

####################################################################################
## FALSE PATH CONSTRAINTS (for asynchronous inputs)
####################################################################################

## Button inputs are asynchronous - mark as false paths
set_false_path -from [get_ports CPU_RESETN]
set_false_path -from [get_ports BTNC]
set_false_path -from [get_ports BTNU]
set_false_path -from [get_ports BTND]

## Switch inputs are asynchronous
set_false_path -from [get_ports {SW[*]}]

## LED outputs don't need tight timing
set_false_path -to [get_ports {LED[*]}]
set_false_path -to [get_ports {AN[*]}]
set_false_path -to [get_ports {SEG[*]}]
set_false_path -to [get_ports DP]
