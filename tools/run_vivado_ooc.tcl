set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
source [file join $script_dir "load_rtl_filelist.tcl"]

if {$argc >= 1} {
    set top_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_TOP)]} {
    set top_name $::env(MARKET_PARSER_TOP)
} else {
    set top_name market_parser_512_pipeline
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
    set synth_directive Default
}

set out_dir [file normalize [file join $repo_root "build" "vivado_ooc" $top_name]]
file mkdir $out_dir

set rtl_files [market_parser_read_rtl_filelist $repo_root]

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
