set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set part_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_PART)]} {
    set part_name $::env(MARKET_PARSER_PART)
} else {
    set part_name xcu50-fsvh2104-2-e
}

if {$argc >= 2} {
    set ip_name [lindex $argv 1]
} else {
    set ip_name cmac_usplus_0
}

set out_dir [file normalize [file join $repo_root "build" "cmac_placement_probe" $part_name]]
set project_dir [file join $out_dir "project"]
set ip_dir [file join $out_dir "ip"]
set ip_instance_dir [file join $ip_dir $ip_name]
set report_path [file join $out_dir "cmac_usplus_placement.txt"]

file mkdir $out_dir
file mkdir $project_dir
file mkdir $ip_dir
if {[file exists $ip_instance_dir]} {
    file delete -force $ip_instance_dir
}

proc emit {fh text} {
    puts $text
    puts $fh $text
    flush $fh
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

proc emit_property_and_legal_values {fh obj prop} {
    if {[catch {set value [get_property $prop $obj]} err]} {
        emit $fh "$prop"
        emit $fh "  current: <unavailable: $err>"
    } else {
        emit $fh "$prop"
        emit $fh "  current: $value"
    }

    if {[catch {set values [list_property_value -quiet $prop $obj]} err]} {
        emit $fh "  legal: <unavailable: $err>"
    } elseif {[llength $values] == 0} {
        emit $fh "  legal: <not enumerated by Vivado>"
    } else {
        emit $fh "  legal: $values"
    }
}

proc list_files_recursive {root} {
    set result [list]
    foreach item [glob -nocomplain -directory $root *] {
        if {[file isdirectory $item]} {
            set result [concat $result [list_files_recursive $item]]
        } else {
            lappend result $item
        }
    }
    return $result
}

set report [open $report_path "w"]

emit $report "Market Parser CMAC UltraScale+ CAUI-4 placement probe"
emit $report "Vivado: [version]"
emit $report "Part: $part_name"
emit $report "IP name: $ip_name"
emit $report ""

create_project -force cmac_placement_probe $project_dir -part $part_name
set_property target_language Verilog [current_project]
update_ip_catalog

set ipdef [get_ipdefs -all -quiet xilinx.com:ip:cmac_usplus:3.1]
if {[llength $ipdef] == 0} {
    emit $report "ERROR: xilinx.com:ip:cmac_usplus:3.1 was not found."
    close $report
    error "CMAC UltraScale+ IP is unavailable"
}

create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.1 \
    -module_name $ip_name -dir $ip_dir

set ip [get_ips $ip_name]
emit $report "Requested production configuration:"
require_config $report $ip CONFIG.USER_INTERFACE AXIS
require_config $report $ip CONFIG.ENABLE_AXIS 1
require_config $report $ip CONFIG.CMAC_CAUI4_MODE 1
require_config $report $ip CONFIG.NUM_LANES 4x25
require_config $report $ip CONFIG.GT_REF_CLK_FREQ 161.1328125
require_config $report $ip CONFIG.CMAC_CORE_SELECT CMACE4_X0Y4
require_config $report $ip CONFIG.GT_GROUP_SELECT X0Y28~X0Y31
require_config $report $ip CONFIG.LANE1_GT_LOC X0Y28
require_config $report $ip CONFIG.LANE2_GT_LOC X0Y29
require_config $report $ip CONFIG.LANE3_GT_LOC X0Y30
require_config $report $ip CONFIG.LANE4_GT_LOC X0Y31
require_config $report $ip CONFIG.INCLUDE_RS_FEC 1
require_config $report $ip CONFIG.ENABLE_PIPELINE_REG 1
emit $report ""

if {[catch {validate_ip $ip} err]} {
    emit $report "ERROR: validate_ip failed: $err"
    close $report
    error "CMAC IP validation failed"
}
emit $report "validate_ip completed"
emit $report ""

emit $report "CAUI-4 CMAC/GT placement properties:"
set matched_props [list]
foreach prop [lsort [list_property $ip]] {
    if {[regexp {^CONFIG\.(CMAC_CORE_SELECT|GT_GROUP_SELECT|GT_LOCATION|GT_REF_CLK_FREQ|INCLUDE_SHARED_LOGIC|LANE[0-9]+_GT_LOC)$} $prop]} {
        lappend matched_props $prop
        emit_property_and_legal_values $report $ip $prop
    }
}
if {[llength $matched_props] == 0} {
    emit $report "  <no placement properties matched>"
}
emit $report ""

emit $report "Relevant device site inventory:"
foreach site_pattern [list \
    CMACE4_* \
    GTYE4_CHANNEL_* \
    GTYE4_COMMON_* \
    IBUFDS_GTE4_* \
] {
    set sites [lsort [get_sites -quiet $site_pattern]]
    emit $report "  $site_pattern"
    if {[llength $sites] == 0} {
        emit $report "    <none>"
    } else {
        emit $report "    $sites"
    }
}
emit $report ""

emit $report "Generating CMAC synthesis output products for XDC inspection..."
if {[catch {generate_target synthesis $ip} err]} {
    emit $report "ERROR: synthesis target generation failed: $err"
    close $report
    error "CMAC synthesis target generation failed"
}
emit $report "synthesis target generation completed"
emit $report ""

emit $report "Generated XDC placement-related lines:"
set xdc_count 0
set match_count 0
foreach generated_file [lsort [list_files_recursive $ip_instance_dir]] {
    if {![string equal -nocase [file extension $generated_file] ".xdc"]} {
        continue
    }

    incr xdc_count
    set file_match_count 0
    set input [open $generated_file "r"]
    set line_number 0
    while {[gets $input line] >= 0} {
        incr line_number
        if {[regexp -nocase {LOC|PACKAGE_PIN|IBUFDS_GTE4|CMACE4|GTYE4_(CHANNEL|COMMON)} $line]} {
            if {$file_match_count == 0} {
                emit $report "  FILE: $generated_file"
            }
            emit $report "    $line_number: $line"
            incr file_match_count
            incr match_count
        }
    }
    close $input
}
if {$xdc_count == 0} {
    emit $report "  <no generated XDC files found>"
} elseif {$match_count == 0} {
    emit $report "  <no matching placement lines found in $xdc_count XDC files>"
}
emit $report ""

emit $report "Interpretation:"
emit $report "  The requested CMAC core and GT lanes match the Xilinx OpenNIC Alveo U50 profile."
emit $report "  Full implementation must also constrain gt_ref_clk_p/n to U50 package pins N36/N37."
emit $report ""
emit $report "Report written to $report_path"
close $report

puts "CMAC placement probe written to $report_path"
