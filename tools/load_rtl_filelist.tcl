proc market_parser_read_rtl_filelist {repo_root} {
    set filelist_path [file join $repo_root "filelist.f"]
    if {![file exists $filelist_path]} {
        error "RTL file list not found: $filelist_path"
    }

    set rtl_files [list]
    set filelist [open $filelist_path "r"]
    while {[gets $filelist line] >= 0} {
        set entry [string trim $line]
        if {$entry eq "" || [string match "#*" $entry]} {
            continue
        }
        if {[string match "rtl/*.sv" $entry]} {
            lappend rtl_files $entry
        }
    }
    close $filelist

    if {[llength $rtl_files] == 0} {
        error "No RTL sources found in $filelist_path"
    }
    return $rtl_files
}
