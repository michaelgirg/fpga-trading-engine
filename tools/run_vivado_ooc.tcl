set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set top_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_TOP)]} {
    set top_name $::env(MARKET_PARSER_TOP)
} else {
    set top_name market_parser_512_system
}

if {$argc >= 2} {
    set part_name [lindex $argv 1]
} elseif {[info exists ::env(MARKET_PARSER_PART)]} {
    set part_name $::env(MARKET_PARSER_PART)
} else {
    set part_name xc7z020clg484-1
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
    set synth_directive Default
}

set out_dir [file normalize [file join $repo_root "build" "vivado_ooc" $top_name]]
file mkdir $out_dir

set rtl_files [list \
    rtl/market_parser_pkg.sv \
    rtl/market_parser.sv \
    rtl/market_parser_axis_adapter.sv \
    rtl/market_parser_64.sv \
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
]

puts "Market Parser Vivado OOC synthesis"
puts "Repo: $repo_root"
puts "Top:  $top_name"
puts "Part: $part_name"
puts "Clock period: $clock_period_ns ns"
puts "Synthesis directive: $synth_directive"

foreach rtl_file $rtl_files {
    read_verilog -sv [file join $repo_root $rtl_file]
}

set xdc_path [file join $out_dir "ooc_constraints.xdc"]
set xdc_file [open $xdc_path "w"]
puts $xdc_file "create_clock -name clk -period $clock_period_ns \[get_ports clk\]"
close $xdc_file
read_xdc $xdc_path

synth_design -top $top_name -part $part_name -mode out_of_context -flatten_hierarchy rebuilt -directive $synth_directive

report_utilization -file [file join $out_dir "utilization.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary.rpt"]
report_clock_utilization -file [file join $out_dir "clock_utilization.rpt"]
write_checkpoint -force [file join $out_dir "${top_name}.dcp"]

puts "Vivado OOC reports written to $out_dir"
