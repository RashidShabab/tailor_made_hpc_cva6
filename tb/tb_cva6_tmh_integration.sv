`timescale 1ns/1ps
`include "axi/typedef.svh"

// Executes a machine-code program on the real core over a small AXI RAM.
// The reference model decodes retired instruction bytes from RAM, independent
// of the monitor's functional-unit classifier and pair index constants.
module tb_cva6_tmh_integration #(parameter bit TmhEnabled = 1'b1);
  localparam config_pkg::cva6_cfg_t Cfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);
  typedef logic [Cfg.AxiAddrWidth-1:0] addr_t;
  typedef logic [Cfg.AxiDataWidth-1:0] data_t;
  typedef logic [Cfg.AxiDataWidth/8-1:0] strb_t;
  typedef logic [Cfg.AxiIdWidth-1:0] id_t;
  typedef logic [Cfg.AxiUserWidth-1:0] user_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  axi_req_t req;
  axi_resp_t rsp;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  cva6 #(.CVA6Cfg(Cfg), .TmhEn(TmhEnabled),
         .noc_req_t(axi_req_t), .noc_resp_t(axi_resp_t)) dut (
    .clk_i(clk), .rst_ni(rst_n), .boot_addr_i(64'h80000000),
    .hart_id_i('0), .irq_i('0), .ipi_i(1'b0), .time_irq_i(1'b0),
    .debug_req_i(1'b0), .rvfi_probes_o(), .cvxif_req_o(),
    .cvxif_resp_i('0), .noc_req_o(req), .noc_resp_i(rsp)
  );

  byte unsigned mem [0:8191];
  int cursor;
  // 0: counting, 1: disabled feature in M mode, 2/3: denied U/S accesses.
  int scenario = 0;
  longint unsigned wrong_pc, done_pc;
  function automatic logic [31:0] insn(input longint unsigned address);
    int off;
    off = int'(address - 64'h80000000);
    if (off < 0 || off > 8188) $fatal(1, "PC outside test RAM: %h", address);
    return {mem[off+3], mem[off+2], mem[off+1], mem[off]};
  endfunction
  task automatic emit(input logic [31:0] value);
    for (int b=0; b<4; b++) mem[cursor+b] = value[b*8+:8];
    cursor += 4;
  endtask
  function automatic logic [31:0] itype(input int imm, rs, f3, rd, op);
    return {12'(imm), 5'(rs), 3'(f3), 5'(rd), 7'(op)};
  endfunction
  function automatic logic [31:0] csrwi(input int address, value);
    return itype(address, value, 5, 0, 'h73);
  endfunction
  function automatic logic [31:0] csrr(input int address, rd);
    return itype(address, 0, 2, rd, 'h73);
  endfunction
  task automatic emit_class(input int class_id);
    case (class_id)
      0: emit(32'h0040006f); // jal x0,+4
      1: emit(itype(0,10,3,3,'h03)); // ld x3,0(x10)
      2: emit(32'h00453823); // sd x4,16(x10)
      3: emit(itype(1,5,0,5,'h13)); // addi
      4: emit(itype(7,5,4,6,'h13)); // xori
      default: $fatal(1,"Invalid stimulus class");
    endcase
  endtask

  initial begin
    void'($value$plusargs("SCENARIO=%d", scenario));
    foreach (mem[i]) mem[i] = 0;
    cursor = 0;
    if (scenario == 0) begin
    emit(32'h00001517); // auipc x10,1: data base 0x80001000
    emit(csrwi('h323, 20)); // mhpmevent3 = integer retired event
    emit(csrwi('hb03, 0));  // clear mhpmcounter3
    emit(csrwi('h7c3, 5)); // enable and clear
    emit(itype(5,0,0,1,'h13)); // A
    emit(itype(3,1,7,2,'h13)); // N
    emit(itype(0,10,3,3,'h03)); // L
    emit(itype(8,10,3,4,'h03)); // L
    // Dependent ALU instructions accumulate behind the delayed loads.
    repeat (12) emit(itype(1,5,0,5,'h13));
    emit(32'h00453823); // sd x4,16(x10): S
    emit(32'h00000463); // beq zero,zero,+8: B
    wrong_pc = 64'h80000000 + 64'(cursor);
    emit(itype(99,0,0,30,'h13)); // must be flushed
    emit(itype(7,5,4,6,'h13)); // xori: N
    // c.addi x5,1 followed by c.addi x5,1: two expanded arithmetic ops.
    emit(32'h02850285);
    emit(32'h0000000f); // fence: OTHER breaks adjacency
    emit(itype(1,0,0,7,'h13));
    emit(itype('h7c3,2,6,0,'h73)); // CSRRSI snapshot, preserve enable
    emit(csrr('h7c3, 20)); // pulse bits read zero, EN stays one
    emit(csrr('h7c7, 20)); // INFO
    for (int p=0; p<25; p++) begin
      emit(csrwi('h7c4, p));
      emit(csrr('h7c5, 21));
      emit(csrr('h7c6, 22));
    end
    emit(csrwi('h7c4,31)); // WARL clamp
    emit(csrr('h7c4,20));
    emit(itype('h7c3,1,7,0,'h73)); // CSRRCI clears EN
    emit(csrr('h7c3,20));
    emit(csrwi('h7c3, 7)); // clear + snapshot -> all zero
    emit(csrr('h7c5, 21));
    emit(csrwi('h7c3, 0)); // disable
    emit(itype(1,5,0,5,'h13));
    emit(itype(1,5,0,5,'h13));
    emit(csrwi('h7c3, 2)); // snapshot while disabled
    emit(csrr('h7c5, 21));
    emit(csrr('hb03,23)); // original HPM remains functional
    done_pc = 64'h80000000 + 64'(cursor);
    emit(itype(1,0,0,31,'h13));
    emit(32'h0000006f);
    end else if (scenario == 4) begin
      assert (TmhEnabled) else $fatal(1,"Matrix scenario requires TMH");
      emit(32'h00001517); // data base
      for (int first=0; first<5; first++) begin
        for (int second=0; second<5; second++) begin
          emit(csrwi('h7c3,5)); // clear counters and history, enable
          emit_class(first);
          emit_class(second);
          emit(csrwi('h7c3,3)); // snapshot
          emit(csrwi('h7c4,first*5+second));
          emit(csrr('h7c5,21));
          emit(csrr('h7c6,22));
        end
      end
      // Enable the architectural floating-point state (mstatus.FS=Dirty).
      emit(32'h00006437); // lui x8,6 -> 0x6000
      emit(itype('h300,8,2,0,'h73)); // csrs mstatus,x8
      emit(32'h3ff00437); // lui x8,0x3ff00
      emit(itype(32,8,1,8,'h13)); // slli x8,32 -> double 1.0
      emit(32'hf2040053); // fmv.d.x f0,x8
      emit(32'h020000d3); // fadd.d f1,f0,f0 -> double 2.0
      emit(32'he20084d3); // fmv.x.d x9,f1, checked at retirement
      done_pc=64'h80000000+64'(cursor);
      emit(itype(1,0,0,31,'h13));
      emit(32'h0000006f);
    end else begin
      assert ((scenario == 1 && !TmhEnabled) ||
              ((scenario == 2 || scenario == 3) && TmhEnabled))
        else $fatal(1,"Invalid access-test configuration");
      // mtvec = RAM+0x600; mepc = RAM+0x400.
      emit(32'h00000597); // auipc x11,0
      emit(itype('h600,11,0,11,'h13));
      emit(itype('h305,11,1,0,'h73)); // csrw mtvec,x11
      emit(32'h00000617); // auipc x12,0 at offset 12
      emit(itype('h400-12,12,0,12,'h13));
      emit(itype('h341,12,1,0,'h73)); // csrw mepc,x12
      emit(itype(-1,0,0,1,'h13));
      emit(itype('h3b0,1,1,0,'h73)); // pmpaddr0 = all ones
      emit(csrwi('h3a0,31)); // NAPOT RWX, allow lower privilege fetch
      if (scenario == 1) begin
        emit(32'h000020b7); // lui x1,2
        emit(itype(-2048,1,0,1,'h13)); // MPP=M (0x1800)
      end else if (scenario == 3) begin
        emit(32'h000010b7); // lui x1,1
        emit(itype(1,1,5,1,'h13)); // srli x1,x1,1: MPP=S
      end else emit(itype(0,0,0,1,'h13)); // MPP=U
      emit(itype('h300,1,1,0,'h73)); // csrw mstatus,x1
      emit(32'h30200073); // mret
      cursor='h400;
      emit(csrwi('h7c3,5)); // rejected write must not enable or clear TMH
      emit(csrr('h7c7,20)); // rejected read
      done_pc=64'h80000408;
      emit(itype(1,0,0,31,'h13));
      emit(32'h0000006f);
      cursor='h600;
      emit(csrr('h342,20)); // mcause = illegal instruction
      emit(csrr('h341,21)); // mepc = attempted access PC
      emit(itype(4,21,0,21,'h13));
      emit(itype('h341,21,1,0,'h73)); // advance mepc
      emit(32'h30200073); // return to same privilege
    end
    mem[4096] = 11;
    mem[4104] = 13;
    $dumpfile("cva6_tmh_integration.vcd");
    $dumpvars(0, tb_cva6_tmh_integration);
    repeat (8) @(negedge clk);
    rst_n = 1;
    repeat (20000) @(posedge clk);
    $fatal(1, "Full-core simulation timed out");
  end

  // One outstanding read and write, INCR bursts, byte strobes. Read latency
  // deliberately permits a backlog of completed instructions in the scoreboard.
  logic reading = 0, writing = 0, bvalid = 0;
  addr_t raddr, waddr;
  id_t rid, wid;
  int rleft, rsize, wsize, delay_count;
  always_comb begin
    rsp = '0;
    rsp.ar_ready = !reading;
    rsp.aw_ready = !writing && !bvalid;
    rsp.w_ready = writing;
    rsp.b_valid = bvalid;
    rsp.b.id = wid;
    rsp.r_valid = reading && delay_count == 0;
    rsp.r.id = rid;
    rsp.r.last = rleft == 0;
    for (int b=0; b<8; b++)
      rsp.r.data[8*b+:8] = mem[int'((raddr - 64'h80000000) & 64'h1ff8)+b];
  end
  always @(posedge clk) if (rst_n) begin
    if (req.ar_valid && rsp.ar_ready) begin
      reading <= 1;
      raddr <= req.ar.addr;
      rid <= req.ar.id;
      rleft <= int'(req.ar.len);
      rsize <= int'(req.ar.size);
      delay_count <= 12;
      assert (req.ar.burst == axi_pkg::BURST_INCR || req.ar.len == 0)
        else $fatal(1, "Unsupported read burst");
    end else if (reading && delay_count > 0) delay_count <= delay_count - 1;
    if (rsp.r_valid && req.r_ready) begin
      if (rleft == 0) reading <= 0;
      else begin raddr <= raddr + (64'd1 << rsize); rleft <= rleft - 1; end
    end
    if (req.aw_valid && rsp.aw_ready) begin
      writing <= 1; waddr <= req.aw.addr; wid <= req.aw.id;
      wsize <= int'(req.aw.size);
      assert (req.aw.atop == 0) else $fatal(1, "Unexpected AXI atomic");
    end
    if (req.w_valid && rsp.w_ready) begin
      for (int b=0; b<8; b++)
        if (req.w.strb[b]) mem[int'((waddr-64'h80000000) & 64'h1ff8)+b] <= req.w.data[b*8+:8];
      if (req.w.last) begin writing <= 0; bvalid <= 1; end
      else waddr <= waddr + (64'd1 << wsize);
    end
    if (rsp.b_valid && req.b_ready) bvalid <= 0;
  end

  function automatic int raw_class(input logic [31:0] instruction);
    if (instruction[1:0] != 2'b11) begin
      assert (instruction[15:0] == 16'h0285) else $fatal(1, "Unexpected compressed op");
      return 3;
    end
    case (instruction[6:0])
      'h63, 'h6f, 'h67: return 0;
      'h03: return 1;
      'h23: return 2;
      'h13: return instruction[14:12] inside {3'd4,3'd6,3'd7} ? 4 : 3;
      'h17, 'h37: return 3;
      default: return -1;
    endcase
  endfunction
  longint unsigned expected[25], shadow[25];
  int previous = -1, selected = 0, commits = 0, dual_cycles = 0, reads = 0;
  int traps = 0;
  bit was_trap = 0, hpm_enabled = 0;
  longint unsigned expected_hpm = 0;
  bit enabled = 0, finished = 0;
  bit [24:0] pair_coverage = '0;
  bit fpu_checked = 0;
  initial begin foreach(expected[i]) begin expected[i]=0; shadow[i]=0; end end
  always @(posedge clk) if (rst_n) begin
    // HPM integer event counts cycles with at least one ALU/MULT retirement.
    // The TMH address window must not suppress these original HPM updates.
    if (hpm_enabled && !dut.debug_mode &&
        !(dut.we_csr_perf && !dut.tmh_addr_hit)) begin
      bit integer_event;
      integer_event=0;
      for (int p=0; p<Cfg.NrCommitPorts; p++) begin
        // Do not evaluate the instruction reader on an inactive port.
        if (dut.commit_ack[p]) begin
          if (raw_class(insn(dut.commit_instr_id_commit[p].pc)) inside {3,4}) integer_event=1;
        end
      end
      if (integer_event) expected_hpm++;
    end
    if (&dut.commit_ack) dual_cycles++;
    for (int p=0; p<Cfg.NrCommitPorts; p++) begin
      if (dut.commit_ack[p]) begin
        automatic longint unsigned pc = dut.commit_instr_id_commit[p].pc;
        automatic logic [31:0] instruction = insn(pc);
        automatic int current = raw_class(instruction);
        commits++;
        assert (pc != wrong_pc) else $fatal(1, "Wrong-path instruction retired");
        if (enabled && previous >= 0 && current >= 0) begin
          expected[previous*5+current]++;
          pair_coverage[previous*5+current]=1;
        end
        previous = current;
        if (instruction[6:0] == 7'h73) begin
          if (instruction[14:12] inside {3'd5,3'd6,3'd7}) begin
            automatic int value = int'(instruction[19:15]);
            automatic int prior_value = instruction[31:20] == 12'h7c3 ? int'(enabled) : selected;
            if (instruction[14:12] == 6) value |= prior_value;
            if (instruction[14:12] == 7) value = prior_value & ~value;
            case (instruction[31:20])
              12'h7c3: begin
                if ((value & 4) != 0) begin
                  foreach(expected[i]) expected[i]=0;
                  previous=-1;
                end
                if ((value & 2) != 0) foreach(shadow[i]) shadow[i]=expected[i];
                enabled=1'(value);
              end
              12'h7c4: selected=(value & 31) > 24 ? 24 : (value & 31);
              12'h323: hpm_enabled = value == 20;
              12'hb03: expected_hpm=64'(value);
              default: if (scenario==0) $fatal(1,"Unexpected CSR write");
            endcase
          end else if (instruction[14:12] == 2 && instruction[19:15] == 0) begin
            automatic longint unsigned want;
            case (instruction[31:20])
              12'h7c5: want=64'(shadow[selected][31:0]);
              12'h7c6: want=64'(shadow[selected][63:32]);
              12'h7c7: want=64'h119;
              12'h7c3: want=64'(enabled);
              12'h7c4: want=64'(selected);
              12'hb03: want=expected_hpm;
              12'h342: want=2;
              12'h341: want=64'h80000400+(64'(traps)-1)*4;
              default: $fatal(1,"Unexpected CSR read");
            endcase
            assert (dut.wdata_commit_id[p] == want)
              else $fatal(1,"CSR %h selected=%0d got=%h expected=%h", instruction[31:20],selected,dut.wdata_commit_id[p],want);
            reads++;
            if (scenario==4 && instruction[31:20]==12'h7c5)
              assert (want==1) else $fatal(1,"Matrix stimulus did not produce exactly one selected pair");
          end
        end
        if (instruction==32'he20084d3) begin
          assert (dut.wdata_commit_id[p]==64'h4000000000000000)
            else $fatal(1,"FPU double addition expected 2.0, got %h",dut.wdata_commit_id[p]);
          fpu_checked=1;
        end
        if (pc == done_pc) finished=1;
      end
    end
    if (dut.ex_commit.valid) begin
      assert (scenario inside {1,2,3} && dut.ex_commit.cause==2 &&
              (dut.pc_commit==64'h80000400 || dut.pc_commit==64'h80000404))
        else $fatal(1,"Unexpected trap cause=%h pc=%h",dut.ex_commit.cause,dut.pc_commit);
      if (!was_trap) traps++;
    end
    was_trap=dut.ex_commit.valid;
    #2;
    assert (dut.gen_perf_counter.perf_counters_i.generic_counter_q[1] == expected_hpm)
      else $fatal(1,"Original HPM changed: got=%0d expected=%0d",dut.gen_perf_counter.perf_counters_i.generic_counter_q[1],expected_hpm);
    if (finished) begin
      if (scenario==0) begin
        assert (reads == 57 && dual_cycles > 0) else $fatal(1,"Missing coverage reads=%0d dual=%0d",reads,dual_cycles);
      end else if (scenario==4) begin
        assert (reads==50 && (&pair_coverage) && fpu_checked)
          else $fatal(1,"Matrix/FPU coverage missing reads=%0d pairs=%h fpu=%0d",reads,pair_coverage,fpu_checked);
        $display("PASS all 25 pair matches and FPU double addition 1.0+1.0=2.0");
      end else assert (reads==4 && traps==2 && !enabled)
        else $fatal(1,"Access test coverage missing reads=%0d traps=%0d",reads,traps);
      $display("PASS full CVA6 TMH scenario=%0d enabled=%0d: %0d retired instructions, %0d dual-commit cycles, %0d CSR reads, %0d expected traps",scenario,TmhEnabled,commits,dual_cycles,reads,traps);
      $finish;
    end
  end
  if (TmhEnabled) begin : check_tmh
    always @(posedge clk) if (rst_n) begin
      #1;
      foreach(expected[i]) begin
        assert (dut.gen_tmh.i_tmh.i_tmh_counter_bank.accum_q[i] == expected[i])
          else $fatal(1,"Live pair %0d mismatch got=%0d expected=%0d",i,dut.gen_tmh.i_tmh.i_tmh_counter_bank.accum_q[i],expected[i]);
      end
      assert (dut.gen_tmh.i_tmh.en == enabled) else $fatal(1,"TMH enable mismatch");
    end
  end
endmodule
