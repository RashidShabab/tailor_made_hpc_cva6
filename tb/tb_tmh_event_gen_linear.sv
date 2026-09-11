`timescale 1ns/1ps

module tb_tmh_event_gen;

  import ariane_pkg::*;
  import tmh_pkg::*;

  // ------------------------------------------------------------
  // Standalone test configuration: two commit ports
  // ------------------------------------------------------------
  localparam config_pkg::cva6_cfg_t TestCfg = '{
    default: '0,
    NrCommitPorts: 2
  };

  localparam int unsigned TmhIncWidth =
      (TestCfg.NrCommitPorts <= 1)
          ? 1
          : $clog2(TestCfg.NrCommitPorts + 1);

  // Minimal scoreboard entry for this unit test.
  // tmh_event_gen only needs .fu and .op.
  typedef struct packed {
    ariane_pkg::fu_t  fu;
    ariane_pkg::fu_op op;
  } test_scoreboard_entry_t;

  logic clk_i;
  logic rst_ni;
  logic clear_history_i;

  test_scoreboard_entry_t [TestCfg.NrCommitPorts-1:0] commit_instr_i;
  logic [TestCfg.NrCommitPorts-1:0]                   commit_ack_i;

  logic [TmhIncWidth-1:0] tmh_inc_o [TMH_NUM_PAIRS];

  // ------------------------------------------------------------
  // Waveform-friendly aliases
  // ------------------------------------------------------------
  wire [TmhIncWidth-1:0] inc_BB = tmh_inc_o[TMH_BB];
  wire [TmhIncWidth-1:0] inc_BL = tmh_inc_o[TMH_BL];
  wire [TmhIncWidth-1:0] inc_BN = tmh_inc_o[TMH_BN];

  wire [TmhIncWidth-1:0] inc_LL = tmh_inc_o[TMH_LL];
  wire [TmhIncWidth-1:0] inc_LA = tmh_inc_o[TMH_LA];
  wire [TmhIncWidth-1:0] inc_LN = tmh_inc_o[TMH_LN];

  wire [TmhIncWidth-1:0] inc_AN = tmh_inc_o[TMH_AN];
  wire [TmhIncWidth-1:0] inc_AS = tmh_inc_o[TMH_AS];

  wire [TmhIncWidth-1:0] inc_NB = tmh_inc_o[TMH_NB];
  wire [TmhIncWidth-1:0] inc_NL = tmh_inc_o[TMH_NL];
  wire [TmhIncWidth-1:0] inc_NN = tmh_inc_o[TMH_NN];

  // Optional access to internal history in waveform.
  // These hierarchical aliases are simulation-only.
  wire [2:0] history_class = dut.history_class_q;
  wire       history_valid = dut.history_valid_q;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  tmh_event_gen #(
    .CVA6Cfg            (TestCfg),
    .scoreboard_entry_t (test_scoreboard_entry_t),
    .TmhIncWidth        (TmhIncWidth)
  ) dut (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .commit_instr_i  (commit_instr_i),
    .commit_ack_i    (commit_ack_i),
    .clear_history_i (clear_history_i),
    .tmh_inc_o       (tmh_inc_o)
  );

  // ------------------------------------------------------------
  // Clock: 10 ns period
  // ------------------------------------------------------------
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  // ------------------------------------------------------------
  // Build an instruction belonging to one TMH class
  // ------------------------------------------------------------
  function automatic test_scoreboard_entry_t make_instr(
    input tmh_class_e class_i
  );
    test_scoreboard_entry_t tmp;

    begin
      tmp = '0;

      unique case (class_i)
        TMH_B: begin
          tmp.fu = CTRL_FLOW;
          tmp.op = BRANCH;
        end

        TMH_L: begin
          tmp.fu = LOAD;
          tmp.op = LD;
        end

        TMH_S: begin
          tmp.fu = STORE;
          tmp.op = SD;
        end

        TMH_A: begin
          tmp.fu = ALU;
          tmp.op = ADD;
        end

        TMH_N: begin
          tmp.fu = ALU;
          tmp.op = ANDL;
        end

        default: begin
          tmp = '0;
        end
      endcase

      return tmp;
    end
  endfunction

  // ------------------------------------------------------------
  // Drive one retirement cycle.
  // Inputs change on negedge, remain stable until posedge.
  // ------------------------------------------------------------
  task automatic drive_cycle(
    input logic       ack0,
    input tmh_class_e class0,
    input logic       ack1,
    input tmh_class_e class1,
    input logic       clear_i
  );
    @(negedge clk_i);

    commit_ack_i[0]   = ack0;
    commit_ack_i[1]   = ack1;
    commit_instr_i[0] = make_instr(class0);
    commit_instr_i[1] = make_instr(class1);
    clear_history_i   = clear_i;

    // Allow combinational TMH logic to settle so the event pulse
    // is clearly visible before the following rising edge.
    #1;
  endtask

  task automatic finish_cycle;
    @(posedge clk_i);
    #0.1;

    // Remove the retirement inputs immediately after the sampling edge.
    // This prevents the same instruction from appearing as a second
    // combinational event after history updates.
    commit_ack_i      = '0;
    commit_instr_i    = '{default:'0};
    clear_history_i   = 1'b0;
  endtask

  // ------------------------------------------------------------
  // Simple waveform/self-check helpers
  // ------------------------------------------------------------
  task automatic expect_none(input string name);
    for (int i = 0; i < TMH_NUM_PAIRS; i++) begin
      if (tmh_inc_o[i] !== '0) begin
        $error("[%0t] %s: expected no TMH event; tmh_inc_o[%0d]=%0d",
               $time, name, i, tmh_inc_o[i]);
        $fatal(1);
      end
    end
    $display("[%0t] PASS: %s", $time, name);
  endtask

  task automatic expect_only(
    input int unsigned event_idx,
    input int unsigned count,
    input string       name
  );
    for (int i = 0; i < TMH_NUM_PAIRS; i++) begin
      if (i == event_idx) begin
        if (tmh_inc_o[i] !== TmhIncWidth'(count)) begin
          $error("[%0t] %s: event %0d expected %0d, got %0d",
                 $time, name, i, count, tmh_inc_o[i]);
          $fatal(1);
        end
      end else if (tmh_inc_o[i] !== '0) begin
        $error("[%0t] %s: unexpected event %0d = %0d",
               $time, name, i, tmh_inc_o[i]);
        $fatal(1);
      end
    end
    $display("[%0t] PASS: %s", $time, name);
  endtask

  task automatic expect_two(
    input int unsigned event0,
    input int unsigned count0,
    input int unsigned event1,
    input int unsigned count1,
    input string       name
  );
    for (int i = 0; i < TMH_NUM_PAIRS; i++) begin
      if (i == event0) begin
        if (tmh_inc_o[i] !== TmhIncWidth'(count0)) begin
          $error("[%0t] %s: event %0d expected %0d, got %0d",
                 $time, name, i, count0, tmh_inc_o[i]);
          $fatal(1);
        end
      end else if (i == event1) begin
        if (tmh_inc_o[i] !== TmhIncWidth'(count1)) begin
          $error("[%0t] %s: event %0d expected %0d, got %0d",
                 $time, name, i, count1, tmh_inc_o[i]);
          $fatal(1);
        end
      end else if (tmh_inc_o[i] !== '0) begin
        $error("[%0t] %s: unexpected event %0d = %0d",
               $time, name, i, tmh_inc_o[i]);
        $fatal(1);
      end
    end
    $display("[%0t] PASS: %s", $time, name);
  endtask

  // ------------------------------------------------------------
  // VCD waveform
  // ------------------------------------------------------------
  initial begin
    $dumpfile("tmh_event_gen.vcd");
    $dumpvars(0, tb_tmh_event_gen);
  end

  // ------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------
  initial begin
    rst_ni          = 1'b0;
    clear_history_i = 1'b0;
    commit_ack_i    = '0;
    commit_instr_i  = '{default:'0};

    repeat (3) @(posedge clk_i);
    #1;
    rst_ni = 1'b1;

    // ----------------------------------------------------------
    // T1: First A only seeds history
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_A,
                1'b0, TMH_B,
                1'b0);
    expect_none("T1 first A seeds history");
    finish_cycle();

    // ----------------------------------------------------------
    // T2: A -> N = AN
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_N,
                1'b0, TMH_B,
                1'b0);
    expect_only(TMH_AN, 1, "T2 A->N gives AN=1");
    finish_cycle();

    // ----------------------------------------------------------
    // T3: Bubble. History N must be retained.
    // ----------------------------------------------------------
    drive_cycle(1'b0, TMH_B,
                1'b0, TMH_B,
                1'b0);
    expect_none("T3 bubble preserves history");
    finish_cycle();

    // ----------------------------------------------------------
    // T4: N -> L = NL
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_L,
                1'b0, TMH_B,
                1'b0);
    expect_only(TMH_NL, 1, "T4 N->L gives NL=1");
    finish_cycle();

    // ----------------------------------------------------------
    // T5: L -> L = LL=1
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_L,
                1'b0, TMH_B,
                1'b0);
    expect_only(TMH_LL, 1, "T5 L->L gives LL=1");
    finish_cycle();

    // ----------------------------------------------------------
    // T6: Important dual-commit case
    // Previous history is L. Both ports retire L.
    // Sequence is: old L -> port0 L -> port1 L
    // Therefore LL = 2 in ONE cycle.
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_L,
                1'b1, TMH_L,
                1'b0);
    expect_only(TMH_LL, 2, "T6 dual L,L gives LL=2");
    finish_cycle();

    // ----------------------------------------------------------
    // T7: clear_history has priority
    // Even though A/N are presented, no event is generated.
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_A,
                1'b1, TMH_N,
                1'b1);
    expect_none("T7 clear_history blocks event generation");
    finish_cycle();

    // ----------------------------------------------------------
    // T8: First L after clear only seeds history
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_L,
                1'b0, TMH_B,
                1'b0);
    expect_none("T8 first L after clear seeds history");
    finish_cycle();

    // ----------------------------------------------------------
    // T9: Two DIFFERENT events in one cycle
    // history=L, port0=A, port1=N
    //   L->A = LA
    //   A->N = AN
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_A,
                1'b1, TMH_N,
                1'b0);
    expect_two(TMH_LA, 1,
               TMH_AN, 1,
               "T9 dual A,N gives LA and AN");
    finish_cycle();

    // ----------------------------------------------------------
    // T10: N -> B = NB
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_B,
                1'b0, TMH_B,
                1'b0);
    expect_only(TMH_NB, 1, "T10 N->B gives NB=1");
    finish_cycle();

    // ----------------------------------------------------------
    // T11: history=B, port0=B, port1=N
    //   B->B = BB
    //   B->N = BN
    // ----------------------------------------------------------
    drive_cycle(1'b1, TMH_B,
                1'b1, TMH_N,
                1'b0);
    expect_two(TMH_BB, 1,
               TMH_BN, 1,
               "T11 dual B,N gives BB and BN");
    finish_cycle();

    $display("");
    $display("============================================");
    $display(" ALL DIRECTED TMH EVENT TESTS PASSED");
    $display(" Waveform: tmh_event_gen.vcd");
    $display("============================================");

    #20;
    $finish;
  end

endmodule
