// -----------------------------------------------------------------------------

// tmh_csr.sv

//

// Register decode for the TMH 25-event counter-bank CSR window

// (TMH_CTRL / TMH_SEL / TMH_CNT_LO / TMH_CNT_HI / TMH_INFO, addresses

// 0x7C3-0x7C7). Owns the EN and SEL register state; SNAPSHOT and CLEAR

// are pure one-cycle write-strobes with no storage of their own -- they

// always read back 0, so a driver never has to poll a "done" bit.

//

// Generic CSR bus convention matches perf_counters.sv's own existing

// addr_i/we_i/data_i/data_o ports directly -- see

// tmh-rtl-architecture-reference.md and

// tmh-25event-csr-integration-spec.md for the additive hook-in (one

// instance of cva6_tmh_unit + one OR'd address-hit term, no change to

// perf_counters.sv's existing generic-counter logic).

//

// CsrDataWidth is parameterized (not hardcoded to 64) so this drops into

// either an RV32 or RV64 CVA6 config unchanged -- every field here fits

// well within 32 bits, the parameter just controls how much of the read

// mux's output is zero-padding.

// -----------------------------------------------------------------------------

 

module tmh_csr

  import tmh_pkg::*;

#(

    parameter int unsigned CsrDataWidth = 64

) (

    input  logic                      clk_i,

    input  logic                      rst_ni,

 

    // Generic CSR bus, wired directly to perf_counters.sv's own ports.

    input  logic [11:0]               addr_i,

    input  logic                      we_i,

    input  logic [CsrDataWidth-1:0]   data_i,

    output logic [CsrDataWidth-1:0]   csr_rdata_o,

    output logic                      csr_addr_hit_o,

 

    // To tmh_counter_bank.

    output logic                      en_o,

    output logic                      snapshot_o,

    output logic                      clear_o,

    output logic [4:0]                sel_o,

 

    // From tmh_counter_bank -- the currently-selected shadow counter.

    input  logic [63:0]               cnt_i

);

 

  logic       ctrl_en_q, ctrl_en_d;

  logic [4:0] sel_q, sel_d;

 

  logic hit_ctrl, hit_sel, hit_cnt_lo, hit_cnt_hi, hit_info;

 

  assign hit_ctrl   = (addr_i == TMH_CTRL_ADDR);

  assign hit_sel    = (addr_i == TMH_SEL_ADDR);

  assign hit_cnt_lo = (addr_i == TMH_CNT_LO_ADDR);

  assign hit_cnt_hi = (addr_i == TMH_CNT_HI_ADDR);

  assign hit_info   = (addr_i == TMH_INFO_ADDR);

 

  assign csr_addr_hit_o = hit_ctrl | hit_sel | hit_cnt_lo | hit_cnt_hi | hit_info;

 

  // ---------------------------------------------------------------------

  // TMH_CTRL: bit0 = EN (stored, resets to 0 -- counting is an explicit

  // software action, not a boot-time default), bit1 = SNAPSHOT (pulse,

  // not stored), bit2 = CLEAR (pulse, not stored).

  // ---------------------------------------------------------------------

  assign ctrl_en_d  = (we_i && hit_ctrl) ? data_i[0] : ctrl_en_q;

  assign snapshot_o = we_i && hit_ctrl && data_i[1];

  assign clear_o    = we_i && hit_ctrl && data_i[2];

  assign en_o       = ctrl_en_q;

 

  // ---------------------------------------------------------------------

  // TMH_SEL: bits[4:0] = IDX, WARL-clamped to TMH_SEL_MAX (24) on write

  // so an out-of-range index can never be latched.

  // ---------------------------------------------------------------------

  always_comb begin

    if (we_i && hit_sel) begin

      sel_d = (data_i[4:0] > TMH_SEL_MAX) ? TMH_SEL_MAX : data_i[4:0];

    end else begin

      sel_d = sel_q;

    end

  end

  assign sel_o = sel_q;

 

  always_ff @(posedge clk_i or negedge rst_ni) begin

    if (!rst_ni) begin

      ctrl_en_q <= 1'b0;

      sel_q     <= 5'd0;

    end else begin

      ctrl_en_q <= ctrl_en_d;

      sel_q     <= sel_d;

    end

  end

 

  // ---------------------------------------------------------------------

  // Read mux. SNAPSHOT/CLEAR bits always read back 0 (nothing is stored

  // for them).

  // ---------------------------------------------------------------------

  always_comb begin

    unique case (1'b1)

      hit_ctrl:   csr_rdata_o = {{(CsrDataWidth-3){1'b0}}, 1'b0, 1'b0, ctrl_en_q};

      hit_sel:    csr_rdata_o = {{(CsrDataWidth-5){1'b0}}, sel_q};

      hit_cnt_lo: csr_rdata_o = {{(CsrDataWidth-32){1'b0}}, cnt_i[31:0]};

      hit_cnt_hi: csr_rdata_o = {{(CsrDataWidth-32){1'b0}}, cnt_i[63:32]};

      hit_info:   csr_rdata_o = {{(CsrDataWidth-16){1'b0}}, TMH_INFO_VERSION, TMH_INFO_NUM_PAIRS};

      default:    csr_rdata_o = '0;

    endcase

  end

 

endmodule
