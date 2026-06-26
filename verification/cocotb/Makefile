TOPLEVEL_LANG ?= verilog
SIM ?= questa

PROJECT_ROOT := $(abspath ../..)

VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_pkg.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_axis_adapter.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_64.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_100g_ingress.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_512_boundary_scan.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_512_frontend.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_512_event_extract.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_512_window_buffer.sv
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/market_parser_512_pipeline.sv

TOPLEVEL = market_parser_512_pipeline
MODULE = test_market_parser_512_pipeline

include $(shell cocotb-config --makefiles)/Makefile.sim
