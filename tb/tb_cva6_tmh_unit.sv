// -----------------------------------------------------------------------------

// tb_cva6_tmh_unit.sv

//

// Directed, self-checking testbench for cva6_tmh_unit -- the CSR/counter

// layer wrapped around the already-Xcelium-verified tmh_event_gen. Reuses

// the same conventions as tb_tmh_event_gen_linear.sv (make_instr, the

// negedge-drive/posedge-settle discipline, $error+$fatal on mismatch,

// PASS per named check) so it reads as a natural extension of the

// existing suite, not a different style.

//

// tb_tmh_event_gen_linear.sv already covers classify/track/match

// exhaustively at the commit-bus level (T1-T11) -- this suite does NOT

// repeat that. It targets exactly the CSR/counter-bank behavior that

// only exists at this level: EN gating, the SEL WARL clamp, the

// snapshot/shadow atomicity guarantee (including the same-cycle

// corner case), and CLEAR-vs-unread-snapshot ordering -- the four gaps

// flagged in tmh-25event-csr-integration-spec.md, plus reset defaults,

// TMH_INFO read-only behavior, and one closing multi-pair integration

// check.

//

// NOTE: clear_history_i is NOT a top-level port on cva6_tmh_unit -- it is

// driven internally from a TMH_CTRL.CLEAR write. Every clear in this

// suite goes through the CSR bus, not a direct pin, unlike

// tb_tmh_event_gen_linear.sv.

// -----------------------------------------------------------------------------

 

