cd ..
vlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv verification/market_parser_tb.sv
vsim -c market_parser_tb -do "run -all; quit"
