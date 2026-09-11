// Copyright ...
//
// tmh_event_gen.sv
//
// Tailor-Made Hardware Performance Counter (TMH) event generator
//
// Detects consecutive retired instruction-class pairs:
//
//      B = Branch / Jump
//      L = Load
//      S = Store
//      A = Arithmetic
//      N = Boolean
//
// Generates all 25 possible two-instruction sequences:
//
//      BB BL BS BA BN
//      LB LL LS LA LN
//      SB SL SS SA SN
//      AB AL AS AA AN
//      NB NL NS NA NN
//
// IMPORTANT:
//   * Only architecturally committed instructions are observed.
//   * commit ports are processed in retirement order.
//   * Multiple occurrences of the same TMH can happen in one cycle.
//     Example:
//          previous = L
//          port0    = L
//          port1    = L
//
//     => LL occurs twice in the same cycle.
//   * Therefore tmh_inc_o is an increment value, not simply a 1-bit pulse.
//

module tmh_event_gen
  import ariane_pkg::*;
  import tmh_pkg::*;
#(
//    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
     
      parameter int unsigned NrCommitPorts = 2
    // Scoreboard entry type from CVA6
    parameter type scoreboard_entry_t = logic,

    // Width required to represent 0 .. NrCommitPorts occurrences.
    //
    // NrCommitPorts = 1 -> width 1
    // NrCommitPorts = 2 -> width 2, can represent 0/1/2
