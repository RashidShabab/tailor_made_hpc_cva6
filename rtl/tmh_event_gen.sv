// SPDX-License-Identifier: Apache-2.0
//
// Consolidated TMH event-generation datapath -- classify, track, and match
// merged into a single module. Same external module name, parameters, and
// ports as the original tmh_event_gen.sv, so this is a drop-in replacement:
// it plugs into cva6_tmh_perf_top.sv, tb/tb_tmh_event_gen.sv, and
// tmh_event_gen_dut.sv completely unchanged.
//
// Replaces FOUR files with this ONE:
//   tmh_instr_classifier.sv, tmh_sequence_tracker.sv,
//   tmh_sequence_matcher.sv, tmh_event_gen.sv (the old thin wrapper)
//
// Nothing about the logic changed in this merge -- each stage below is the
// original submodule's always_comb/always_ff block, pasted in verbatim,
// with only the wires between stages renamed (see NOTE below). Two
// combinational blocks feeding each other settle to the same fixed point
// whether or not there's a module boundary between them, so removing the
// boundaries does not change behavior.
//
// NOTE / bug fixed while merging: the original tmh_event_gen.sv declared a
// local signal named `class` (tmh_class_e [NrCommitPorts-1:0] class;).
// `class` is a reserved SystemVerilog keyword (IEEE 1800, `class...
// endclass`), not a legal plain identifier -- every conformant tool
// (Verilator, Icarus, VCS, Questa, Xcelium) lexes it specially regardless
// of context, so that file would not have compiled as-is. Renamed to
// `instr_class` / `instr_class_valid` here; nothing else changes.
//
// Pipeline (now three always blocks in one module instead of three module
// instances):
//
//   commit_instr_i / commit_ack_i
//               |
//               v
//   [stage 1, comb]   classify each committed instruction (was tmh_instr_classifier)
//               |
//               v
//   [stage 2, seq]    pair with the previous class, one history register
//                     (was tmh_sequence_tracker -- the ONLY state in this module)
//               |
//               v
//   [stage 3, comb]   count LL / AN / AS matches this cycle (was tmh_sequence_matcher)
//               |
//               v
//          tmh_inc_o

module tmh_event_gen
  import ariane_pkg::*;
  import tmh_pkg::*;
