`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Linear unit-level testbench for tmh_event_gen
//
// Purpose:
//   - Generate a clean waveform for a 2-wide CVA6-style commit interface.
//   - Exercise LL, AN, and AS sequence events.
//   - Demonstrate:
//       * history across cycles
//       * two LL events in one 2-wide commit cycle
//       * bubbles do NOT break history
//       * clear_history_i DOES break history
//       * unsupported instructions (e.g. CSR) break history
//       * same-cycle sequence formation across commit port 0 -> port 1
//
// This TB intentionally uses a MINIMAL scoreboard entry type containing only
// the fields tmh_event_gen actually reads: .fu and .op.
//
// Compile this TB with your existing ariane_pkg.sv, tmh_pkg.sv, and
// tmh_event_gen.sv.
// -----------------------------------------------------------------------------

module tb_tmh_event_gen_linear;

  import ariane_pkg::*;
  import tmh_pkg::*;

  localparam int unsigned NrCommitPorts = 2;
  localparam int unsigned TmhIncWidth   = $clog2(NrCommitPorts + 1); // = 2

  // Minimal scoreboard entry for unit-level testing.
  // tmh_event_gen only accesses instr.fu and instr.op.
  typedef struct packed {
    fu_t  fu;
    fu_op op;
  } tb_scoreboard_entry_t;

  logic clk_i;
  logic rst_ni;

  logic clear_history_i;

  tb_scoreboard_entry_t [NrCommitPorts-1:0] commit_instr_i;
  logic                 [NrCommitPorts-1:0] commit_ack_i;

  logic [TMH_NUM_EVENTS-1:0][TmhIncWidth-1:0] tmh_inc_o;

  // ---------------------------------------------------------------------------
  // "Next" stimulus registers.
  //
  // These are loaded linearly by the initial block at the falling edge.
  // At the following rising edge they are transferred to the DUT inputs.
  // This models a synchronous upstream commit stage and gives cleaner waves.
  // ---------------------------------------------------------------------------
  tb_scoreboard_entry_t [NrCommitPorts-1:0] next_commit_instr;
  logic                 [NrCommitPorts-1:0] next_commit_ack;
  logic                                    next_clear_history;

  // Helpful waveform markers.
  int unsigned test_step;
  logic [TmhIncWidth-1:0] exp_ll;
  logic [TmhIncWidth-1:0] exp_an;
  logic [TmhIncWidth-1:0] exp_as;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  tmh_event_gen #(
    .NrCommitPorts    (NrCommitPorts),
    .scoreboard_entry_t(tb_scoreboard_entry_t),
    .TmhIncWidth      (TmhIncWidth)
  ) dut (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .clear_history_i (clear_history_i),
    .commit_instr_i  (commit_instr_i),
    .commit_ack_i    (commit_ack_i),
    .tmh_inc_o       (tmh_inc_o)
  );

  // ---------------------------------------------------------------------------
  // 100 MHz clock: 10 ns period
  // ---------------------------------------------------------------------------
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  // ---------------------------------------------------------------------------
  // Synchronous source model.
  //
  // At each posedge the DUT sees the previous cycle's commit inputs for its
  // history update, while these source flops launch the next commit bundle.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      commit_instr_i  <= '0;
      commit_ack_i    <= '0;
      clear_history_i <= 1'b0;
    end else begin
      commit_instr_i  <= next_commit_instr;
      commit_ack_i    <= next_commit_ack;
      clear_history_i <= next_clear_history;
    end
  end

  // ---------------------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tmh_event_gen_linear.vcd");
    $dumpvars(0, tb_tmh_event_gen_linear);
  end

  // ---------------------------------------------------------------------------
  // Linear stimulus
  // ---------------------------------------------------------------------------
  initial begin
    rst_ni             = 1'b0;
    next_commit_instr  = '0;
    next_commit_ack    = '0;
    next_clear_history = 1'b0;

    test_step = 0;
    exp_ll    = '0;
    exp_an    = '0;
    exp_as    = '0;

    // Hold reset for two clocks.
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // ========================================================================
    // STEP 1: One LOAD on port 0.
    // No predecessor exists yet -> no sequence event.
    // ========================================================================
    test_step          = 1;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;   // op ignored for LOAD

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 2: Another LOAD on port 0.
    // Previous history is LOAD -> LL = 1.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 2;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;

    exp_ll = 1;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 3: Two LOADs retire in the same cycle.
    //
    // Existing history LOAD -> port0 LOAD = LL #1
    // port0 LOAD          -> port1 LOAD = LL #2
    //
    // Therefore LL increment = 2 (2'b10).
    // This is the key demonstration of why TmhIncWidth = 2 for a 2-wide core.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 3;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b11;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;
    next_commit_instr[1].fu = LOAD;
    next_commit_instr[1].op = ADD;

    exp_ll = 2;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 4: Bubble -- no instruction commits.
    // History must remain LOAD. No event this cycle.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 4;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b00;
    next_clear_history = 1'b0;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 5: LOAD after the bubble.
    // Bubble did not break instruction adjacency -> LL = 1.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 5;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;

    exp_ll = 1;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 6: Explicitly clear sequence history.
    // No commit and no event.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 6;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b00;
    next_clear_history = 1'b1;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 7: LOAD immediately after clear_history.
    // Even though the old history before clear was LOAD, no LL is allowed.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 7;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 8: ARITHMETIC instruction (ADD).
    // Establish ARITH as the new predecessor. No event yet.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 8;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = ALU;
    next_commit_instr[0].op = ADD;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 9: BOOLEAN instruction (ANDL).
    // ARITH -> BOOL = AN = 1.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 9;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = ALU;
    next_commit_instr[0].op = ANDL;

    exp_ll = 0;
    exp_an = 1;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 10: ARITHMETIC instruction.
    // BOOL -> ARITH does not match any configured TMH.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 10;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = ALU;
    next_commit_instr[0].op = ADD;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 11: STORE.
    // ARITH -> STORE = AS = 1.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 11;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = STORE;
    next_commit_instr[0].op = ADD;  // op ignored for STORE

    exp_ll = 0;
    exp_an = 0;
    exp_as = 1;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 12: LOAD.
    // STORE -> LOAD is not one of LL/AN/AS.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 12;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 13: Unsupported instruction class -- CSR.
    // Classifier returns TMH_CLASS_NONE, which intentionally breaks history.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 13;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = CSR;
    next_commit_instr[0].op = ADD;  // ignored because FU = CSR

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 14: LOAD after CSR.
    // Must NOT produce LL because the CSR broke the sequence history.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 14;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b01;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = LOAD;
    next_commit_instr[0].op = ADD;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 15: Same-cycle ARITH -> STORE using both commit ports.
    //
    // Port 0 = ARITH
    // Port 1 = STORE
    //
    // The tracker uses blocking next-history updates inside its port loop,
    // therefore port 1 sees port 0 as its immediate predecessor -> AS = 1.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 15;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b11;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = ALU;
    next_commit_instr[0].op = ADD;
    next_commit_instr[1].fu = STORE;
    next_commit_instr[1].op = ADD;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 1;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 16: Same-cycle ARITH -> BOOLEAN using both commit ports.
    //
    // Port 0 = ADD  -> ARITH
    // Port 1 = ANDL -> BOOL
    //
    // Therefore AN = 1.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 16;
    next_commit_instr  = '0;
    next_commit_ack    = 2'b11;
    next_clear_history = 1'b0;

    next_commit_instr[0].fu = ALU;
    next_commit_instr[0].op = ADD;
    next_commit_instr[1].fu = ALU;
    next_commit_instr[1].op = ANDL;

    exp_ll = 0;
    exp_an = 1;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    // ========================================================================
    // STEP 17: Idle/end.
    // ========================================================================
    @(negedge clk_i);
    test_step          = 17;
    next_commit_instr  = '0;
    next_commit_ack    = '0;
    next_clear_history = 1'b0;

    exp_ll = 0;
    exp_an = 0;
    exp_as = 0;

    @(posedge clk_i); #1;
    assert (tmh_inc_o[TMH_LL_IDX] == exp_ll);
    assert (tmh_inc_o[TMH_AN_IDX] == exp_an);
    assert (tmh_inc_o[TMH_AS_IDX] == exp_as);

    $display("");
    $display("============================================================");
    $display("  PASS: tmh_event_gen linear waveform test completed");
    $display("  VCD : tmh_event_gen_linear.vcd");
    $display("============================================================");
    $display("");

    repeat (2) @(posedge clk_i);
    $finish;
  end

endmodule
