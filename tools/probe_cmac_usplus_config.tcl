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
set requested_user_interface ""
if {$argc >= 2} {
    set arg1 [string toupper [lindex $argv 1]]
    if {$arg1 eq "AXIS" || $arg1 eq "LBUS"} {
        set requested_user_interface $arg1
    } else {
        set ip_name [lindex $argv 1]
    }
}

if {$argc >= 3} {
    set requested_user_interface [string toupper [lindex $argv 2]]
} elseif {[info exists ::env(MARKET_PARSER_CMAC_USER_INTERFACE)]} {
    set requested_user_interface [string toupper $::env(MARKET_PARSER_CMAC_USER_INTERFACE)]
}

if {$requested_user_interface ne "" &&
    $requested_user_interface ne "AXIS" &&
    $requested_user_interface ne "LBUS"} {
    puts "ERROR: user interface must be AXIS or LBUS, got '$requested_user_interface'"
    exit 1
}

set out_dir [file normalize [file join $repo_root "build" "cmac_ip_probe" $part_name]]
file mkdir $out_dir
set ip_dir [file join $out_dir "ip"]
file mkdir $ip_dir
if {$requested_user_interface eq ""} {
    set report_path [file join $out_dir "cmac_usplus_config.txt"]
} else {
    set report_path [file join $out_dir "cmac_usplus_config_[string tolower $requested_user_interface].txt"]
}
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

proc emit_property_if_present {fh obj prop prop_list} {
    if {[lsearch -exact $prop_list $prop] < 0} {
        emit $fh [format "  %-48s <not present>" $prop]
    } else {
        emit_property $fh $obj $prop
    }
}

proc try_set_config {fh obj prop value prop_list} {
    if {[lsearch -exact $prop_list $prop] < 0} {
        emit $fh "SKIP: $prop is not present on this IP instance."
        return
    }

    if {[catch {set_property -dict [list $prop $value] $obj} err]} {
        emit $fh "WARNING: failed to set $prop=$value: $err"
    } else {
        emit $fh "Applied $prop=$value"
    }
}

emit $report "Market Parser CMAC UltraScale+ config probe"
emit $report "Vivado: [version]"
emit $report "Part: $part_name"
emit $report "IP name: $ip_name"
if {$requested_user_interface eq ""} {
    emit $report "Requested user interface: default"
} else {
    emit $report "Requested user interface: $requested_user_interface"
}
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
set all_props [lsort [list_property $ip]]
if {$requested_user_interface ne ""} {
    emit $report "Requested configuration overrides:"
    try_set_config $report $ip CONFIG.USER_INTERFACE $requested_user_interface $all_props
    if {$requested_user_interface eq "AXIS"} {
        try_set_config $report $ip CONFIG.ENABLE_AXIS 1 $all_props
    }
    emit $report ""

    set all_props [lsort [list_property $ip]]
}

emit $report "Core properties:"
foreach prop $all_props {
    if {[string match "CONFIG.*" $prop]} {
        emit_property $report $ip $prop
    }
}
emit $report ""

emit $report "Non-CONFIG summary properties:"
foreach prop [list IPDEF IP_NAME IP_VERSION IS_LOCKED IS_SYNTH_CHECKPOINT IP_DIR IP_FILE] {
    emit_property_if_present $report $ip $prop $all_props
}
emit $report ""

if {[catch {generate_target instantiation_template $ip} err]} {
    emit $report "Instantiation template generation failed: $err"
} else {
    emit $report "Generated instantiation template under:"
    emit $report "  [file join $ip_dir $ip_name]"
    set template_dir [file join $ip_dir $ip_name]
    set template_files [concat \
        [glob -nocomplain -directory $template_dir *.veo] \
        [glob -nocomplain -directory $template_dir *.vho]]
    if {[llength $template_files] > 0} {
        emit $report "Instantiation template files:"
        foreach template_file [lsort $template_files] {
            emit $report "  $template_file"
        }
    }
}

emit $report ""
emit $report "Report written to $report_path"
close $report
