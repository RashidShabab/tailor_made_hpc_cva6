// -----------------------------------------------------------------------------
// MINIMAL ariane_pkg stub for standalone tmh_event_gen unit testing.
//
// IMPORTANT:
//   This is NOT a replacement for CVA6's real ariane_pkg.
//   It contains only the types/enumerators used by tmh_event_gen and the
//   linear testbench.
//
//   When compiling inside the real CVA6 repository, use CVA6's real
//   ariane_pkg instead and REMOVE this file from the compile list.
// -----------------------------------------------------------------------------
package ariane_pkg;

  // Functional-unit class used by the TMH classifier.
  // Only values needed by this unit test are included.
  typedef enum logic [3:0] {
    ALU       = 4'd0,
    CTRL_FLOW = 4'd1,
    MULT      = 4'd2,
    CSR       = 4'd3,
    LOAD      = 4'd4,
    STORE     = 4'd5,
    FPU       = 4'd6,
    ACCEL     = 4'd7
  } fu_t;

  // Functional-unit operation.
  // tmh_event_gen only distinguishes XORL/ORL/ANDL from other ALU ops.
  typedef enum logic [7:0] {
    ADD  = 8'd0,
    SUB  = 8'd1,
    XORL = 8'd2,
    ORL  = 8'd3,
    ANDL = 8'd4,
    MUL  = 8'd5
  } fu_op;

endpackage