`timescale 1ns/1ps

 

module tb_cva6_tmh_unit;

 

  import ariane_pkg::*;

  import tmh_pkg::*;

 

  // ------------------------------------------------------------

  // Standalone test configuration: two commit ports, 64-bit CSR bus.

  // ------------------------------------------------------------

  localparam int unsigned NrCommitPorts = 2;

  localparam int unsigned CsrDataWidth  = 64;

 

  localparam int unsigned TmhIncWidth =

      (NrCommitPorts <= 1) ? 1 : $clog2(NrCommitPorts + 1);

 

  // Minimal scoreboard entry for this unit test -- identical to

  // tb_tmh_event_gen_linear.sv's.

  typedef struct packed {

    ariane_pkg::fu_t  fu;

    ariane_pkg::fu_op op;

  } test_scoreboard_entry_t;

 

  logic clk_i;

  logic rst_ni;

 

  // Unpacked (dimension after the identifier) to match cva6_tmh_unit's

  // own commit_instr_i port exactly -- see the packing note in

  // cva6_tmh_unit.sv (a real Xcelium TYCMPAT elaboration issue with

  // parameter-type ports, not a style choice).

  test_scoreboard_entry_t commit_instr_i [NrCommitPorts];

  logic                    [NrCommitPorts-1:0] commit_ack_i;

 

  logic [11:0]              addr_i;

  logic                     we_i;

  logic [CsrDataWidth-1:0]  data_i;

  logic [CsrDataWidth-1:0]  csr_rdata_o;

  logic                     csr_addr_hit_o;

 

  // ------------------------------------------------------------

  // DUT

  // ------------------------------------------------------------

  cva6_tmh_unit #(

      .NrCommitPorts      (NrCommitPorts),

      .scoreboard_entry_t (test_scoreboard_entry_t),

      .CsrDataWidth       (CsrDataWidth),

      .TmhIncWidth        (TmhIncWidth)

  ) dut (

      .clk_i          (clk_i),

      .rst_ni         (rst_ni),

      .commit_instr_i (commit_instr_i),

      .commit_ack_i   (commit_ack_i),

      .addr_i         (addr_i),

      .we_i           (we_i),

      .data_i         (data_i),

      .csr_rdata_o    (csr_rdata_o),

      .csr_addr_hit_o (csr_addr_hit_o)

  );

 

  // ------------------------------------------------------------

  // Clock: 10 ns period

  // ------------------------------------------------------------

  initial begin

    clk_i = 1'b0;

    forever #5 clk_i = ~clk_i;

  end

 

  // ------------------------------------------------------------

  // Build an instruction belonging to one TMH class -- identical to

  // tb_tmh_event_gen_linear.sv's make_instr.

  // ------------------------------------------------------------

  function automatic test_scoreboard_entry_t make_instr(input tmh_class_e class_i);

    test_scoreboard_entry_t tmp;

    begin

      tmp = '0;

      unique case (class_i)

        TMH_B:   begin tmp.fu = CTRL_FLOW; tmp.op = BRANCH; end

        TMH_L:   begin tmp.fu = LOAD;      tmp.op = LD;     end

        TMH_S:   begin tmp.fu = STORE;     tmp.op = SD;     end

        TMH_A:   begin tmp.fu = ALU;       tmp.op = ADD;    end

        TMH_N:   begin tmp.fu = ALU;       tmp.op = ANDL;   end

        default: begin tmp = '0; end

      endcase

      return tmp;

    end

  endfunction

 

  // ------------------------------------------------------------

  // TMH_CTRL word builder: bit0=EN, bit1=SNAPSHOT, bit2=CLEAR.

  // Always pass the EN value you want to PERSIST -- SNAPSHOT/CLEAR are

  // one-cycle pulses layered on top of whatever EN state you specify,

  // they do not implicitly preserve a previously-written EN on their own.

  // ------------------------------------------------------------

  function automatic logic [63:0] ctrl_word(input logic en, input logic snap, input logic clr);

    ctrl_word = {61'b0, clr, snap, en};

  endfunction

 

  // ------------------------------------------------------------

  // Pure commit-bus driving, no CSR access -- same rhythm as

  // tb_tmh_event_gen_linear.sv's drive_cycle/finish_cycle, minus

  // clear_history_i (not a direct port here, see file header note).

  // ------------------------------------------------------------

  task automatic drive_cycle(

      input logic       ack0, input tmh_class_e class0,

      input logic       ack1, input tmh_class_e class1

  );

    @(negedge clk_i);

    commit_ack_i[0]   = ack0;

    commit_ack_i[1]   = ack1;

    commit_instr_i[0] = make_instr(class0);

    commit_instr_i[1] = make_instr(class1);

    #1;

  endtask

 

  task automatic finish_cycle;

    @(posedge clk_i);

    #0.1;

    commit_ack_i   = '0;

    commit_instr_i = '{default: '0};

  endtask

 

  // ------------------------------------------------------------

  // Pure CSR write/read, no commit activity in the same cycle.

  // ------------------------------------------------------------

  task automatic csr_write(input logic [11:0] addr, input logic [63:0] wdata);

    @(negedge clk_i);

    addr_i = addr;

    we_i   = 1'b1;

    data_i = wdata;

    #1;

    @(posedge clk_i);

    #0.1;

    we_i = 1'b0;

  endtask

 

  task automatic csr_read(input logic [11:0] addr, output logic [63:0] rdata);

    addr_i = addr;

    we_i   = 1'b0;

    #1;

    rdata  = csr_rdata_o;

  endtask

 

  // ------------------------------------------------------------

  // The one composite action: a commit AND a CSR write in the SAME

  // cycle -- exists only to drive test U5, the same-cycle corner case.

  // ------------------------------------------------------------

  task automatic drive_commit_and_ctrl_write(

      input logic       ack0, input tmh_class_e class0,

      input logic       ack1, input tmh_class_e class1,

      input logic [63:0] ctrl_wdata

  );

    @(negedge clk_i);

    commit_ack_i[0]   = ack0;

    commit_ack_i[1]   = ack1;

    commit_instr_i[0] = make_instr(class0);

    commit_instr_i[1] = make_instr(class1);

    addr_i = TMH_CTRL_ADDR;

    we_i   = 1'b1;

    data_i = ctrl_wdata;

    #1;

    @(posedge clk_i);

    #0.1;

    commit_ack_i   = '0;

    commit_instr_i = '{default: '0};

    we_i           = 1'b0;

  endtask

 

  // ------------------------------------------------------------

  // Read the shadow counter at index idx: one CSR write (select) +

  // two CSR reads (lo/hi), reassembled into 64 bits.

  // ------------------------------------------------------------

  task automatic read_count(input int unsigned idx, output logic [63:0] cnt);

    logic [63:0] lo, hi;

    csr_write(TMH_SEL_ADDR, 64'(idx));

    csr_read(TMH_CNT_LO_ADDR, lo);

    csr_read(TMH_CNT_HI_ADDR, hi);

    cnt = {hi[31:0], lo[31:0]};

  endtask

 

  // ------------------------------------------------------------

  // Self-check helpers

  // ------------------------------------------------------------

  task automatic expect_count(input int unsigned idx, input logic [63:0] want, input string name);

    logic [63:0] got;

    read_count(idx, got);

    if (got !== want) begin

      $error("[%0t] %s: TMH_CNT[%0d] expected %0d, got %0d", $time, name, idx, want, got);

      $fatal(1);

    end

    $display("[%0t] PASS: %s", $time, name);

  endtask

 

  task automatic expect_sel(input logic [4:0] want, input string name);

    logic [63:0] got;

    csr_read(TMH_SEL_ADDR, got);

    if (got[4:0] !== want) begin

      $error("[%0t] %s: TMH_SEL expected %0d, got %0d", $time, name, want, got[4:0]);

      $fatal(1);

    end

    $display("[%0t] PASS: %s", $time, name);

  endtask

 

  task automatic expect_info(input string name);

    logic [63:0] got;

    csr_read(TMH_INFO_ADDR, got);

    if ((got[7:0] !== 8'd25) || (got[15:8] !== 8'd1)) begin

      $error("[%0t] %s: TMH_INFO expected {VERSION=1,NUM_PAIRS=25}, got {%0d,%0d}",

             $time, name, got[15:8], got[7:0]);

      $fatal(1);

    end

    $display("[%0t] PASS: %s", $time, name);

  endtask

 

  task automatic expect_ctrl_en(input logic want, input string name);

    logic [63:0] got;

    csr_read(TMH_CTRL_ADDR, got);

    if (got[0] !== want) begin

      $error("[%0t] %s: TMH_CTRL.EN expected %0d, got %0d", $time, name, want, got[0]);

      $fatal(1);

    end

    $display("[%0t] PASS: %s", $time, name);

  endtask

 

  // ------------------------------------------------------------

  // VCD waveform

  // ------------------------------------------------------------

  initial begin

    $dumpfile("cva6_tmh_unit.vcd");

    $dumpvars(0, tb_cva6_tmh_unit);

  end

 

  // ------------------------------------------------------------

  // Test sequence

  // ------------------------------------------------------------

  initial begin

    logic [63:0] rdata;

    bit en_state;

 

    rst_ni         = 1'b0;

    commit_ack_i   = '0;

    commit_instr_i = '{default: '0};

    addr_i         = '0;

    we_i           = 1'b0;

    data_i         = '0;

    en_state       = 1'b0;

 

    repeat (3) @(posedge clk_i);

    #1;

    rst_ni = 1'b1;

 

    // ----------------------------------------------------------

    // U1: reset defaults -- INFO fixed, CTRL/SEL zero, shadow zero

    // ----------------------------------------------------------

    expect_info("U1a TMH_INFO reads {VERSION=1,NUM_PAIRS=25} at reset");

    csr_read(TMH_CTRL_ADDR, rdata);

    if (rdata !== '0) begin

      $error("[%0t] U1b: TMH_CTRL expected 0 at reset, got %0d", $time, rdata);

      $fatal(1);

    end

    $display("[%0t] PASS: U1b TMH_CTRL reads 0 at reset", $time);

    expect_sel(5'd0, "U1c TMH_SEL reads 0 at reset");

    expect_count(TMH_LL, 64'd0, "U1d shadow counters read 0 at reset");

 

    // ----------------------------------------------------------

    // U2: EN=0 (still the reset default) blocks counting even though

    // tmh_event_gen is classifying/tracking underneath it.

    // ----------------------------------------------------------

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // seeds history = L

    finish_cycle();

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // L->L match inside tmh_event_gen,

    finish_cycle();                          // but EN=0 so it must not accumulate

    csr_write(TMH_CTRL_ADDR, ctrl_word(1'b0, 1'b1, 1'b0));  // snapshot, EN stays 0

    expect_count(TMH_LL, 64'd0, "U2 EN=0 blocks counting despite a real LL match");

 

    // ----------------------------------------------------------

    // U3: enable, then confirm live counting across two snapshots

    // ----------------------------------------------------------

    csr_write(TMH_CTRL_ADDR, ctrl_word(1'b1, 1'b0, 1'b0));

    en_state = 1'b1;

    expect_ctrl_en(1'b1, "U3a TMH_CTRL.EN reads back 1 after enabling");

 

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // history already L -> LL match, EN=1

    finish_cycle();

    csr_write(TMH_CTRL_ADDR, ctrl_word(en_state, 1'b1, 1'b0));

    expect_count(TMH_LL, 64'd1, "U3b first live increment counted");

 

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // another LL match

    finish_cycle();

    csr_write(TMH_CTRL_ADDR, ctrl_word(en_state, 1'b1, 1'b0));

    expect_count(TMH_LL, 64'd2, "U3c second live increment counted");

 

    // ----------------------------------------------------------

    // U4: TMH_SEL is WARL-clamped to 24 (TMH_NUM_PAIRS-1)

    // ----------------------------------------------------------

    csr_write(TMH_SEL_ADDR, 64'd31);

    expect_sel(5'd24, "U4a SEL=31 clamps to 24");

    csr_write(TMH_SEL_ADDR, 64'd25);

    expect_sel(5'd24, "U4b SEL=25 clamps to 24");

    csr_write(TMH_SEL_ADDR, 64'd24);

    expect_sel(5'd24, "U4c SEL=24 (legal max) stays 24");

    csr_write(TMH_SEL_ADDR, 64'd0);

    expect_sel(5'd0, "U4d SEL=0 stays 0");

 

    // ----------------------------------------------------------

    // U5: the corner case -- a commit-side match and a TMH_CTRL

    // SNAPSHOT write happen in the SAME cycle. The snapshot must

    // capture the post-increment value (3), not the pre-increment

    // value (2) -- this is the accum_d-vs-accum_q distinction called

    // out in the integration spec. History is still L from U3, so

    // this commit produces one more LL match.

    // ----------------------------------------------------------

    drive_commit_and_ctrl_write(

        1'b1, TMH_L, 1'b0, TMH_B,

        ctrl_word(en_state, 1'b1, 1'b0)

    );

    expect_count(TMH_LL, 64'd3, "U5 snapshot captures same-cycle commit (accum_d, not accum_q)");

 

    // ----------------------------------------------------------

    // U6: CLEAR zeroes the live accumulators and resets

    // tmh_event_gen's history, but must NOT touch the shadow array --

    // the last snapshot (3) must still be readable until the next

    // snapshot overwrites it.

    // ----------------------------------------------------------

    csr_write(TMH_CTRL_ADDR, ctrl_word(en_state, 1'b0, 1'b1));

    expect_count(TMH_LL, 64'd3, "U6a shadow survives CLEAR until the next snapshot");

 

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // history invalid after clear -> seeds only

    finish_cycle();

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // now L->L match, on a freshly-zeroed accum

    finish_cycle();

    csr_write(TMH_CTRL_ADDR, ctrl_word(en_state, 1'b1, 1'b0));

    expect_count(TMH_LL, 64'd1, "U6b live accumulator truly restarted from 0 after CLEAR");

 

    // ----------------------------------------------------------

    // U7: TMH_INFO is read-only -- a write to it must be a no-op, and

    // must not corrupt CTRL/SEL either (a wrong address-hit decode is

    // exactly the kind of bug this would catch).

    // ----------------------------------------------------------

    csr_write(TMH_INFO_ADDR, 64'hFFFF_FFFF_FFFF_FFFF);

    expect_info("U7a TMH_INFO unchanged after a write attempt");

    expect_ctrl_en(1'b1, "U7b TMH_CTRL.EN unaffected by a write to TMH_INFO");

    expect_sel(5'(TMH_LL), "U7c TMH_SEL unaffected by a write to TMH_INFO");

 

    // ----------------------------------------------------------

    // U8: closing integration check -- a short mixed sequence across

    // several distinct pairs, one snapshot, then walk multiple

    // indices including ones that should read back zero.

    // ----------------------------------------------------------

    csr_write(TMH_CTRL_ADDR, ctrl_word(en_state, 1'b0, 1'b1));  // clean slate

 

    drive_cycle(1'b1, TMH_A, 1'b0, TMH_B);   // seeds history = A

    finish_cycle();

    drive_cycle(1'b1, TMH_N, 1'b0, TMH_B);   // A->N

    finish_cycle();

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // N->L

    finish_cycle();

    drive_cycle(1'b1, TMH_L, 1'b0, TMH_B);   // L->L

    finish_cycle();

    drive_cycle(1'b1, TMH_B, 1'b0, TMH_B);   // L->B

    finish_cycle();

 

    csr_write(TMH_CTRL_ADDR, ctrl_word(en_state, 1'b1, 1'b0));

 

    expect_count(TMH_AN, 64'd1, "U8a AN counted");

    expect_count(TMH_NL, 64'd1, "U8b NL counted");

    expect_count(TMH_LL, 64'd1, "U8c LL counted");

    expect_count(TMH_LB, 64'd1, "U8d LB counted");

    expect_count(TMH_BB, 64'd0, "U8e BB correctly untouched");

    expect_count(TMH_AA, 64'd0, "U8f AA correctly untouched");

 

    $display("");

    $display("============================================");

    $display(" ALL CVA6_TMH_UNIT DIRECTED TESTS PASSED");

    $display(" Waveform: cva6_tmh_unit.vcd");

    $display("============================================");

 

    #20;

    $finish;

  end

 

endmodule
