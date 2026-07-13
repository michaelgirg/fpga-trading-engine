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
} elseif {[info exists ::env(MARKET_PARSER_CMAC_IP_NAME)]} {
    set ip_name $::env(MARKET_PARSER_CMAC_IP_NAME)
} else {
    set ip_name cmac_usplus_0
}

if {[info exists ::env(MARKET_PARSER_CMAC_IP_OUT_DIR)]} {
    set out_dir [file normalize $::env(MARKET_PARSER_CMAC_IP_OUT_DIR)]
} else {
    set out_dir [file normalize [file join $repo_root "build" "cmac_usplus_axis_ip" $part_name]]
}

set verbose_inventory 0
if {[info exists ::env(MARKET_PARSER_CMAC_VERBOSE_INVENTORY)]} {
    set value [string tolower $::env(MARKET_PARSER_CMAC_VERBOSE_INVENTORY)]
    if {$value eq "1" || $value eq "true" || $value eq "yes"} {
        set verbose_inventory 1
    }
}

set project_dir [file join $out_dir "project"]
set ip_dir [file join $out_dir "ip"]
set ip_instance_dir [file join $ip_dir $ip_name]
set manifest_path [file join $out_dir "cmac_usplus_axis_manifest.txt"]

file mkdir $out_dir
file mkdir $project_dir
file mkdir $ip_dir
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
        emit $fh "SKIP: $prop is not present on this IP instance."
        return
    }

    if {[catch {set_property -dict [list $prop $value] $obj} err]} {
        emit $fh "ERROR: failed to set $prop=$value: $err"
        close $fh
        exit 1
    }

    emit $fh "Applied $prop=$value"
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

set manifest [open $manifest_path "w"]

emit $manifest "Market Parser CMAC UltraScale+ AXIS IP build"
emit $manifest "Vivado: [version]"
emit $manifest "Part: $part_name"
emit $manifest "IP name: $ip_name"
emit $manifest "Output directory: $out_dir"
emit $manifest ""

create_project -force cmac_usplus_axis_ip $project_dir -part $part_name
set_property target_language Verilog [current_project]
update_ip_catalog

set ipdef [get_ipdefs -all -quiet xilinx.com:ip:cmac_usplus:3.1]
if {[llength $ipdef] == 0} {
    emit $manifest "ERROR: xilinx.com:ip:cmac_usplus:3.1 was not found in the Vivado IP catalog."
    close $manifest
    exit 1
}

emit $manifest "Selected IP definition:"
emit $manifest "  [lindex $ipdef 0]"
emit $manifest ""

if {[catch {
    create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.1 \
        -module_name $ip_name -dir $ip_dir
} err]} {
    emit $manifest "ERROR: create_ip failed: $err"
    close $manifest
    exit 1
}

set ip [get_ips $ip_name]

emit $manifest "Requested configuration overrides:"
try_set_config $manifest $ip CONFIG.USER_INTERFACE AXIS
try_set_config $manifest $ip CONFIG.ENABLE_AXIS 1
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

emit $manifest "Generated targets:"
foreach target [list instantiation_template synthesis simulation] {
    if {[catch {generate_target $target $ip} err]} {
        emit $manifest "  $target: failed: $err"
    } else {
        emit $manifest "  $target: ok"
    }
}

if {[catch {export_ip_user_files -of_objects $ip -no_script -sync -force -quiet} err]} {
    emit $manifest "export_ip_user_files: failed: $err"
} else {
    emit $manifest "export_ip_user_files: ok"
}

emit $manifest ""
emit $manifest "Important generated files:"
foreach prop [list IP_FILE IP_DIR] {
    emit_property $manifest $ip $prop
}

set template_files [concat \
    [glob -nocomplain -directory $ip_instance_dir *.veo] \
    [glob -nocomplain -directory $ip_instance_dir *.vho]]
if {[llength $template_files] > 0} {
    emit $manifest "  instantiation templates:"
    foreach template_file [lsort $template_files] {
        emit $manifest "    $template_file"
    }
}
emit $manifest ""

emit $manifest "AXIS RX handoff expected by repo RTL:"
emit $manifest "  rx_axis_tvalid"
emit $manifest "  rx_axis_tdata[511:0]"
emit $manifest "  rx_axis_tkeep[63:0]"
emit $manifest "  rx_axis_tlast"
emit $manifest "  rx_axis_tuser"
emit $manifest "  no rx_axis_tready on the generated CMAC RX side"
emit $manifest ""
emit $manifest "Repo-side receive boundary:"
emit $manifest "  market_parser_100g_cmac_axis_strategy_top"
emit $manifest "  market_parser_100g_cmac_axis_impl_harness"
emit $manifest "  market_parser_100g_cmac_ip_impl_harness"
emit $manifest ""

set generated_files [lsort [list_files_recursive $out_dir]]
emit $manifest "Generated file inventory:"
emit $manifest "  total files: [llength $generated_files]"
if {$verbose_inventory} {
    foreach generated_file $generated_files {
        emit $manifest "  $generated_file"
    }
} else {
    emit $manifest "  set MARKET_PARSER_CMAC_VERBOSE_INVENTORY=1 to list every generated file"
}

emit $manifest ""
emit $manifest "Manifest written to $manifest_path"
close $manifest

puts "CMAC UltraScale+ AXIS IP build artifacts written to $out_dir"
