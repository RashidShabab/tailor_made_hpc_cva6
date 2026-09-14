
// -----------------------------------------------------------------------------

// TMH package used by tmh_event_gen.

//

// Full prev -> curr transition matrix over a 5-class instruction alphabet:

//   B = branch/control-flow

//   L = load

//   S = store

//   A = arithmetic

//   N = Boolean

// A 6th class, TMH_X, is used internally by the classifier for anything

// outside this alphabet (CSR, FPU, AMO, accelerator, ...). TMH_X is never

// paired -- it only breaks sequence history, the same way TMH_CLASS_NONE

// did in the earlier 3-event design.

// -----------------------------------------------------------------------------

package tmh_pkg;



  typedef enum logic [2:0] {

    TMH_B = 3'd0,

    TMH_L = 3'd1,

    TMH_S = 3'd2,

    TMH_A = 3'd3,

    TMH_N = 3'd4,

    TMH_X = 3'd5   // outside the 5-class alphabet -- breaks adjacency only

  } tmh_class_e;



  localparam int unsigned TMH_NUM_CLASSES = 5;  // B,L,S,A,N only -- TMH_X is not paired



  // Event index = prev_index * TMH_NUM_CLASSES + curr_index, using the

  // B=0,L=1,S=2,A=3,N=4 ordering above. All 25 ordered pairs are tracked.

  localparam int unsigned TMH_BB = 0;

  localparam int unsigned TMH_BL = 1;

  localparam int unsigned TMH_BS = 2;

  localparam int unsigned TMH_BA = 3;

  localparam int unsigned TMH_BN = 4;



  localparam int unsigned TMH_LB = 5;

  localparam int unsigned TMH_LL = 6;

  localparam int unsigned TMH_LS = 7;

  localparam int unsigned TMH_LA = 8;

  localparam int unsigned TMH_LN = 9;



  localparam int unsigned TMH_SB = 10;

  localparam int unsigned TMH_SL = 11;

  localparam int unsigned TMH_SS = 12;

  localparam int unsigned TMH_SA = 13;

  localparam int unsigned TMH_SN = 14;



  localparam int unsigned TMH_AB = 15;

  localparam int unsigned TMH_AL = 16;

  localparam int unsigned TMH_AS = 17;

  localparam int unsigned TMH_AA = 18;

  localparam int unsigned TMH_AN = 19;



  localparam int unsigned TMH_NB = 20;

  localparam int unsigned TMH_NL = 21;

  localparam int unsigned TMH_NS = 22;

  localparam int unsigned TMH_NA = 23;

  localparam int unsigned TMH_NN = 24;



  localparam int unsigned TMH_NUM_PAIRS = TMH_NUM_CLASSES * TMH_NUM_CLASSES;  // 25



endpackage

