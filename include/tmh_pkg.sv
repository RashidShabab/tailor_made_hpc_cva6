// -----------------------------------------------------------------------------
// TMH package used by tmh_event_gen.
// -----------------------------------------------------------------------------
package tmh_pkg;

  typedef enum logic [2:0] {
    TMH_B    = 3'd0,
    TMH_L    = 3'd1,
    TMH_S    = 3'd2,
    TMH_A    = 3'd3,
    TMH_N    = 3'd4,
    TMH_NONE = 3'd7
  } tmh_class_e;

  localparam int unsigned TMH_NUM_CLASSES = 5;
  localparam int unsigned TMH_NUM_PAIRS   = TMH_NUM_CLASSES * TMH_NUM_CLASSES;

  typedef enum int unsigned {
    TMH_BB =  0,
    TMH_BL =  1,
    TMH_BS =  2,
    TMH_BA =  3,
    TMH_BN =  4,

    TMH_LB =  5,
    TMH_LL =  6,
    TMH_LS =  7,
    TMH_LA =  8,
    TMH_LN =  9,

    TMH_SB = 10,
    TMH_SL = 11,
    TMH_SS = 12,
    TMH_SA = 13,
    TMH_SN = 14,

    TMH_AB = 15,
    TMH_AL = 16,
    TMH_AS = 17,
    TMH_AA = 18,
    TMH_AN = 19,

    TMH_NB = 20,
    TMH_NL = 21,
    TMH_NS = 22,
    TMH_NA = 23,
    TMH_NN = 24
  } tmh_pair_e;

  function automatic int unsigned tmh_pair_index(
    input tmh_class_e prev_class,
    input tmh_class_e curr_class
  );
    return (int'(prev_class) * TMH_NUM_CLASSES) + int'(curr_class);
  endfunction

endpackage

