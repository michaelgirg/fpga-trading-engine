vlog -sv ../rtl/market_parser.sv market_parser_tb.sv
vsim -c market_parser_tb -do "run -all; quit"
