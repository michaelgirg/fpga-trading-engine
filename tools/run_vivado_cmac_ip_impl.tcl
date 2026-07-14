set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set top_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_TOP)]} {
    set top_name $::env(MARKET_PARSER_TOP)
} else {
    set top_name market_parser_100g_cmac_ip_impl_harness
}

if {$argc >= 2} {
    set part_name [lindex $argv 1]
} elseif {[info exists ::env(MARKET_PARSER_PART)]} {
    set part_name $::env(MARKET_PARSER_PART)
} else {
    set part_name xcu50-fsvh2104-2-e
}

if {$argc >= 3} {
    set clock_period_ns [lindex $argv 2]
} elseif {[info exists ::env(MARKET_PARSER_CLOCK_PERIOD_NS)]} {
    set clock_period_ns $::env(MARKET_PARSER_CLOCK_PERIOD_NS)
} else {
    set clock_period_ns 3.102
}

if {$argc >= 4} {
    set synth_directive [lindex $argv 3]
} elseif {[info exists ::env(MARKET_PARSER_SYNTH_DIRECTIVE)]} {
    set synth_directive $::env(MARKET_PARSER_SYNTH_DIRECTIVE)
} else {
    set synth_directive RuntimeOptimized
}

if {$argc >= 5} {
    set place_directive [lindex $argv 4]
} elseif {[info exists ::env(MARKET_PARSER_PLACE_DIRECTIVE)]} {
    set place_directive $::env(MARKET_PARSER_PLACE_DIRECTIVE)
} else {
    set place_directive Explore
}

if {$argc >= 6} {
    set route_directive [lindex $argv 5]
} elseif {[info exists ::env(MARKET_PARSER_ROUTE_DIRECTIVE)]} {
    set route_directive $::env(MARKET_PARSER_ROUTE_DIRECTIVE)
} else {
    set route_directive Explore
}

if {$argc >= 7} {
    set phys_opt_directive [lindex $argv 6]
} elseif {[info exists ::env(MARKET_PARSER_PHYS_OPT_DIRECTIVE)]} {
    set phys_opt_directive $::env(MARKET_PARSER_PHYS_OPT_DIRECTIVE)
} else {
    set phys_opt_directive Explore
}

if {$argc >= 8} {
    set jobs [lindex $argv 7]
} elseif {[info exists ::env(MARKET_PARSER_VIVADO_JOBS)]} {
    set jobs $::env(MARKET_PARSER_VIVADO_JOBS)
} else {
    set jobs 8
}

if {[info exists ::env(MARKET_PARSER_CMAC_IP_IMPL_OUT_DIR)]} {
    set out_dir [file normalize $::env(MARKET_PARSER_CMAC_IP_IMPL_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $repo_root "build" "vivado_cmac_ip_impl" $top_name]]
}

set project_dir [file join $out_dir "project"]
set ip_dir [file join $out_dir "ip"]
set report_dir [file join $out_dir "reports"]
set ip_name cmac_usplus_0
set ip_instance_dir [file join $ip_dir $ip_name]

file mkdir $out_dir
file mkdir $project_dir
file mkdir $ip_dir
file mkdir $report_dir
if {[file exists $ip_instance_dir]} {
    file delete -force $ip_instance_dir
}

proc emit {fh text} {
    puts $text
    puts $fh $text
    flush $fh
}

proc emit_property {fh obj prop} {
    if {[catch {set value [get_property $prop $obj]} err]} {
        emit $fh [format "  %-48s <unavailable: %s>" $prop $err]
    } else {
        emit $fh [format "  %-48s %s" $prop $value]
    }
}

proc require_config {fh obj prop value} {
    if {[lsearch -exact [list_property $obj] $prop] < 0} {
        emit $fh "ERROR: $prop is not present on this IP instance."
        close $fh
        error "Required CMAC property is unavailable: $prop"
    }

    if {[catch {set_property -dict [list $prop $value] $obj} err]} {
        emit $fh "ERROR: failed to set $prop=$value: $err"
        close $fh
        error "Failed to configure CMAC property $prop"
    }

    emit $fh "Applied $prop=$value"
}

