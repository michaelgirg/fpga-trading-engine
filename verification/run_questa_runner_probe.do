onerror {quit -code 1}
cd $probe_root
set probe_dir [file join $probe_root build questa_runner_selftest]
file mkdir $probe_dir
set probe_lib [file join $probe_dir work]
if {![file exists $probe_lib]} {vlib $probe_lib}
vlog -work $probe_lib -sv verification/questa_runner_probe.sv
source verification/questa_test_runner.tcl
set regression_timeout {100 ns}
run_test -lib $probe_lib -GMODE=$probe_mode questa_runner_probe
quit -code 0
