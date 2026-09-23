# Simple Makefile for the tmh_event_gen standalone Xcelium sim.

# Run from this directory (sim/).

 

TOP    ?= tb_tmh_event_gen_linear

FILES  := files.f

XRUN   := xrun -sv -access +rwc -timescale 1ns/1ps -f $(FILES) -top $(TOP)

 

.PHONY: all sim gui clean verilator cva6-integration

 

all: sim

verilator:
	bash run_verilator.sh

cva6-integration:
	bash run_cva6_integration.sh enabled
	bash run_cva6_integration.sh disabled

 

sim:
	$(XRUN)

 

gui:
	$(XRUN) -gui

 

clean:
	rm -rf xcelium.d xrun.log xrun.history .simvision waves.shm *.vcd *.key *.diag