proc require_completed_run {fh run_obj label} {
    set progress [get_property PROGRESS $run_obj]
    set status [get_property STATUS $run_obj]
    emit $fh "$label progress: $progress"
    emit $fh "$label status: $status"

    if {$progress ne "100%" || [regexp -nocase {error|fail} $status]} {
        close $fh
        error "$label did not complete successfully: $status ($progress)"
    }
}

set rtl_files [list \
    rtl/market_parser_pkg.sv \
    rtl/market_parser.sv \
    rtl/market_parser_axis_adapter.sv \
    rtl/market_parser_64.sv \
    rtl/market_parser_axis_register_slice.sv \
    rtl/market_parser_100g_ingress.sv \
    rtl/market_parser_udp_payload_strip.sv \
    rtl/market_parser_512_boundary_scan.sv \
    rtl/market_parser_512_frontend.sv \
    rtl/market_parser_512_event_extract.sv \
    rtl/market_parser_512_window_buffer.sv \
    rtl/market_parser_512_pipeline.sv \
    rtl/market_parser_event_fifo.sv \
    rtl/market_parser_512_pipeline_fifo.sv \
    rtl/market_parser_axi_lite_regs.sv \
    rtl/market_parser_512_system.sv \
    rtl/market_parser_100g_cmac_system.sv \
    rtl/market_parser_top_of_book.sv \
    rtl/market_parser_100g_strategy_top.sv \
    rtl/market_parser_cmac_axis_rx_bridge.sv \
    rtl/market_parser_100g_cmac_axis_strategy_top.sv \
    rtl/market_parser_100g_cmac_ip_strategy_top.sv \
    rtl/market_parser_100g_cmac_ip_impl_harness.sv \
]

set manifest_path [file join $report_dir "cmac_ip_impl_manifest.txt"]
set manifest [open $manifest_path "w"]

emit $manifest "Market Parser full CMAC IP implementation"
emit $manifest "Vivado: [version]"
emit $manifest "Top: $top_name"
emit $manifest "Part: $part_name"
emit $manifest "RX clock period: $clock_period_ns ns"
emit $manifest "Synthesis directive: $synth_directive"
emit $manifest "Place directive: $place_directive"
emit $manifest "Route directive: $route_directive"
emit $manifest "Physical optimization directive: $phys_opt_directive"
emit $manifest "Parallel jobs: $jobs"
emit $manifest ""

create_project -force cmac_ip_impl $project_dir -part $part_name
set_property target_language Verilog [current_project]
update_ip_catalog

set ipdef [get_ipdefs -all -quiet xilinx.com:ip:cmac_usplus:3.1]
if {[llength $ipdef] == 0} {
    emit $manifest "ERROR: xilinx.com:ip:cmac_usplus:3.1 was not found."
    close $manifest
    error "CMAC UltraScale+ IP is unavailable"
}

emit $manifest "Selected IP definition:"
emit $manifest "  [lindex $ipdef 0]"
emit $manifest ""

create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.1 \
    -module_name $ip_name -dir $ip_dir

set ip [get_ips $ip_name]
emit $manifest "Requested configuration overrides:"
require_config $manifest $ip CONFIG.USER_INTERFACE AXIS
require_config $manifest $ip CONFIG.ENABLE_AXIS 1
require_config $manifest $ip CONFIG.CMAC_CAUI4_MODE 1
require_config $manifest $ip CONFIG.NUM_LANES 4x25
emit $manifest ""

if {[catch {validate_ip $ip} err]} {
    emit $manifest "ERROR: validate_ip failed: $err"
    close $manifest
    error "CMAC IP validation failed"
}
emit $manifest "validate_ip completed"
emit $manifest ""

emit $manifest "Resolved CMAC configuration:"
foreach prop [list \
    CONFIG.USER_INTERFACE \
    CONFIG.ENABLE_AXIS \
    CONFIG.CMAC_CAUI4_MODE \
    CONFIG.CLOCKING_MODE \
    CONFIG.GT_TYPE \
    CONFIG.GT_REF_CLK_FREQ \
    CONFIG.NUM_LANES \
    CONFIG.INCLUDE_RS_FEC \
    CONFIG.RX_FRAME_CRC_CHECKING \
    CONFIG.RX_MAX_PACKET_LEN \
] {
    emit_property $manifest $ip $prop
}
emit $manifest ""

