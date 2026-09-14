
# TMH Full-Matrix Event Generator — Standalone Unit Test



This directory contains everything required to compile `tmh_event_gen` in

isolation and verify it against a full 5x5 transition matrix over a 5-class

instruction alphabet (B/L/S/A/N — branch, load, store, arithmetic, Boolean).

Every one of the 25 ordered (prev, curr) class pairs is counted every

cycle — there's no fixed subset and no CSR-selected subset; this lets

downstream analysis pick which sequences matter without any RTL change.



## Files



1. `include/ariane_pkg_stub.sv`

   - Minimal standalone substitute for CVA6 `ariane_pkg`.

   - Defines `fu_t` and `fu_op`, including the `BRANCH`/`LD`/`SD` op values

     the testbench's stimulus generator uses (classification itself only

     ever looks at `.fu`, not `.op`, for the B/L/S classes).

   - DO NOT compile this stub together with CVA6's real `ariane_pkg`.



2. `include/tmh_pkg.sv`

   - Defines the `tmh_class_e` enum: `TMH_B/L/S/A/N` (the trackable

     alphabet) plus `TMH_X` (anything outside it — breaks sequence

     adjacency, never paired).

   - Defines all 25 `TMH_XY` pair indices (e.g. `TMH_LL`, `TMH_AN`, `TMH_NB`)

     and `TMH_NUM_PAIRS = 25`.



3. `rtl/tmh_event_gen.sv`

   - The DUT. Three stages in one module: classify (comb) -> track history

     (seq, one register) -> match against the full matrix (comb).

   - `tmh_inc_o` is an **unpacked** array, `logic [TmhIncWidth-1:0]

     tmh_inc_o [TMH_NUM_PAIRS]` — every instantiation must explicitly pass

     `.NrCommitPorts(...)`; don't rely on the module's own default.



4. `tb/tb_tmh_event_gen_linear.sv`

   - Directed testbench, tests T1-T11: single/cross-cycle chaining, a

     bubble that preserves history, `clear_history_i` breaking it,

     same-cycle 2-port matches (including two *different* events forming

     in one cycle from a 2-wide commit), and the LL=2 dual-port

     same-class case.

   - Self-checking (`expect_none`/`expect_only`/`expect_two` tasks).

   - Generates `tmh_event_gen.vcd`.



5. `sim/files.f` — compile order (see below).



6. `sim/Makefile` — `make sim` / `make gui` / `make clean`. Preferred way to

   run this.



7. `sim/run_xrun.sh`, `sim/run_xrun_gui.sh` — equivalent standalone scripts,

   same `xrun` invocation the Makefile wraps.



## Compile order



The order matters (enforced by `sim/files.f`):



    include/ariane_pkg_stub.sv

    include/tmh_pkg.sv

    rtl/tmh_event_gen.sv

    tb/tb_tmh_event_gen_linear.sv



## Run with Xcelium



From `sim/`:



    make sim



or, for the SimVision GUI:



    make gui



`make clean` removes the Xcelium work library, logs, and generated

`.vcd`/waveform files.



A successful run prints:



    ============================================

     ALL DIRECTED TMH EVENT TESTS PASSED

     Waveform: tmh_event_gen.vcd

    ============================================



Verified against real Cadence Xcelium 25.03-s013 — all 11 directed tests

pass (T1 through T11).



## If integrating inside the real CVA6 repository



Do NOT use `ariane_pkg_stub.sv`.



Instead compile CVA6's real packages/dependencies in the normal CVA6 compile

flow, followed by:



    tmh_pkg.sv

    tmh_event_gen.sv

    (your integration-specific top-level / testbench)



The DUT's minimal scoreboard entry type requirement is intentional: it's

parameterized by `scoreboard_entry_t` and only reads `.fu` and `.op`.



Note: because this design tracks all 25 pairs unconditionally rather than a

small fixed or CSR-selected subset, mapping `tmh_inc_o` onto a real

`perf_counters.sv`'s `mhpmevent`-style CSR scheme will need some kind of

software-selected indirection (e.g. "counter N watches pair index i") —

there isn't room for 25 fixed reserved event IDs the way earlier,

smaller-event-count designs in this project used. Not yet designed.

