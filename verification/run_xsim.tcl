cd ..
xvlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv rtl/market_parser_64.sv verification/market_parser_tb.sv verification/market_parser_64_tb.sv
xelab market_parser_tb -debug typical
xsim market_parser_tb -runall
xelab market_parser_64_tb -debug typical
xsim market_parser_64_tb -runall
