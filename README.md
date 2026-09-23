# Tailor-Made Hardware Performance Counters (TMH) for CVA6

Sequence-based security performance counters for the
[CVA6](https://github.com/openhwgroup/cva6) RISC-V core. The monitor watches
architecturally committed instructions, classifies each into a 5-class
alphabet, and counts **every one of the 25 ordered adjacent-class pairs**
(a full 5x5 transition matrix). Counters are read through a small custom CSR
window.

| Class | Meaning | CVA6 decode (`.fu` / `.op`) |
| --- | --- | --- |
| B | branch / jump | `CTRL_FLOW` |
| L | load | `LOAD` (includes FP loads) |
| S | store | `STORE` (includes FP stores and AMOs) |
| A | arithmetic | `ALU` (non-Boolean ops), `MULT` |
| N | Boolean | `ALU` with `XORL` / `ORL` / `ANDL` |
| X | anything else (CSR/system, FPU arithmetic, ...) | breaks history, never paired |

## Repository layout

| Path | Contents |
| --- | --- |
| `include/tmh_pkg.sv` | Class enum, 25 pair indices, CSR addresses |
| `include/ariane_pkg_stub.sv` | Minimal `ariane_pkg` for **standalone** tests only — never compile with real CVA6 |
| `rtl/tmh_event_gen.sv` | Classify -> track history -> match all 25 pairs; multi-port, age-ordered |
| `rtl/tmh_counter_bank.sv` | 25 live 64-bit accumulators + 25 snapshot shadows |
| `rtl/tmh_csr.sv` | CSR decode for the TMH window |
| `rtl/cva6_tmh_unit.sv` | Wrapper instantiated in `core/cva6.sv` |
| `tb/tb_tmh_event_gen_linear.sv` | Standalone directed tests T1-T11 |
| `tb/tb_cva6_tmh_unit.sv` | Standalone counter/CSR tests U1-U8 |
| `tb/tb_cva6_tmh_integration.sv` | Full-core CVA6 testbench (5 scenarios) |
| `integration/cva6-tmh.patch` | Patch against upstream CVA6 `81245a47` |
| `integration/README.md` | How to reproduce the full-core build, and what the patch changes |
| `sim/` | `makefile`, file list, Verilator / Xcelium launch scripts |

## CSR window (machine-mode custom RW, `0x7C3`-`0x7C7`)

| Address | Name | Fields |
| --- | --- | --- |
| `0x7C3` | `TMH_CTRL` | bit0 EN (stored, resets 0); bit1 SNAPSHOT (pulse); bit2 CLEAR (pulse, also clears history) |
| `0x7C4` | `TMH_SEL` | bits[4:0] pair index, WARL-clamped to 24 |
| `0x7C5` | `TMH_CNT_LO` | low 32 bits of the selected **snapshot** counter |
| `0x7C6` | `TMH_CNT_HI` | high 32 bits of the selected snapshot counter |
| `0x7C7` | `TMH_INFO` | [7:0] number of pairs (25), [15:8] layout version (1) |

Pair index = `prev * 5 + curr`, with B=0, L=1, S=2, A=3, N=4. Counters are
free-running and wrap at 64 bits. EN pauses accumulation but not history.
In CVA6 the window only exists when the `TmhEn` parameter is 1 (default 0); otherwise
accesses trap as illegal instructions.

## Running the tests

Standalone (stub package), from `sim/`:

```bash
make verilator                       # both standalone suites under Verilator
make sim TOP=tb_tmh_event_gen_linear # Xcelium
make sim TOP=tb_cva6_tmh_unit        # Xcelium
```

Full core: set up a sibling `cva6-core` checkout as described in
[integration/README.md](integration/README.md), then from `sim/`:

```bash
make cva6-integration                # TMH enabled (scenarios 0,2,3,4) and disabled (scenario 1)
```

## Status

- Standalone: 11 event-generator checks and 24 counter/CSR checks pass
  (Verilator 5.032; the event generator was also run on Xcelium 25.03).
- Full core: the directed regression passes on `cv64a6_imafdc_sv39` (RV64, 2 commit ports,
  FPU on, Zcmp off) at upstream CVA6 `81245a47`.
- Not yet covered: interrupts/trap-boundary policy, classifying the special
  instruction types (AMO, FP memory, Zbb), overflow tests, RV32 and other configs,
  Zcmp, and area/timing measurement.
