set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set top_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_TOP)]} {
    set top_name $::env(MARKET_PARSER_TOP)
} else {
    set top_name market_parser_100g_cmac_ip_strategy_top
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

if {[info exists ::env(MARKET_PARSER_CMAC_IP_OOC_OUT_DIR)]} {
    set out_dir [file normalize $::env(MARKET_PARSER_CMAC_IP_OOC_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $repo_root "build" "vivado_cmac_ip_ooc" $top_name]]
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
}

proc emit_property {fh obj prop} {
    if {[catch {set value [get_property $prop $obj]} err]} {
        emit $fh [format "  %-48s <unavailable: %s>" $prop $err]
    } else {
        emit $fh [format "  %-48s %s" $prop $value]
    }
}

proc try_set_config {fh obj prop value} {
    set prop_list [list_property $obj]
    if {[lsearch -exact $prop_list $prop] < 0} {
        emit $fh "ERROR: $prop is not present on this IP instance."
        close $fh
        exit 1
    }

    if {[catch {set_property -dict [list $prop $value] $obj} err]} {
        emit $fh "ERROR: failed to set $prop=$value: $err"
        close $fh
        exit 1
    }

    emit $fh "Applied $prop=$value"
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
    rtl/market_parser_multi_symbol_top_of_book.sv \
    rtl/market_parser_100g_strategy_top.sv \
    rtl/market_parser_100g_multi_strategy_top.sv \
    rtl/market_parser_cmac_axis_rx_bridge.sv \
    rtl/market_parser_100g_cmac_axis_strategy_top.sv \
    rtl/market_parser_100g_cmac_ip_strategy_top.sv \
]

puts "Market Parser CMAC IP OOC synthesis"
puts "Repo: $repo_root"
puts "Top:  $top_name"
puts "Part: $part_name"
puts "Clock period: $clock_period_ns ns"
puts "Synthesis directive: $synth_directive"

create_project -force cmac_ip_ooc $project_dir -part $part_name
set_property target_language Verilog [current_project]
update_ip_catalog

set manifest_path [file join $report_dir "cmac_ip_ooc_manifest.txt"]
set manifest [open $manifest_path "w"]
emit $manifest "Market Parser CMAC IP OOC synthesis"
emit $manifest "Vivado: [version]"
emit $manifest "Top: $top_name"
emit $manifest "Part: $part_name"
emit $manifest "Clock period: $clock_period_ns ns"
emit $manifest "Synthesis directive: $synth_directive"
emit $manifest ""

set ipdef [get_ipdefs -all -quiet xilinx.com:ip:cmac_usplus:3.1]
if {[llength $ipdef] == 0} {
    emit $manifest "ERROR: xilinx.com:ip:cmac_usplus:3.1 was not found."
    close $manifest
    exit 1
}

emit $manifest "Selected IP definition:"
emit $manifest "  [lindex $ipdef 0]"
emit $manifest ""

create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.1 \
    -module_name $ip_name -dir $ip_dir

set ip [get_ips $ip_name]
set ip_file [get_property IP_FILE $ip]
set ip_generated_dir [get_property IP_DIR $ip]
emit $manifest "Requested configuration overrides:"
try_set_config $manifest $ip CONFIG.USER_INTERFACE AXIS
try_set_config $manifest $ip CONFIG.ENABLE_AXIS 1
try_set_config $manifest $ip CONFIG.CMAC_CAUI4_MODE 1
try_set_config $manifest $ip CONFIG.NUM_LANES 4x25
try_set_config $manifest $ip CONFIG.INCLUDE_RS_FEC 1
try_set_config $manifest $ip CONFIG.ENABLE_PIPELINE_REG 1
emit $manifest ""

if {[catch {validate_ip $ip} err]} {
    emit $manifest "WARNING: validate_ip failed: $err"
} else {
    emit $manifest "validate_ip completed"
}
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
    CONFIG.ENABLE_PIPELINE_REG \
    CONFIG.RX_FRAME_CRC_CHECKING \
    CONFIG.RX_MAX_PACKET_LEN \
] {
    emit_property $manifest $ip $prop
}
emit $manifest ""

foreach target [list instantiation_template synthesis simulation] {
    if {[catch {generate_target $target $ip} err]} {
        emit $manifest "generate_target $target: failed: $err"
    } else {
        emit $manifest "generate_target $target: ok"
    }
}

emit $manifest ""
emit $manifest "Generated IP files:"
foreach prop [list IP_FILE IP_DIR] {
    emit_property $manifest $ip $prop
}

set ip_stub_file [file join $ip_generated_dir "${ip_name}_bmstub.v"]
set ip_wrapper_file [file join $ip_generated_dir "${ip_name}.v"]
set ip_declaration_file ""
if {[file exists $ip_stub_file]} {
    set ip_declaration_file $ip_stub_file
} elseif {[file exists $ip_wrapper_file]} {
    set ip_declaration_file $ip_wrapper_file
}

emit $manifest ""
if {$ip_declaration_file eq ""} {
    emit $manifest "ERROR: no generated CMAC declaration source found for $ip_name"
    close $manifest
    exit 1
}
set ip_declaration_read_file [file join $report_dir "${ip_name}_declaration_stub.v"]
file copy -force $ip_declaration_file $ip_declaration_read_file
emit $manifest "CMAC declaration source read for wrapper synthesis:"
emit $manifest "  $ip_declaration_file"
emit $manifest "Copied declaration source:"
emit $manifest "  $ip_declaration_read_file"
emit $manifest "Note: this OOC flow validates wrapper ports against a CMAC black box."
close $manifest

read_verilog $ip_declaration_read_file
foreach rtl_file $rtl_files {
    read_verilog -sv [file join $repo_root $rtl_file]
}

set xdc_path [file join $report_dir "cmac_ip_ooc_constraints.xdc"]
set xdc_file [open $xdc_path "w"]
puts $xdc_file "create_clock -name rx_clk -period $clock_period_ns \[get_ports rx_clk\]"
puts $xdc_file "create_clock -name init_clk -period 10.000 \[get_ports init_clk\]"
puts $xdc_file "create_clock -name drp_clk -period 10.000 \[get_ports drp_clk\]"
close $xdc_file
read_xdc $xdc_path

update_compile_order -fileset sources_1
synth_design -top $top_name -part $part_name -mode out_of_context \
    -flatten_hierarchy rebuilt -directive $synth_directive

report_ip_status -file [file join $report_dir "ip_status.rpt"]
report_utilization -file [file join $report_dir "utilization.rpt"]
report_timing_summary -file [file join $report_dir "timing_summary.rpt"]
report_clock_utilization -file [file join $report_dir "clock_utilization.rpt"]
write_checkpoint -force [file join $report_dir "${top_name}.dcp"]

puts "CMAC IP OOC reports written to $report_dir"
