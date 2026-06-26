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

set out_dir [file normalize [file join $repo_root "build" "vivado_ooc" $top_name]]
file mkdir $out_dir

set rtl_files [list \
    rtl/market_parser_pkg.sv \
    rtl/market_parser.sv \
    rtl/market_parser_axis_adapter.sv \
    rtl/market_parser_64.sv \
    rtl/market_parser_100g_ingress.sv \
    rtl/market_parser_512_boundary_scan.sv \
    rtl/market_parser_512_frontend.sv \
    rtl/market_parser_512_event_extract.sv \
    rtl/market_parser_512_window_buffer.sv \
    rtl/market_parser_512_pipeline.sv \
    rtl/market_parser_event_fifo.sv \
    rtl/market_parser_512_pipeline_fifo.sv \
    rtl/market_parser_axi_lite_regs.sv \
    rtl/market_parser_512_system.sv \
]

puts "Market Parser Vivado OOC synthesis"
puts "Repo: $repo_root"
puts "Top:  $top_name"
puts "Part: $part_name"

foreach rtl_file $rtl_files {
    read_verilog -sv [file join $repo_root $rtl_file]
}

synth_design -top $top_name -part $part_name -mode out_of_context -flatten_hierarchy rebuilt

report_utilization -file [file join $out_dir "utilization.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary.rpt"]
report_clock_utilization -file [file join $out_dir "clock_utilization.rpt"]
write_checkpoint -force [file join $out_dir "${top_name}.dcp"]

puts "Vivado OOC reports written to $out_dir"
