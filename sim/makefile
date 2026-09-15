# Simple Makefile for the tmh_event_gen standalone Xcelium sim.

# Run from this directory (sim/).

 

TOP    := tb_tmh_event_gen_linear

FILES  := files.f

XRUN   := xrun -sv -access +rwc -timescale 1ns/1ps -f $(FILES)

 

.PHONY: all sim gui clean

 

all: sim

 

sim:
	$(XRUN)

 

gui:
	$(XRUN) -gui

 

clean:
	rm -rf xcelium.d xrun.log xrun.history .simvision waves.shm *.vcd *.key *.diag
