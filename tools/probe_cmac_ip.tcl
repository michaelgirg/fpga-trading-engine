set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set part_name [lindex $argv 0]
} elseif {[info exists ::env(MARKET_PARSER_PART)]} {
    set part_name $::env(MARKET_PARSER_PART)
} else {
    set part_name xcu50-fsvh2104-2-e
}

set out_dir [file normalize [file join $repo_root "build" "cmac_ip_probe" $part_name]]
file mkdir $out_dir
set report_path [file join $out_dir "cmac_ip_catalog.txt"]
set report [open $report_path "w"]

proc emit {fh text} {
    puts $text
    puts $fh $text
}

emit $report "Market Parser CMAC/IP catalog probe"
emit $report "Vivado: [version]"
emit $report "Part: $part_name"
emit $report ""

create_project -in_memory -part $part_name
update_ip_catalog

array set seen {}
set matches [list]
foreach pattern [list *cmac* *100g* *ethernet* *eth*] {
    foreach ipdef [get_ipdefs -all -quiet $pattern] {
        set key [string tolower $ipdef]
        if {![info exists seen($key)]} {
            set seen($key) 1
            lappend matches $ipdef
        }
    }
}

if {[llength $matches] == 0} {
    emit $report "No CMAC/100G/Ethernet-like IP definitions matched the probe patterns."
} else {
    emit $report "Matching IP definitions:"
    foreach ipdef [lsort $matches] {
        emit $report "  $ipdef"
    }
}

emit $report ""
emit $report "Report written to $report_path"
close $report