generate_target all $ip
export_ip_user_files -of_objects $ip -no_script -sync -force -quiet
create_ip_run $ip

set ip_run [get_runs -quiet "${ip_name}_synth_1"]
if {[llength $ip_run] == 0} {
    emit $manifest "ERROR: Vivado did not create ${ip_name}_synth_1."
    close $manifest
    error "CMAC IP synthesis run was not created"
}

emit $manifest "Launching full CMAC IP synthesis: $ip_run"
launch_runs $ip_run -jobs $jobs
wait_on_run $ip_run
require_completed_run $manifest $ip_run "CMAC IP synthesis"
emit $manifest ""

foreach rtl_file $rtl_files {
    add_files -fileset sources_1 -norecurse [file join $repo_root $rtl_file]
}
set_property top $top_name [get_filesets sources_1]

set xdc_path [file join $report_dir "cmac_ip_impl_constraints.xdc"]
set xdc_file [open $xdc_path "w"]
puts $xdc_file "create_clock -name rx_clk -period $clock_period_ns \[get_ports rx_clk\]"
puts $xdc_file "create_clock -name init_clk -period 10.000 \[get_ports init_clk\]"
puts $xdc_file "create_clock -name drp_clk -period 10.000 \[get_ports drp_clk\]"
puts $xdc_file "set_clock_groups -asynchronous -group \[get_clocks rx_clk\] -group \[get_clocks init_clk\] -group \[get_clocks drp_clk\]"
close $xdc_file
add_files -fileset constrs_1 -norecurse $xdc_path

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set synth_run [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt $synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE $synth_directive $synth_run

emit $manifest "Launching integrated top-level synthesis: $synth_run"
launch_runs $synth_run -jobs $jobs
wait_on_run $synth_run
require_completed_run $manifest $synth_run "Integrated top-level synthesis"
emit $manifest ""

open_run $synth_run

set black_boxes [get_cells -hierarchical -quiet -filter {IS_BLACKBOX == 1}]
set black_box_report [open [file join $report_dir "black_boxes.rpt"] "w"]
puts $black_box_report "Black box cells after integrated synthesis: [llength $black_boxes]"
foreach black_box $black_boxes {
    puts $black_box_report $black_box
}
close $black_box_report
emit $manifest "Black box cells after integrated synthesis: [llength $black_boxes]"
if {[llength $black_boxes] != 0} {
    emit $manifest "ERROR: integrated synthesis still contains black boxes."
    close $manifest
    error "Integrated CMAC design contains black boxes"
}

report_ip_status -file [file join $report_dir "ip_status.rpt"]
report_utilization -file [file join $report_dir "post_synth_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_synth_timing_summary.rpt"]
write_checkpoint -force [file join $report_dir "post_synth.dcp"]

emit $manifest "Starting implementation"
opt_design
write_checkpoint -force [file join $report_dir "post_opt.dcp"]

place_design -directive $place_directive
if {$phys_opt_directive ne "" && [string tolower $phys_opt_directive] ne "none"} {
    phys_opt_design -directive $phys_opt_directive
}
write_checkpoint -force [file join $report_dir "post_place.dcp"]
report_timing_summary -file [file join $report_dir "post_place_timing_summary.rpt"]

route_design -directive $route_directive
if {$phys_opt_directive ne "" && [string tolower $phys_opt_directive] ne "none"} {
    phys_opt_design -directive $phys_opt_directive
}
write_checkpoint -force [file join $report_dir "post_route.dcp"]

report_route_status -file [file join $report_dir "route_status.rpt"]
report_drc -file [file join $report_dir "drc.rpt"]
report_methodology -file [file join $report_dir "methodology.rpt"]
report_utilization -file [file join $report_dir "utilization.rpt"]
report_timing_summary -file [file join $report_dir "timing_summary.rpt"]
report_clock_utilization -file [file join $report_dir "clock_utilization.rpt"]

emit $manifest "Implementation completed"
emit $manifest "Reports: $report_dir"
close $manifest

puts "Full CMAC IP implementation reports written to $report_dir"
