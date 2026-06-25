cd ..
vlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv rtl/market_parser_axis_adapter.sv rtl/market_parser_64.sv verification/market_parser_tb.sv verification/market_parser_64_tb.sv verification/market_parser_axis_adapter_tb.sv
vsim -onfinish stop market_parser_tb
run -all
quit -sim
vsim -onfinish stop market_parser_64_tb
run -all
quit -sim
vsim -onfinish stop -GDATA_WIDTH=64 market_parser_axis_adapter_tb
run -all
quit -sim
vsim -onfinish stop -GDATA_WIDTH=256 market_parser_axis_adapter_tb
run -all
quit -sim
vsim -onfinish stop -GDATA_WIDTH=512 market_parser_axis_adapter_tb
run -all
quit -sim
quit
