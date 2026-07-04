set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set top_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_TOP)]} {
    set top_name $::env(MARKET_PARSER_TOP)
} else {
    set top_name market_parser_100g_strategy_top
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

if {[info exists ::env(MARKET_PARSER_IMPL_OUT_DIR)]} {
    set out_dir [file normalize $::env(MARKET_PARSER_IMPL_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $repo_root "build" "vivado_impl" $top_name]]
}
file mkdir $out_dir

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
    rtl/market_parser_100g_strategy_impl_harness.sv \
    rtl/market_parser_100g_cmac_axis_impl_harness.sv \
]

puts "Market Parser Vivado implementation timing"
puts "Repo: $repo_root"
puts "Top:  $top_name"
puts "Part: $part_name"
puts "Clock period: $clock_period_ns ns"
puts "Synthesis directive: $synth_directive"
puts "Place directive: $place_directive"
puts "Route directive: $route_directive"
puts "Phys opt directive: $phys_opt_directive"

foreach rtl_file $rtl_files {
    read_verilog -sv [file join $repo_root $rtl_file]
}

set xdc_path [file join $out_dir "impl_constraints.xdc"]
set xdc_file [open $xdc_path "w"]
puts $xdc_file "create_clock -name clk -period $clock_period_ns \[get_ports clk\]"
close $xdc_file
read_xdc $xdc_path

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt -directive $synth_directive
write_checkpoint -force [file join $out_dir "post_synth.dcp"]
report_utilization -file [file join $out_dir "post_synth_utilization.rpt"]
report_timing_summary -file [file join $out_dir "post_synth_timing_summary.rpt"]

opt_design
write_checkpoint -force [file join $out_dir "post_opt.dcp"]

place_design -directive $place_directive
if {$phys_opt_directive ne "" && [string tolower $phys_opt_directive] ne "none"} {
    phys_opt_design -directive $phys_opt_directive
}
write_checkpoint -force [file join $out_dir "post_place.dcp"]
report_timing_summary -file [file join $out_dir "post_place_timing_summary.rpt"]

route_design -directive $route_directive
if {$phys_opt_directive ne "" && [string tolower $phys_opt_directive] ne "none"} {
    phys_opt_design -directive $phys_opt_directive
}
write_checkpoint -force [file join $out_dir "post_route.dcp"]

report_route_status -file [file join $out_dir "route_status.rpt"]
report_drc -file [file join $out_dir "drc.rpt"]
report_utilization -file [file join $out_dir "utilization.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary.rpt"]
report_clock_utilization -file [file join $out_dir "clock_utilization.rpt"]

puts "Vivado implementation reports written to $out_dir"
