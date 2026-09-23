# Full CVA6 integration

Upstream: https://github.com/openhwgroup/cva6.git

Pinned revision: `81245a47fad8fe1a5d562d953ef2662e099def76`.

Initial configuration: `cv64a6_imafdc_sv39` (RV64, two commit ports, FPU enabled, Zcmp disabled). This is a new provisional integration baseline, not a claim about the researcher's earlier CVA6 revision.

The working full-core checkout is the sibling directory `../../cva6-core` relative to this file's directory. The patch is already applied there, and the five TMH source files are copied into `core/tmh/`. The standalone package stub is never compiled in the full-core build.

## Reproduce on a fresh checkout

Run from the parent directory of the TMH repository named `cva6`:

```bash
git clone https://github.com/openhwgroup/cva6.git cva6-core
git -C cva6-core checkout 81245a47fad8fe1a5d562d953ef2662e099def76
git -C cva6-core submodule update --init --recursive core/cvfpu core/cache_subsystem/hpdcache
git -C cva6-core apply --check ../cva6/integration/cva6-tmh.patch
git -C cva6-core apply ../cva6/integration/cva6-tmh.patch
mkdir -p cva6-core/core/tmh
cp cva6/include/tmh_pkg.sv cva6-core/core/tmh/
cp cva6/rtl/*.sv cva6-core/core/tmh/
bash cva6/sim/run_cva6_integration.sh enabled
bash cva6/sim/run_cva6_integration.sh disabled
```

Do not reapply the patch to the already modified checkout. Keep `core/tmh` copies synchronized with the standalone source when making future changes. Other upstream manifests (e.g. alternative synthesis or DV flows) are not updated by this patch; this integration uses `core/Flist.cva6`.

## Changes and source evidence

- `core/cva6.sv:99` defines the real packed scoreboard entry, including `.fu`, `.op`, `.ex`, and compressed-instruction metadata. `ariane_pkg.sv:190` defines the 4-bit functional-unit enum; line 275 defines the 8-bit operation enum. The complete entry width is configuration-dependent and is passed as a type, never recreated in the monitor.
- `core/issue_stage.sv:210` instantiates the scoreboard and forwards commit entries. `core/scoreboard.sv:138` reads each entry using its commit pointer. Lines 275 and 284 advance the oldest pointer and offset subsequent ports, establishing ascending port age order.
- `core/commit_stage.sv:185` begins valid/exception-qualified retirement. The port-1 gate near line 337 requires port-0 acknowledgement and restricts which instructions may retire together. Dropped entries may still be acknowledged for removal, so raw `commit_ack_commit_id` must not drive the monitor.
- `core/cva6.sv:1204` forms `commit_ack = commit_macro_ack & ~commit_drop_id_commit`. This filtered acknowledgement drives the monitor. `commit_stage.sv` substitutes raw acknowledgements when Zcmp is disabled. Integration currently asserts that Zcmp is disabled because macro-level classification is unresolved.
- `core/id_stage.sv:173` expands compressed instructions before the decoder at line 340. The monitor observes decoded functional-unit and operation enums, not an assumed 32-bit instruction word.
- `core/cva6.sv:1345` selects the TMH or HPM read result. `gen_tmh` instantiates the separate monitor and gates writes by successful port-0 retirement. HPM writes are gated away from the TMH window, preserving counting during custom CSR writes. `perf_counters.sv` itself is unchanged.
- `core/csr_regfile.sv:891` and line 1925 route the existing TMH window `0x7C3..0x7C7` when enabled. Existing privilege checking and CSR set/clear computation remain in the CSR file. These addresses do not appear in the pinned upstream CSR map, whose adjacent custom registers occupy `0x7C0..0x7C2`.
- The appended `TmhEn` parameter defaults to zero. Disabled custom accesses remain illegal, and the monitor is not instantiated. The directed disabled-feature test confirms the custom write/read traps.

## Validation status, 2026-09-23

The standalone suites passed (11 event-generator checks and 24 counter/CSR checks). The full-core directed regression now passes with Verilator 5.032 and the FPU enabled. It uses `-Wno-BLKANDNBLK`, matching upstream `Makefile`'s compatibility option. Results (each scenario's `run.log` ends in PASS):

| Scenario | TMH | Retired | Dual-commit cycles | Checked CSR reads | Expected traps |
| --- | --- | ---: | ---: | ---: | ---: |
| 0 — counting, CSR control, HPM | enabled | 118 | 2 | 57 | 0 |
| 1 — custom CSR access in M mode | disabled | 24 | 0 | 4 | 2 |
| 2 — custom CSR access in U mode | enabled | 23 | 0 | 4 | 2 |
| 3 — custom CSR access in S mode | enabled | 24 | 0 | 4 | 2 |
| 4 — all 25 pairs + FPU `fadd.d` | enabled | 184 | 5 | 50 | 0 |

Logs and waveforms are written to `sim/build/cva6_integration_<enabled|disabled>/scenario_<n>/` (git-ignored).

The testbench executes machine-code programs using an AXI RAM, compares live counters against an independent raw-instruction reference model, exercises all 25 pair matches and CSR counter selections, and observes dual retirement. Additional passing checks cover wrong-path exclusion, compressed arithmetic, a fence, snapshot/clear/disable, CSR set/clear, HPM integer-event counting, user/supervisor privilege violations, disabled-feature access traps, and a double-precision floating-point addition.

Remaining work includes interrupt handling, broader instruction classification, overflow-focused tests, other configurations, and synthesis/timing measurement. Passing these directed tests does not imply exhaustive core or FPU verification.

## Existing policy limitations

The original classifier and counters were copied unchanged. All 25 pairs are tracked; X breaks history; the 64-bit counters wrap; enable pauses accumulation but not history. Counter width is not yet parameterized. The functional-unit classifier may classify floating-point memory operations or atomics as L/S and extension ALU operations as A; these require a research policy and dedicated tests before general workload evaluation. No claim of exhaustive ISA classification is made.
