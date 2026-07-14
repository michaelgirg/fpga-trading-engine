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

set requested_num_lanes ""
if {$argc >= 4} {
    set requested_num_lanes [lindex $argv 3]
} elseif {[info exists ::env(MARKET_PARSER_CMAC_NUM_LANES)]} {
    set requested_num_lanes $::env(MARKET_PARSER_CMAC_NUM_LANES)
}

set out_dir [file normalize [file join $repo_root "build" "cmac_ip_probe" $part_name]]
file mkdir $out_dir
set ip_dir [file join $out_dir "ip"]
file mkdir $ip_dir
set report_suffix ""
if {$requested_user_interface ne ""} {
    append report_suffix "_[string tolower $requested_user_interface]"
}
if {$requested_num_lanes ne ""} {
    set lane_suffix [string map {"/" "_" " " "_"} [string tolower $requested_num_lanes]]
    append report_suffix "_$lane_suffix"
}
set report_path [file join $out_dir "cmac_usplus_config${report_suffix}.txt"]
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
        return 0
    }

    if {[catch {set_property -dict [list $prop $value] $obj} err]} {
        emit $fh "WARNING: failed to set $prop=$value: $err"
        return 0
    } else {
        emit $fh "Applied $prop=$value"
        return 1
    }
}

proc emit_legal_values {fh obj prop prop_list} {
    if {[lsearch -exact $prop_list $prop] < 0} {
        emit $fh "Legal values for $prop: <property not present>"
        return
    }

    if {[catch {set values [list_property_value -quiet $prop $obj]} err]} {
        emit $fh "Legal values for $prop: <unavailable: $err>"
    } elseif {[llength $values] == 0} {
        emit $fh "Legal values for $prop: <not enumerated>"
    } else {
        emit $fh "Legal values for $prop: $values"
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
if {$requested_num_lanes eq ""} {
    emit $report "Requested lane profile: default"
} else {
    emit $report "Requested lane profile: $requested_num_lanes"
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
set config_ok 1
if {$requested_user_interface ne ""} {
    emit $report "Requested configuration overrides:"
    if {![try_set_config $report $ip CONFIG.USER_INTERFACE $requested_user_interface $all_props]} {
        set config_ok 0
    }
    if {$requested_user_interface eq "AXIS"} {
        if {![try_set_config $report $ip CONFIG.ENABLE_AXIS 1 $all_props]} {
            set config_ok 0
        }
    }
    set all_props [lsort [list_property $ip]]
}

if {$requested_num_lanes ne ""} {
    if {$requested_user_interface eq ""} {
        emit $report "Requested configuration overrides:"
    }

    set normalized_num_lanes [string tolower $requested_num_lanes]
    if {$normalized_num_lanes eq "4x25"} {
        emit_legal_values $report $ip CONFIG.CMAC_CAUI4_MODE $all_props
        if {![try_set_config $report $ip CONFIG.CMAC_CAUI4_MODE 1 $all_props]} {
            set config_ok 0
        }
        set all_props [lsort [list_property $ip]]
    } elseif {$normalized_num_lanes eq "10x10"} {
        if {![try_set_config $report $ip CONFIG.CMAC_CAUI4_MODE 0 $all_props]} {
            set config_ok 0
        }
        set all_props [lsort [list_property $ip]]
    }

    emit_legal_values $report $ip CONFIG.NUM_LANES $all_props
    if {![try_set_config $report $ip CONFIG.NUM_LANES $requested_num_lanes $all_props]} {
        set config_ok 0
    }
    set all_props [lsort [list_property $ip]]
}

if {$requested_user_interface ne "" || $requested_num_lanes ne ""} {
    emit $report ""
}

if {!$config_ok} {
    emit $report "ERROR: one or more requested CMAC properties were not applied."
    close $report
    exit 1
}

if {[catch {validate_ip $ip} err]} {
    emit $report "ERROR: validate_ip failed: $err"
    close $report
    exit 1
} else {
    emit $report "validate_ip completed"
    emit $report ""
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
