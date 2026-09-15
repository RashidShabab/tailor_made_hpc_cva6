// -----------------------------------------------------------------------------

// cva6_tmh_unit.sv

//

// Top-level wrapper for the TMH 25-event transition-matrix counter block.

// This is the single instantiation point inside perf_counters.sv -- ties

// together the already-Xcelium-verified tmh_event_gen (unchanged) with

// the two new modules (tmh_counter_bank, tmh_csr) per

// tmh-25event-csr-integration-spec.md.

//

// PACKING NOTE (real Xcelium 25.03-s013 TYCMPAT bug, fixed here):

// commit_instr_i is deliberately declared UNPACKED (dimension AFTER the

// identifier) rather than mirroring tmh_event_gen's own packed-style

// declaration (dimension BEFORE the identifier). Real Xcelium elaborates

// a `parameter type` port combined with a dimension-before-identifier as

// an UNPACKED array regardless of what the type resolves to -- it only

// treats that form as packed when the type is already concrete at the

// declaration site (e.g. a plain local variable of a fixed struct type).

// tmh_event_gen's own port genuinely IS packed (confirmed by the same

// error), so an explicit repack loop below builds that shape via

// elementwise assignment rather than relying on an implicit port-shape

// conversion, which is exactly what failed. Same root cause as the

// earlier Verilator "parameter type + array" workaround in

// tmh-event-gen-verilator-check.md, different tool.

//

// CAVEAT for the real perf_counters.sv integration: if its own

// commit_instr_i turns out to be declared packed (plausible, matching

// tmh_event_gen/real cva6.sv style) when this is wired in for real, that

// outer boundary may need the same kind of explicit repack, or this

// port's form flipped -- re-check against real Xcelium output or real

// source then, don't assume it carries over automatically.

// -----------------------------------------------------------------------------

 

module cva6_tmh_unit

  import tmh_pkg::*;

#(

    parameter int unsigned NrCommitPorts      = 1,

    parameter type         scoreboard_entry_t = logic,

    parameter int unsigned CsrDataWidth       = 64,

 

    parameter int unsigned TmhIncWidth =

      (NrCommitPorts <= 1) ? 1 : $clog2(NrCommitPorts + 1)

) (

    input  logic                             clk_i,

    input  logic                             rst_ni,

 

    // Commit stream, straight from perf_counters.sv's own ports.

    // Unpacked on purpose -- see file header note.

    input  scoreboard_entry_t                commit_instr_i [NrCommitPorts],

    input  logic              [NrCommitPorts-1:0] commit_ack_i,

 

    // Generic CSR bus, straight from perf_counters.sv's own ports.

    input  logic [11:0]                      addr_i,

    input  logic                             we_i,

    input  logic [CsrDataWidth-1:0]          data_i,

    output logic [CsrDataWidth-1:0]          csr_rdata_o,

    output logic                             csr_addr_hit_o

);

 

  logic [TmhIncWidth-1:0] tmh_inc [TMH_NUM_PAIRS];

 

  logic        en, snapshot, clear;

  logic [4:0]  sel;

  logic [63:0] cnt;

 

  // Explicit repack for tmh_event_gen's packed commit_instr_i port --

  // see file header note.

  scoreboard_entry_t [NrCommitPorts-1:0] commit_instr_packed;

  always_comb begin

    for (int unsigned p = 0; p < NrCommitPorts; p++) begin

      commit_instr_packed[p] = commit_instr_i[p];

    end

  end

 

  // Unchanged, already Xcelium-verified against 11 directed tests

  // (T1-T11) -- see tmh-full-matrix-xcelium-verification.md.

  tmh_event_gen #(

      .NrCommitPorts      (NrCommitPorts),

      .scoreboard_entry_t (scoreboard_entry_t),

      .TmhIncWidth        (TmhIncWidth)

  ) i_tmh_event_gen (

      .clk_i           (clk_i),

      .rst_ni          (rst_ni),

      .commit_instr_i  (commit_instr_packed),

      .commit_ack_i    (commit_ack_i),

      .clear_history_i (clear),   // driven by TMH_CTRL.CLEAR

      .tmh_inc_o       (tmh_inc)

  );

 

  tmh_counter_bank #(

      .NrCommitPorts (NrCommitPorts),

      .TmhIncWidth   (TmhIncWidth)

  ) i_tmh_counter_bank (

      .clk_i      (clk_i),

      .rst_ni     (rst_ni),

      .tmh_inc_i  (tmh_inc),

      .en_i       (en),

      .snapshot_i (snapshot),

      .clear_i    (clear),

      .sel_i      (sel),

      .cnt_o      (cnt)

  );

 

  tmh_csr #(

      .CsrDataWidth (CsrDataWidth)

  ) i_tmh_csr (

      .clk_i          (clk_i),

      .rst_ni         (rst_ni),

      .addr_i         (addr_i),

      .we_i           (we_i),

      .data_i         (data_i),

      .csr_rdata_o    (csr_rdata_o),

      .csr_addr_hit_o (csr_addr_hit_o),

      .en_o           (en),

      .snapshot_o     (snapshot),

      .clear_o        (clear),

      .sel_o          (sel),

      .cnt_i          (cnt)

  );

 

endmodule
