# TMH Linear Waveform Demo — Standalone Unit Test

This directory contains everything required to compile the consolidated
`tmh_event_gen` in isolation and generate a waveform for a 2-wide commit
configuration.

## Files

1. `ariane_pkg_stub.sv`
   - Minimal standalone substitute for CVA6 `ariane_pkg`.
   - Defines only `fu_t`, `fu_op`, and the enumerators needed by this unit test.
   - DO NOT compile this stub together with CVA6's real `ariane_pkg`.

2. `tmh_pkg.sv`
   - Defines the B/L/S/A/N instruction classes.
   - Defines LL, AN, AS indices and `TMH_NUM_EVENTS`.

3. `tmh_event_gen.sv`
   - Consolidated DUT.
   - Contains classifier, sequence tracker/history, and matcher.
   - No `tmh_instr_classifier`, `tmh_sequence_tracker`, or
     `tmh_sequence_matcher` modules are needed for this consolidated version.

4. `tb_tmh_event_gen_linear.sv`
   - Linear 2-wide testbench.
   - Generates `tmh_event_gen_linear.vcd`.
   - Exercises LL, AN, AS, bubble, clear-history, unsupported-instruction,
     and same-cycle port-0 -> port-1 cases.

5. `files.f`
   - Compile order.

6. `run_xrun.sh`
   - Command-line Xcelium run.

7. `run_xrun_gui.sh`
   - Xcelium + SimVision GUI.

## Compile order

The order matters:

    ariane_pkg_stub.sv
    tmh_pkg.sv
    tmh_event_gen.sv
    tb_tmh_event_gen_linear.sv

## Run with Xcelium

    chmod +x run_xrun.sh run_xrun_gui.sh
    ./run_xrun.sh

or:

    ./run_xrun_gui.sh

A successful run prints:

    PASS: tmh_event_gen linear waveform test completed

and writes:

    tmh_event_gen_linear.vcd

## If integrating inside the real CVA6 repository

Do NOT use `ariane_pkg_stub.sv`.

Instead compile CVA6's real packages/dependencies in the normal CVA6 compile
flow, followed by:

    tmh_pkg.sv
    tmh_event_gen.sv
    tb_tmh_event_gen_linear.sv

The testbench's minimal scoreboard entry type is intentional: the DUT is
parameterized by `scoreboard_entry_t` and only reads `.fu` and `.op`.
