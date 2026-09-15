// -----------------------------------------------------------------------------

// tmh_counter_bank.sv

//

// Storage for the 25-entry TMH transition-matrix counter bank: one live,

// free-running 64-bit accumulator per (prev,curr) class pair, plus a

// parallel 25-entry shadow array that only updates on an explicit

// snapshot pulse. Software always reads through the shadow array (via

// cnt_o, muxed by sel_i) so a multi-word read across all 25 counters is

// always glitch-free and internally consistent, regardless of live

// counting continuing underneath it.

//

// Deliberately NOT a freeze: live counting never stops, so no transition

// is ever silently dropped during a read window -- see

// tmh-25event-csr-integration-spec.md for the full rationale (this feeds

// a security-monitoring trace; a freeze window is exactly the kind of

// gap that shouldn't exist).

//

// shadow_d captures the POST-increment value of the same cycle a

// snapshot is requested (accum_d, not accum_q), so a snapshot requested

// the same cycle as a same-cycle commit-side transition still includes

// it -- see the "same-cycle CSR-read / commit corner case" note in the

// integration spec.

//

// en_i only gates accumulation here, not tmh_event_gen's own history

// tracking -- EN pauses *counting*, it does not reset or pause the

// adjacency-detection pipeline feeding it, so re-enabling doesn't lose

// track of in-flight sequence state.

// -----------------------------------------------------------------------------

 

module tmh_counter_bank

  import tmh_pkg::*;

#(

    parameter int unsigned NrCommitPorts = 2,

    parameter int unsigned TmhIncWidth   = $clog2(NrCommitPorts + 1)

) (

    input  logic                   clk_i,

    input  logic                   rst_ni,

 

    // From tmh_event_gen, unchanged.

    input  logic [TmhIncWidth-1:0] tmh_inc_i   [TMH_NUM_PAIRS],

 

    // Control, from tmh_csr.

    input  logic                   en_i,        // 0 = hold, 1 = count

    input  logic                   snapshot_i,  // 1-cycle pulse

    input  logic                   clear_i,     // 1-cycle pulse

 

    // Read-side selection, from tmh_csr (already clamped to 0..24).

    input  logic [4:0]             sel_i,

 

    // Selected shadow counter, full 64 bits -- tmh_csr splits into

    // TMH_CNT_LO / TMH_CNT_HI on read.

    output logic [63:0]            cnt_o

);

 

  logic [63:0] accum_q  [TMH_NUM_PAIRS];

  logic [63:0] accum_d  [TMH_NUM_PAIRS];

  logic [63:0] shadow_q [TMH_NUM_PAIRS];

  logic [63:0] shadow_d [TMH_NUM_PAIRS];

 

  always_comb begin

    for (int unsigned i = 0; i < TMH_NUM_PAIRS; i++) begin

      // clear_i wins even over en_i=0 written the same cycle -- a clear

      // always clears.

      if (clear_i) begin

        accum_d[i] = '0;

      end else if (en_i) begin

        accum_d[i] = accum_q[i] + 64'(tmh_inc_i[i]);

      end else begin

        accum_d[i] = accum_q[i];

      end

 

      shadow_d[i] = snapshot_i ? accum_d[i] : shadow_q[i];

    end

  end

 

  always_ff @(posedge clk_i or negedge rst_ni) begin

    if (!rst_ni) begin

      for (int unsigned i = 0; i < TMH_NUM_PAIRS; i++) begin

        accum_q[i]  <= '0;

        shadow_q[i] <= '0;

      end

    end else begin

      accum_q  <= accum_d;

      shadow_q <= shadow_d;

    end

  end

 

  // sel_i is guaranteed 0..24 by tmh_csr's WARL clamp on write -- no

  // bounds check needed here, just the mux.

  assign cnt_o = shadow_q[sel_i];

 

endmodule
