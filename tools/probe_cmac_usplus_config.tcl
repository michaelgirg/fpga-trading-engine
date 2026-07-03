set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set part_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_PART)]} {
    set part_name $::env(MARKET_PARSER_PART)
} else {
    set part_name xcu50-fsvh2104-2-e
}

set ip_name cmac_usplus_0
if {$argc >= 2} {
    set ip_name [lindex $argv 1]
}

set out_dir [file normalize [file join $repo_root "build" "cmac_ip_probe" $part_name]]
file mkdir $out_dir
set ip_dir [file join $out_dir "ip"]
file mkdir $ip_dir
set report_path [file join $out_dir "cmac_usplus_config.txt"]
set report [open $report_path "w"]

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

emit $report "Market Parser CMAC UltraScale+ config probe"
emit $report "Vivado: [version]"
emit $report "Part: $part_name"
emit $report "IP name: $ip_name"
emit $report ""

create_project -in_memory -part $part_name
update_ip_catalog

set ipdef [get_ipdefs -all -quiet xilinx.com:ip:cmac_usplus:3.1]
if {[llength $ipdef] == 0} {
    emit $report "ERROR: xilinx.com:ip:cmac_usplus:3.1 was not found in the Vivado IP catalog."
    close $report
    exit 1
}

emit $report "Selected IP definition:"
emit $report "  [lindex $ipdef 0]"
emit $report ""

if {[catch {
    create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.1 \
        -module_name $ip_name -dir $ip_dir
} err]} {
    emit $report "ERROR: create_ip failed: $err"
    close $report
    exit 1
}

set ip [get_ips $ip_name]
emit $report "Core properties:"
foreach prop [lsort [list_property $ip]] {
    if {[string match "CONFIG.*" $prop]} {
        emit_property $report $ip $prop
    }
}
emit $report ""

emit $report "Non-CONFIG summary properties:"
foreach prop [list IPDEF IP_NAME IP_VERSION IS_LOCKED IS_SYNTH_CHECKPOINT IP_DIR IP_FILE] {
    emit_property $report $ip $prop
}
emit $report ""

if {[catch {generate_target instantiation_template $ip} err]} {
    emit $report "Instantiation template generation failed: $err"
} else {
    emit $report "Generated instantiation template under:"
    emit $report "  [file join $ip_dir $ip_name]"
}

emit $report ""
emit $report "Report written to $report_path"
close $report
