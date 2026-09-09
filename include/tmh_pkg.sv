// -----------------------------------------------------------------------------
// TMH package used by tmh_event_gen.
// -----------------------------------------------------------------------------
package tmh_pkg;

  // Reduced instruction alphabet:
  //   B = branch/control-flow
  //   L = load
  //   S = store
  //   A = arithmetic
  //   N = Boolean
  // NONE means the committed instruction is outside the monitored alphabet.
  typedef enum logic [2:0] {
    TMH_CLASS_NONE   = 3'd0,
    TMH_CLASS_BRANCH = 3'd1,
    TMH_CLASS_LOAD   = 3'd2,
    TMH_CLASS_STORE  = 3'd3,
    TMH_CLASS_ARITH  = 3'd4,
    TMH_CLASS_BOOL   = 3'd5
  } tmh_class_e;

  // Current sequence-based TMH events.
  localparam int unsigned TMH_LL_IDX = 0;  // LOAD  -> LOAD
  localparam int unsigned TMH_AN_IDX = 1;  // ARITH -> BOOL
  localparam int unsigned TMH_AS_IDX = 2;  // ARITH -> STORE

  localparam int unsigned TMH_NUM_EVENTS = 3;

endpackage