#(
    parameter int unsigned NrCommitPorts = 1,
    parameter type scoreboard_entry_t    = logic,

    parameter int unsigned TmhIncWidth =
      (NrCommitPorts <= 1) ? 1 : $clog2(NrCommitPorts + 1)
) (
    input logic clk_i,
    input logic rst_ni,

    input logic clear_history_i,

    input scoreboard_entry_t [NrCommitPorts-1:0] commit_instr_i,
    input logic              [NrCommitPorts-1:0] commit_ack_i,

    output logic [TMH_NUM_EVENTS-1:0][TmhIncWidth-1:0] tmh_inc_o
);

  // --------------------------------------------------------------------------
  // Stage 1 (combinational) -- was tmh_instr_classifier.sv, unchanged logic.
  // Maps each committed instruction to the five-class B/L/S/A/N alphabet.
  // --------------------------------------------------------------------------
  function automatic logic is_boolean_op(input fu_op op);
    unique case (op)
      XORL, ORL, ANDL: return 1'b1;
      default:         return 1'b0;
    endcase
  endfunction

  function automatic tmh_class_e classify_instr(input scoreboard_entry_t instr);
    // Memory classes have highest priority and are identified by FU.
    if (instr.fu == LOAD) begin
      return TMH_CLASS_LOAD;
    end

    if (instr.fu == STORE) begin
      return TMH_CLASS_STORE;
    end

    // Control-flow instructions are the branch/jump class.
    if (instr.fu == CTRL_FLOW) begin
      return TMH_CLASS_BRANCH;
    end

    // Integer ALU and multiply instructions are either Boolean or arithmetic.
    if ((instr.fu == ALU) || (instr.fu == MULT)) begin
      if ((instr.fu == ALU) && is_boolean_op(instr.op)) begin
        return TMH_CLASS_BOOL;
      end
      return TMH_CLASS_ARITH;
    end

    // CSR, FPU, accelerator, etc. are outside the initial five-class alphabet.
    return TMH_CLASS_NONE;
  endfunction

  // Renamed from the original's `class` / `class_valid` -- see header note.
  tmh_class_e [NrCommitPorts-1:0] instr_class;
  logic       [NrCommitPorts-1:0] instr_class_valid;

  always_comb begin : p_classify
    instr_class       = '{default: TMH_CLASS_NONE};
    instr_class_valid = '0;

    for (int unsigned p = 0; p < NrCommitPorts; p++) begin
      // commit_ack_i is the authoritative "this instruction retired" signal.
      instr_class_valid[p] = commit_ack_i[p];

      if (commit_ack_i[p]) begin
        instr_class[p] = classify_instr(commit_instr_i[p]);
      end
    end
  end

  // --------------------------------------------------------------------------
  // Stage 2 (sequential) -- was tmh_sequence_tracker.sv, unchanged logic.
  // This is the ONLY state this module adds: one history register.
  // Blocking updates of history_class_d/history_valid_d inside the for loop
  // are INTENTIONAL -- they let port p+1 observe port p as its immediate
  // predecessor within the same cycle.
  // --------------------------------------------------------------------------
  tmh_class_e history_class_q, history_class_d;
  logic       history_valid_q, history_valid_d;

  tmh_class_e [NrCommitPorts-1:0] pair_prev;
  tmh_class_e [NrCommitPorts-1:0] pair_curr;
  logic       [NrCommitPorts-1:0] pair_valid;

  always_comb begin : p_track
    // Hold history by default.
    history_class_d = history_class_q;
    history_valid_d = history_valid_q;

    // No pair is valid unless explicitly formed below.
    pair_prev  = '{default: TMH_CLASS_NONE};
    pair_curr  = '{default: TMH_CLASS_NONE};
    pair_valid = '0;

    if (clear_history_i) begin
      history_class_d = TMH_CLASS_NONE;
      history_valid_d = 1'b0;
    end else begin
      for (int unsigned p = 0; p < NrCommitPorts; p++) begin
        if (instr_class_valid[p]) begin

          if (instr_class[p] == TMH_CLASS_NONE) begin
            // A committed instruction outside the alphabet interrupts an
            // immediate sequence. Example: LOAD -> CSR -> LOAD is not LL.
            history_class_d = TMH_CLASS_NONE;
            history_valid_d = 1'b0;

          end else begin
            if (history_valid_d) begin
              pair_prev[p]  = history_class_d;
              pair_curr[p]  = instr_class[p];
              pair_valid[p] = 1'b1;
            end

            // The current committed class becomes the predecessor for the
            // next committed instruction, including a later port this cycle.
            history_class_d = instr_class[p];
            history_valid_d = 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_history_ff
    if (!rst_ni) begin
      history_class_q <= TMH_CLASS_NONE;
      history_valid_q <= 1'b0;
    end else begin
      history_class_q <= history_class_d;
      history_valid_q <= history_valid_d;
    end
  end

  // (The original tracker also exposed history_class_o/history_valid_o as
  // debug-only outputs, but tmh_event_gen never wired them to anything
  // outside itself -- they dead-ended at that module boundary. Dropped
  // here; history_class_q/history_valid_q are still directly visible to a
  // waveform dump, one hierarchy level shallower than before.)

  // --------------------------------------------------------------------------
  // Stage 3 (combinational) -- was tmh_sequence_matcher.sv, unchanged logic.
  // No architectural state. Reports how many times each sequence occurred
  // this cycle (can be >1 on a superscalar commit cycle).
  // --------------------------------------------------------------------------
  always_comb begin : p_match
    tmh_inc_o = '0;

    for (int unsigned p = 0; p < NrCommitPorts; p++) begin
      if (pair_valid[p]) begin

        // TMH 0: LL = LOAD -> LOAD
        if ((pair_prev[p] == TMH_CLASS_LOAD) &&
            (pair_curr[p] == TMH_CLASS_LOAD)) begin
          tmh_inc_o[TMH_LL_IDX] = tmh_inc_o[TMH_LL_IDX] + 1'b1;
        end

        // TMH 1: AN = ARITHMETIC -> BOOLEAN
        if ((pair_prev[p] == TMH_CLASS_ARITH) &&
            (pair_curr[p] == TMH_CLASS_BOOL)) begin
          tmh_inc_o[TMH_AN_IDX] = tmh_inc_o[TMH_AN_IDX] + 1'b1;
        end

        // TMH 2: AS = ARITHMETIC -> STORE
        if ((pair_prev[p] == TMH_CLASS_ARITH) &&
            (pair_curr[p] == TMH_CLASS_STORE)) begin
          tmh_inc_o[TMH_AS_IDX] = tmh_inc_o[TMH_AS_IDX] + 1'b1;
        end
      end
    end
  end

  // Simulation-only configuration checks (kept from tmh_sequence_matcher.sv;
  // NrPairs there is exactly NrCommitPorts here, since matching now happens
  // directly on this module's own ports instead of a separate NrPairs param).
  // pragma translate_off
  initial begin
    assert (NrCommitPorts >= 1)
      else $fatal(1, "tmh_event_gen: NrCommitPorts must be >= 1");

    assert ((2**TmhIncWidth) > NrCommitPorts)
      else $fatal(1, "tmh_event_gen: TmhIncWidth is too small");
  end
  // pragma translate_on

endmodule
