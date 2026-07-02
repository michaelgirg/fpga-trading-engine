cd ..
vlog -sv rtl/market_parser_pkg.sv rtl/market_parser.sv rtl/market_parser_axis_adapter.sv rtl/market_parser_64.sv rtl/market_parser_axis_register_slice.sv rtl/market_parser_100g_ingress.sv rtl/market_parser_udp_payload_strip.sv rtl/market_parser_512_boundary_scan.sv rtl/market_parser_512_frontend.sv rtl/market_parser_512_event_extract.sv rtl/market_parser_512_window_buffer.sv rtl/market_parser_512_pipeline.sv rtl/market_parser_event_fifo.sv rtl/market_parser_512_pipeline_fifo.sv rtl/market_parser_axi_lite_regs.sv rtl/market_parser_512_system.sv rtl/market_parser_100g_cmac_system.sv rtl/market_parser_top_of_book.sv rtl/market_parser_100g_strategy_top.sv verification/market_parser_tb.sv verification/market_parser_64_tb.sv verification/market_parser_axis_adapter_tb.sv verification/market_parser_100g_ingress_tb.sv verification/market_parser_100g_cmac_system_tb.sv verification/market_parser_512_boundary_scan_tb.sv verification/market_parser_512_frontend_tb.sv verification/market_parser_512_event_extract_tb.sv verification/market_parser_512_pipeline_tb.sv verification/market_parser_512_pipeline_fifo_tb.sv verification/market_parser_512_system_tb.sv verification/market_parser_top_of_book_tb.sv verification/market_parser_100g_strategy_top_tb.sv
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
vsim -onfinish stop market_parser_100g_ingress_tb
run -all
quit -sim
vsim -onfinish stop market_parser_100g_cmac_system_tb
run -all
quit -sim
vsim -onfinish stop market_parser_512_boundary_scan_tb
run -all
quit -sim
vsim -onfinish stop market_parser_512_frontend_tb
run -all
quit -sim
vsim -onfinish stop market_parser_512_event_extract_tb
run -all
quit -sim
vsim -onfinish stop -GEXTRACTION_WINDOW_BYTES=128 market_parser_512_pipeline_tb
run -all
quit -sim
vsim -onfinish stop -GEXTRACTION_WINDOW_BYTES=256 market_parser_512_pipeline_tb
run -all
quit -sim
vsim -onfinish stop -GEXTRACTION_WINDOW_BYTES=512 market_parser_512_pipeline_tb
run -all
quit -sim
vsim -onfinish stop market_parser_512_pipeline_fifo_tb
run -all
quit -sim
vsim -onfinish stop market_parser_512_system_tb
run -all
quit -sim
vsim -onfinish stop market_parser_top_of_book_tb
run -all
quit -sim
vsim -onfinish stop market_parser_100g_strategy_top_tb
run -all
quit -sim
quit
