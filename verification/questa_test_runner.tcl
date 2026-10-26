# Bound every configuration, including benches waiting indefinitely on a handshake.
set regression_timeout {5 ms}
set regression_pass_count 0
onbreak {resume}

proc run_test {args} {
    global regression_timeout regression_pass_count
    vsim -onfinish stop {*}$args
    run {*}$regression_timeout
    set status [runStatus -full]
    if {[llength $status] < 3 || [lindex $status 2] ne {$finish}} {
        echo "REGRESSION ERROR: $args did not finish successfully: $status"
        quit -code 1
    }
    incr regression_pass_count
    echo "REGRESSION PASS: $args"
    quit -sim
}
