
// SPDX-License-Identifier: Apache-2.0

//

// TMH event-generation datapath: classify, track, and match against the

// FULL 5x5 transition matrix over the B/L/S/A/N instruction alphabet

// (see tmh_pkg.sv). Every one of the 25 ordered adjacent-class pairs is

// counted every cycle via tmh_inc_o -- there is no fixed/hardwired subset

// and no CSR-selected subset; downstream analysis picks which pairs matter.



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



    output logic [TmhIncWidth-1:0] tmh_inc_o [TMH_NUM_PAIRS]

);



  function automatic logic is_boolean_op(input fu_op op);

    unique case (op)

      XORL, ORL, ANDL: return 1'b1;

      default:         return 1'b0;

    endcase

  endfunction



  function automatic tmh_class_e classify_instr(input scoreboard_entry_t instr);

    if (instr.fu == LOAD) begin

      return TMH_L;

    end



    if (instr.fu == STORE) begin

      return TMH_S;

    end



    if (instr.fu == CTRL_FLOW) begin

      return TMH_B;

    end



    if ((instr.fu == ALU) || (instr.fu == MULT)) begin

      if ((instr.fu == ALU) && is_boolean_op(instr.op)) begin

        return TMH_N;

      end

      return TMH_A;

    end



    return TMH_X;

  endfunction



  tmh_class_e [NrCommitPorts-1:0] instr_class;

  logic       [NrCommitPorts-1:0] instr_class_valid;



  always_comb begin : p_classify

    instr_class       = '{default: TMH_X};

    instr_class_valid = '0;



    for (int unsigned p = 0; p < NrCommitPorts; p++) begin

      instr_class_valid[p] = commit_ack_i[p];



      if (commit_ack_i[p]) begin

        instr_class[p] = classify_instr(commit_instr_i[p]);

      end

    end

  end



  tmh_class_e history_class_q, history_class_d;

  logic       history_valid_q, history_valid_d;



  tmh_class_e [NrCommitPorts-1:0] pair_prev;

  tmh_class_e [NrCommitPorts-1:0] pair_curr;

  logic       [NrCommitPorts-1:0] pair_valid;



  always_comb begin : p_track

    history_class_d = history_class_q;

    history_valid_d = history_valid_q;



    pair_prev  = '{default: TMH_X};

    pair_curr  = '{default: TMH_X};

    pair_valid = '0;



    if (clear_history_i) begin

      history_class_d = TMH_X;

      history_valid_d = 1'b0;

    end else begin

      for (int unsigned p = 0; p < NrCommitPorts; p++) begin

        if (instr_class_valid[p]) begin



          if (instr_class[p] == TMH_X) begin

            history_class_d = TMH_X;

            history_valid_d = 1'b0;



          end else begin

            if (history_valid_d) begin

              pair_prev[p]  = history_class_d;

              pair_curr[p]  = instr_class[p];

              pair_valid[p] = 1'b1;

            end



            history_class_d = instr_class[p];

            history_valid_d = 1'b1;

          end

        end

      end

    end

  end



  always_ff @(posedge clk_i or negedge rst_ni) begin : p_history_ff

    if (!rst_ni) begin

      history_class_q <= TMH_X;

      history_valid_q <= 1'b0;

    end else begin

      history_class_q <= history_class_d;

      history_valid_q <= history_valid_d;

    end

  end



  always_comb begin : p_match

    for (int unsigned i = 0; i < TMH_NUM_PAIRS; i++) begin

      logic [TmhIncWidth-1:0] match_count;

      match_count = '0;



      for (int unsigned p = 0; p < NrCommitPorts; p++) begin

        if (pair_valid[p] &&

            ((int'(pair_prev[p]) * TMH_NUM_CLASSES + int'(pair_curr[p])) == i)) begin

          match_count = match_count + 1'b1;

        end

      end



      tmh_inc_o[i] = match_count;

    end

  end



  // pragma translate_off

  initial begin

    assert (NrCommitPorts >= 1)

      else $fatal(1, "tmh_event_gen: NrCommitPorts must be >= 1");



    assert ((2**TmhIncWidth) > NrCommitPorts)

      else $fatal(1, "tmh_event_gen: TmhIncWidth is too small");

  end

  // pragma translate_on



endmodule