//    parameter int unsigned TmhIncWidth =
//        (CVA6Cfg.NrCommitPorts <= 1)
//            ? 1
//            : $clog2(CVA6Cfg.NrCommitPorts + 1)

     parameter int unsigned TmhIncWidth =
        (NrCommitPorts <= 1)
            ? 1
            : $clog2(NrCommitPorts + 1)

) (

    input logic clk_i,
    input logic rst_ni,

    // ------------------------------------------------------------
    // Commit interface from CVA6 scoreboard / commit stage
    // ------------------------------------------------------------

    input scoreboard_entry_t [NrCommitPorts-1:0]
        commit_instr_i,

    input logic [NrCommitPorts-1:0]
        commit_ack_i,

    // ------------------------------------------------------------
    // Explicit sequence-history clear
    //
    // Can later be asserted at:
    //   * beginning of a sampling window
    //   * process/context boundary
    //   * software-controlled TMH reset
    //
    // If not used yet, tie this input to 1'b0.
    // ------------------------------------------------------------

    input logic clear_history_i,

    // ------------------------------------------------------------
    // TMH event increments
    //
    // tmh_inc_o[TMH_LL] = number of LL occurrences this cycle
    // tmh_inc_o[TMH_AN] = number of AN occurrences this cycle
    // ...
    //
    // Each entry can be 0 .. CVA6Cfg.NrCommitPorts.
    // ------------------------------------------------------------

    output logic [TmhIncWidth-1:0]
        tmh_inc_o [TMH_NUM_PAIRS]

);


    // ============================================================
    // Internal sequence-history registers
    // ============================================================

    tmh_class_e history_class_q;
    tmh_class_e history_class_d;

    logic history_valid_q;
    logic history_valid_d;


    // ============================================================
    // Boolean instruction classifier
    // ============================================================
    //
    // For the first implementation we treat the basic RISC-V
    // logical operations as Boolean instructions.
    //
    // Other ALU instructions are classified as arithmetic.
    //
    // We can extend this later for RVB instructions if required.
    // ============================================================

    function automatic logic is_boolean_op(
        input ariane_pkg::fu_op op_i
    );

        begin

            unique case (op_i)

                XORL,
                ORL,
                ANDL:
                    is_boolean_op = 1'b1;

                default:
                    is_boolean_op = 1'b0;

            endcase

        end

    endfunction


    // ============================================================
    // Instruction classifier
    // ============================================================
    //
    // Converts a retired CVA6 scoreboard entry into:
    //
    //          B / L / S / A / N
    //
    // Unsupported instruction classes return TMH_NONE.
    //
    // Classification priority is important.
    //
    // For example a JAL may internally use an ADD-like operation,
    // but its functional unit is CTRL_FLOW, so it must be B.
    // ============================================================

    function automatic tmh_class_e classify_instr(
        input scoreboard_entry_t instr_i
    );

        begin

            unique case (instr_i.fu)

                // ------------------------------------------------
                // Branch / jump
                // ------------------------------------------------
                CTRL_FLOW:
                    classify_instr = TMH_B;


                // ------------------------------------------------
                // Load
                // ------------------------------------------------
                LOAD:
                    classify_instr = TMH_L;


                // ------------------------------------------------
                // Store
                // ------------------------------------------------
                STORE:
                    classify_instr = TMH_S;


                // ------------------------------------------------
                // Integer ALU
                //
                // Separate Boolean operations from the remaining
                // arithmetic/ALU operations.
                // ------------------------------------------------
                ALU: begin

                    if (is_boolean_op(instr_i.op))
                        classify_instr = TMH_N;
                    else
                        classify_instr = TMH_A;

                end


                // ------------------------------------------------
                // Multiply / divide operations
                //
                // Count these as arithmetic.
                // ------------------------------------------------
                MULT:
                    classify_instr = TMH_A;


                // ------------------------------------------------
                // Everything else currently lies outside our
                // B/L/S/A/N classification.
                //
                // Examples:
                //      CSR
                //      FPU
                //      FPU_VEC
                //      CVXIF
                //      ACCEL
                //      AES
                // ------------------------------------------------
                default:
                    classify_instr = TMH_NONE;

            endcase

        end

    endfunction


    // ============================================================
    // TMH sequence detection
    // ============================================================
    //
    // The fundamental operation is:
    //
    //      previous instruction class -> current instruction class
    //
    // Example:
    //
    //      previous = A
    //      current  = N
    //
    //              AN += 1
    //
    //
    // Multiple commit ports are processed sequentially inside the
    // combinational next-state logic.
    //
    // Example:
    //
    //      history before cycle = A
    //
    //      commit port 0 = N
    //      commit port 1 = L
    //
    //      resulting sequences:
    //
    //          A -> N     => AN
    //          N -> L     => NL
    //
    //      final history = L
    //
    // ============================================================

    always_comb begin : p_tmh_sequence_detection

        tmh_class_e current_class;
        int unsigned pair_idx;

        // --------------------------------------------------------
        // Default outputs
        // --------------------------------------------------------

        tmh_inc_o = '{default: '0};

        // Hold history unless something retires
        history_class_d = history_class_q;
        history_valid_d = history_valid_q;


        // --------------------------------------------------------
        // Explicit history clear
        // --------------------------------------------------------

        if (clear_history_i) begin

            history_class_d = TMH_NONE;
            history_valid_d = 1'b0;

        end else begin

            // ----------------------------------------------------
            // Process retirement ports IN ORDER.
            //
            // Port 0 must be processed before port 1.
            //
            // We intentionally use history_class_d here instead
            // of history_class_q because history_class_d is
            // updated immediately after processing each port.
            //
            // Therefore:
            //
            //      old history -> port0 -> port1
            //
            // can all be observed in a single clock cycle.
            // ----------------------------------------------------

            for (
                int unsigned p = 0;
                p < NrCommitPorts;
                p++
            ) begin

                // ------------------------------------------------
                // Only architecturally committed instructions
                // participate.
                // ------------------------------------------------

                if (commit_ack_i[p]) begin

                    current_class =
                        classify_instr(commit_instr_i[p]);


                    // ============================================
                    // Unsupported instruction
                    // ============================================
                    //
                    // We break sequence adjacency here.
                    //
                    // Example:
                    //
                    //      A
                    //      CSR
                    //      N
                    //
                    // must NOT become:
                    //
                    //      AN
                    //
                    // because A and N were not consecutive retired
                    // B/L/S/A/N instructions in the architectural
                    // instruction stream.
                    // ============================================

                    if (current_class == TMH_NONE) begin

                        history_class_d = TMH_NONE;
                        history_valid_d = 1'b0;

                    end else begin


                        // ========================================
                        // Previous valid instruction exists
                        // ========================================

                        if (history_valid_d) begin

                            // ------------------------------------
                            // Convert XY into a 0..24 index.
                            //
                            // With:
                            //
                            //      B = 0
                            //      L = 1
                            //      S = 2
                            //      A = 3
                            //      N = 4
                            //
                            // index =
                            //
                            //      previous * 5 + current
                            //
                            // Examples:
                            //
                            // BB = 0*5 + 0 = 0
                            // LL = 1*5 + 1 = 6
                            // AN = 3*5 + 4 = 19
                            // NN = 4*5 + 4 = 24
                            // ------------------------------------

                            pair_idx =
                                tmh_pair_index(
                                    history_class_d,
                                    current_class
                                );


                            // ------------------------------------
                            // Increment corresponding TMH event.
                            //
                            // This is ADDITION, not assignment to 1.
                            //
                            // That distinction is important when
                            // two retirement ports create the same
                            // sequence in one cycle.
                            //
                            // Example:
                            //
                            // history = L
                            // port0   = L
                            // port1   = L
                            //
                            // tmh_inc_o[TMH_LL] becomes 2.
                            // ------------------------------------

                            tmh_inc_o[pair_idx] =
                                tmh_inc_o[pair_idx]
                                + TmhIncWidth'(1);

                        end


                        // ========================================
                        // Current instruction becomes history
                        // ========================================

                        history_class_d = current_class;
                        history_valid_d = 1'b1;

                    end

                end

                // ------------------------------------------------
                // If commit_ack_i[p] == 0:
                //
                // this is simply a bubble / no retirement.
                //
                // We intentionally do NOT clear history.
                //
                // Example:
                //
                // cycle 1 : A retires
                // cycle 2 : nothing retires
                // cycle 3 : N retires
                //
                // Architectural sequence is still A -> N.
                // ------------------------------------------------

            end

        end

    end


    // ============================================================
    // History registers
    // ============================================================

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin

            history_class_q <= TMH_NONE;
            history_valid_q <= 1'b0;

        end else begin

            history_class_q <= history_class_d;
            history_valid_q <= history_valid_d;

        end
    end


endmodule
