xvlog -sv ../rtl/market_parser_pkg.sv ../rtl/market_parser.sv market_parser_tb.sv
xelab market_parser_tb -debug typical
xsim market_parser_tb -runall
