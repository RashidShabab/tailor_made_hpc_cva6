// -----------------------------------------------------------------------------

// cva6_tmh_unit.sv

//

// Top-level wrapper for the TMH 25-event transition-matrix counter block.

// This is the single instantiation point inside perf_counters.sv -- ties

// together the already-Xcelium-verified tmh_event_gen (unchanged) with

// the two new modules (tmh_counter_bank, tmh_csr) per

// tmh-25event-csr-integration-spec.md.

//

// PACKING NOTE (reconciled 2026-09-18, see tmh-tycmpat-reconciliation.md):
// commit_instr_i is PACKED (dimension BEFORE the identifier), matching
// tmh_event_gen's own port style directly -- no repack needed. A prior
// Xcelium 25.03-s013 TYCMPAT failure here was originally attributed to a
// tool quirk ("Xcelium silently unpacks a parameter-type packed-syntax
// port"), but re-reading that failure's raw error text shows the RTL
// port was already packed at the time and the *testbench's* local
// variable was the unpacked one -- an ordinary shape mismatch between
// two files that weren't kept in sync, not a tool-specific behavior.
// Confirmed clean on both Verilator 5.008 and real Cadence Xcelium
// 25.03-s013 with both sides declared packed and consistent. The
// operative rule: keep both ends of every port connection declared
// with matching packed/unpacked shape -- nothing more exotic to design
// around.
//
// CAVEAT for the real perf_counters.sv integration: this hasn't been
// run on any simulator yet. perf_counters.sv's own commit_instr_i is
// already packed, so a direct packed-to-packed connection should work,
// but verify against a real simulator when that step happens -- don't
// carry this conclusion over by assumption alone.

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

    // Packed, matching tmh_event_gen's own port style -- see file header note.

    input  scoreboard_entry_t [NrCommitPorts-1:0] commit_instr_i,

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

 

 

  // Unchanged, already Xcelium-verified against 11 directed tests

  // (T1-T11) -- see tmh-full-matrix-xcelium-verification.md.

  tmh_event_gen #(

      .NrCommitPorts      (NrCommitPorts),

      .scoreboard_entry_t (scoreboard_entry_t),

      .TmhIncWidth        (TmhIncWidth)

  ) i_tmh_event_gen (

      .clk_i           (clk_i),

      .rst_ni          (rst_ni),

      .commit_instr_i  (commit_instr_i),

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
