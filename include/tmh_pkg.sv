
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

// CSR addresses, machine custom read/write range (0x7C0-0x7FF).

// 0x7C0/0x7C1/0x7C2 are real CVA6's CSR_ICACHE/CSR_DCACHE/CSR_ACC_CONS.

// 0x7C3-0x7C7 are this block's window; 0x7C8-0x7FF stay free for DFDTMH.

  localparam logic [11:0] TMH_CTRL_ADDR   = 12'h7C3;
  
  localparam logic [11:0] TMH_SEL_ADDR    = 12'h7C4;
  
  localparam logic [11:0] TMH_CNT_LO_ADDR = 12'h7C5;
  
  localparam logic [11:0] TMH_CNT_HI_ADDR = 12'h7C6;
  
  localparam logic [11:0] TMH_INFO_ADDR   = 12'h7C7;

 

// TMH_SEL is 5 bits (covers 0-31); only 0-24 are legal indices into the

// 25-entry matrix. Out-of-range writes clamp to this value (WARL --

// write-any-read-legal, must never trap per RISC-V CSR convention).

  localparam logic [4:0]  TMH_SEL_MAX        = 5'd24;

 

// TMH_INFO fixed fields -- let software discover the matrix size and

// register-layout revision instead of hardcoding either.

  localparam logic [7:0]  TMH_INFO_NUM_PAIRS = 8'(TMH_NUM_PAIRS); // = 25

  localparam logic [7:0]  TMH_INFO_VERSION   = 8'd1;

endpackage

