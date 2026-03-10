#!/usr/bin/env tclsh

proc main {N} {
    if {$N == ""} { set N 16 }
    puts "=== SystolicArray N=[expr $N*$N] on Nexys A7-100T ==="

    file mkdir reports bitstreams
    
    if {[llength [get_projects]] > 0} { close_project }
    file delete -force vivado_${N}x${N}
    
    create_project systolic_${N}x${N} ./vivado_${N}x${N} -part xc7a100tcsg324-1 -force
    
    add_files -norecurse {
        rtl/bram.sv
        rtl/controller.sv
        rtl/pe.sv
        rtl/systolic_array.sv
        rtl/top.sv
    }
    set_property top top [current_fileset]
    set_property file_type SystemVerilog [get_files *.sv]
    add_files -fileset constrs_1 fpga/constraints.xdc

    set_property generic "N=$N DATA_WIDTH=8 ACCUM_WIDTH=48 DEPTH=256 ADDR_WIDTH=8" \
        [get_filesets sources_1]

    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    open_run synth_1
    report_utilization -file reports/synth_N${N}.rpt

    set period 10.0  ;# 100MHz
    set fd [open temp_xdc.xdc w]
    puts $fd "create_clock -period $period -name clk \[get_ports clk\]"
    puts $fd "set_input_delay -clock clk 2.0 \[all_inputs\]"
    puts $fd "set_output_delay -clock clk 2.0 \[all_outputs\]"
    puts $fd "set_false_path -from \[get_ports rst_n\]"
    close $fd
    
    add_files -fileset constrs_1 temp_xdc.xdc
    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1

    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    set fmax [expr {1000.0 / $period * (1.0 + $wns / $period)}]
    set luts [report_property UTILIZATION [get_runs impl_1] LUTS]
    
    set fd [open reports/metrics_N${N}.txt w]
    puts $fd "N=${N} @ Nexys A7-100T"
    puts $fd "Fmax: [format %.1f $fmax] MHz (WNS=$wns ns)"
    puts $fd "Bitstream: ./vivado_${N}x${N}/systolic_${N}x${N}.runs/impl_1/top.bit"
    close $fd
    
    puts "\nN=${N} Fmax=[format %.1f $fmax]MHz | Bitstream ready"
}

main $::argv
