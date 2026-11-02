# Synthesizes and implements the original and optimized key generators out of
# context on the Nexys A7-100T part, then writes utilization and timing reports.
#
#   cd sha_256_optimized/vivado
#   vivado -mode batch -source compare.tcl                  # 100 MHz target (Nexys A7 clock)
#   vivado -mode batch -source compare.tcl -tclargs 6.0     # tighter target, to find the real Fmax
#
# Reports land in reports/<design>_{utilization,timing}.rpt and a one-line
# summary per design in reports/summary.txt. Achieved Fmax = 1000 / (PERIOD_NS - WNS).

set part      xc7a100tcsg324-1
set period_ns [expr {$argc > 0 ? [lindex $argv 0] : 10.0}]
set here      [file dirname [file normalize [info script]]]
set base      [file normalize "$here/../../sha_256_implementation"]
set opt       [file normalize "$here/.."]
set out       "$here/reports"
file mkdir $out

set designs [list \
    original  top_module_matrix_streaming [list \
        $base/sha_256_pkg.vhd $base/key_matrix_pkg_streaming.vhd $base/chebyshev1.vhd \
        $base/sha_256.vhd $base/top_module_matrix_streaming.vhd] \
    optimized key_stream_top [list \
        $base/sha_256_pkg.vhd $base/key_matrix_pkg_streaming.vhd $opt/modp_pkg.vhd \
        $opt/sha256_core.vhd $opt/chebyshev_modp.vhd $opt/chebyshev_stream.vhd \
        $opt/key_stream_top.vhd] \
]

# Used count from a row of report_utilization, e.g. "| Slice LUTs | 2841 | ..."
proc used {report row} {
    if {[regexp "\\|\\s*$row\\s*\\|\\s*(\\d+)" $report -> n]} { return $n }
    return ?
}

set summary [open "$out/summary.txt" w]
foreach {name top files} $designs {
    close_project -quiet
    create_project -in_memory -part $part
    read_vhdl -vhdl2008 $files
    synth_design -top $top -part $part -mode out_of_context
    create_clock -period $period_ns -name clk [get_ports clk]
    opt_design
    place_design
    route_design

    report_utilization    -file "$out/${name}_utilization.rpt"
    set util [report_utilization -return_string]
    report_timing_summary -file "$out/${name}_timing.rpt"

    set wns  [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set fmax [format %.1f [expr {1000.0 / ($period_ns - $wns)}]]
    set luts [used $util {Slice LUTs\*?}]
    set ffs  [used $util {Slice Registers}]
    set dsps [used $util {DSPs}]
    set line "$name: WNS=${wns} ns  Fmax=${fmax} MHz  LUT=$luts  FF=$ffs  DSP=$dsps"
    puts $line
    puts $summary $line
}
close $summary
