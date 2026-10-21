// Copyright 2026 TIDE-MCU contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Tide DD stub (Phase 1, tide_cd DV only).
//
// Test double that replaces the real tide_dd_top (tide_dd repo) behind the
// frozen CD<->DD boundary during CD-side verification (tide_doc ch10
// section 3.4). It models ONLY the interface-visible DD behaviour:
//   - enqueue checks C2/C3/C4, all-or-none (ISA section 2.2): per-channel
//     strict-monotonic ts', guard band ts' >= elapsed + TQ_GUARD, occupancy
//   - commit: an enqueued event commits on the first cycle with
//     ts' <= elapsed; the stub backend is the identity mapping
//     (result = code, T_done = elapsed at commit) - the codeword is opaque
//     and only transported, never interpreted
//   - readout queues with the identity channel->queue map, QLOAD pop
//   - QSYNC release after SYNC_LAT ticks (anchor pulse)
//   - GC / elapsed counters, fail-stop / halt state, P2 realignment
//   - the CSR split bus (RO readback + RW mirror + W1S actions) and the
//     MMIO configuration window (capability block + generic RW storage)
//
// This stub is NOT Phase 2 compliance evidence (top-level AGENTS.md
// section 6, rule 9): Phase 2 evidence must come from the real
// tide_dd_top in the tide_dd repo.

module tide_dd_stub
  import ibex_tide_pkg::*;
  #(
    parameter int NCH      = 16,   // must match the DUT build (pkg default)
    parameter int NRQ      = 16,
    parameter int TQ_DEPTH = 32,
    parameter int RQ_DEPTH = 4,
    parameter int TQ_GUARD = 8,
    parameter int SYNC_LAT = 2     // QSYNC release latency (XBOARD_K)
  ) (
    input  logic            clk,
    input  logic            rst_n,
    // Event channel (CD -> DD)
    input  tide_enq_req_t   enq_req_i,
    output tide_enq_rsp_t   enq_rsp_o,
    // Result channel (DD -> CD)
    input  tide_rq_req_t    rq_req_i,
    output tide_rq_rsp_t    rq_rsp_o,
    // Sync channel
    input  tide_sync_req_t  sync_req_i,
    output logic            sync_anchor_o,
    output logic            gc_realign_o,
    // Exception channel (DD -> CD)
    output tide_trap_t      trap_o,
    output logic            halt_o,
    // CSR split bus (same-cycle combinational response, frozen protocol)
    input  tide_csr_req_t   csr_req_i,
    output tide_csr_rsp_t   csr_rsp_o,
    // MMIO configuration plane (same-cycle response; the DUT registers it)
    input  tide_mmio_req_t  mmio_req_i,
    output tide_mmio_rsp_t  mmio_rsp_o
  );

  localparam int CH_CNT_W   = $clog2(TQ_DEPTH) + 1;
  localparam int CH_IDX_W   = $clog2(TQ_DEPTH);
  localparam int RQ_CNT_W   = $clog2(RQ_DEPTH) + 1;
  localparam int RQ_IDX_W   = $clog2(RQ_DEPTH);
  localparam logic [31:0] TIDE_STUB_SCHEMA = 32'h0001_0001; // v1, vendor 0
  localparam logic [31:0] TIDE_STUB_CAP    = 32'h0001_0001; // capability block
  localparam int MMIO_WORDS = 16384;                        // 64 KB window

  function automatic logic [31:0] sat_inc(input logic [31:0] v);
    sat_inc = (v == 32'hFFFF_FFFF) ? v : v + 32'd1;
  endfunction

  // ---------------- state ----------------
  logic [63:0] gc_q;
  logic        anchored_dd_q;
  logic [47:0] elapsed_q;
  logic        halted_q;
  logic        run_q;

  // timed queues: event = {ts'[47:0], code[31:0]}
  logic [79:0]         ch_mem       [NCH][TQ_DEPTH];
  logic [CH_CNT_W-1:0] ch_cnt_q     [NCH];
  logic [CH_IDX_W-1:0] ch_head_q    [NCH];
  logic [47:0]         ch_last_ts_q [NCH];

  // readout queues: record = {result[31:0], T_done[47:0]}
  logic [79:0]         rq_mem      [NRQ][RQ_DEPTH];
  logic [RQ_CNT_W-1:0] rq_cnt_q    [NRQ];
  logic [RQ_IDX_W-1:0] rq_head_q   [NRQ];
  logic [31:0]         rq_latest_q [NRQ];   // ADR C16: latest result value
  logic [CH_CNT_W-1:0] ch_max_used_q [NCH]; // ADR C16: watermark history
  logic [31:0]         err_cnt_q [11];      // ADR C16: TQ_* counters

  // CSR mirror / W1S state
  logic        nb_q;
  logic [31:0] policy_q;
  logic [7:0]  tqidx_q;
  logic [31:0] tqsink_q;
  logic [31:0] gch_snap_q;

  // sync FSM
  logic        sync_busy_q;
  logic [31:0] sync_cnt_q;
  logic        sync_stall_q;
  logic        sync_stall_req = 1'b0; // task-only; zero-init (X would wedge the anchor FSM)
  // MMIO storage (capability block 0x0000-0x0FFF is RO)
  logic [31:0] mmio_mem [0:MMIO_WORDS-1];

  // ---------------- test stimulus request lines ---------------------------
  logic        realign_req = 1'b0;
  logic        trap_req = 1'b0;
  logic        trap_fs_req = 1'b0;
  tide_tqcause_e    trap_cause_req = TideTqCauseLate;
  tide_trap_class_e trap_class_req = TideTrapClassSync;
  logic        trap_isqueue_req = 1'b0;
  logic [4:0]  trap_idx_req = 5'd0;
  logic [47:0] trap_ts_req = 48'd0;
  logic [31:0] trap_gid_req = 32'd0;
  logic        force_late_req = 1'b0;
  logic [4:0]  force_late_ch_req = 5'd0;
  logic        force_late_q;
  logic [4:0]  force_late_ch_q;
  logic        inj_req = 1'b0;
  logic [4:0]  inj_rq_req = 5'd0;
  logic [31:0] inj_result_req = 32'd0;
  logic [47:0] inj_tdone_req = 48'd0;
  // trap one-shot pulse registers (armed by task hook or internal overflow)
  logic             trap_arm_q;
  logic             trap_failstop_arm;
  tide_tqcause_e    trap_cause_arm;
  tide_trap_class_e trap_class_arm;
  logic             trap_isqueue_arm;
  logic [4:0]       trap_idx_arm;
  logic [47:0]      trap_ts_arm;
  logic [31:0]      trap_gid_arm;

  // ---------------- enqueue checks C2/C3/C4 (combinational) --------------
  logic           enq_active;
  logic [NCH-1:0] enq_mask;
  logic           any_late;
  logic           any_full;
  logic [4:0]     late_ch;
  logic [4:0]     full_ch;

  assign enq_active = enq_req_i.valid;
  assign enq_mask   = enq_req_i.mask[NCH-1:0];

  always_comb begin : gen_enq_checks
    any_late = 1'b0;
    any_full = 1'b0;
    late_ch  = 5'd0;
    full_ch  = 5'd0;
    for (int c = 0; c < NCH; c++) begin
      if (enq_mask[c]) begin
        // C3: ts' >= elapsed + TQ_GUARD ; C2: ts' strictly > last enqueued ts'
        if ((enq_req_i.ts_prime[47:0] < (elapsed_q + 48'(TQ_GUARD))) ||
            (enq_req_i.ts_prime[47:0] <= ch_last_ts_q[c])) begin
          if (!any_late) begin
            any_late = 1'b1;
            late_ch  = 5'(c);
          end
        end else if (ch_cnt_q[c] == CH_CNT_W'(TQ_DEPTH)) begin
          // C4: target queue has free slots (lowest failing channel, ISA 6.5)
          if (!any_full) begin
            any_full = 1'b1;
            full_ch  = 5'(c);
          end
        end
      end
    end
    // test hook: force a LATE verdict on a given channel
    if (force_late_q) begin
      any_late = 1'b1;
      late_ch  = force_late_ch_q;
    end
  end

  // Response: LATE (or non-blocking FULL) raises tq_err; blocking FULL
  // stalls (backpressure). The CD holds the request until the instruction
  // retires or traps, so the response may be purely combinational.
  assign enq_rsp_o = '{
    stall   : enq_active & ~any_late & any_full & ~nb_q,
    illegal : 1'b0,
    tq_err  : enq_active & (any_late | (any_full & nb_q)),
    tqcause : any_late ? TideTqCauseLate : TideTqCauseFull,
    ch      : any_late ? late_ch : full_ch
  };

  // A successful enqueue commits into the queues on the next edge.
  logic enq_commit;
  assign enq_commit = enq_active & ~any_late & ~any_full;

  // ---------------- commit (dequeue) decision ----------------------------
  // One pop per channel per cycle. Halted fault domain: dequeue disabled,
  // elapsed keeps counting (ISA section 6.3).
  logic [NCH-1:0] ch_commit_now;
  always_comb begin : gen_commit_dec
    for (int c = 0; c < NCH; c++) begin
      ch_commit_now[c] = anchored_dd_q & ~halted_q & (ch_cnt_q[c] != '0) &
                         (ch_mem[c][ch_head_q[c]][79:32] <= elapsed_q);
    end
  end

  // ---------------- QLOAD pop (result channel) ---------------------------
  assign rq_rsp_o.valid = rq_req_i.valid & (rq_cnt_q[rq_req_i.rq_idx] != '0);
  assign rq_rsp_o.result =
      (rq_cnt_q[rq_req_i.rq_idx] != '0) ?
      rq_mem[rq_req_i.rq_idx][rq_head_q[rq_req_i.rq_idx]][79:48] : 32'd0;
  logic rq_pop_now;
  assign rq_pop_now = rq_req_i.valid & rq_rsp_o.valid;

  // ---------------- completion push / suspended overflow -----------------
  // Identity channel->readout-queue map (version A). A committing event on
  // channel c produces one completion record on queue c; tqsink queues drop
  // real completions without fault. A push into a full queue is
  // TQ_SUSP_OVF: the record is dropped, then per tqerr_policy bit 3 either
  // fail-stop (halt) or async trap (ISA section 6.6). Lowest overflowing
  // queue wins (ISA section 6.5 same-rank ordering).
  logic [NRQ-1:0] comp_push;
  logic [NRQ-1:0] comp_sink;
  logic [NRQ-1:0] inj_push;
  logic [NRQ-1:0] susp_ovf;
  logic [4:0]     susp_ovf_rq;
  logic           susp_ovf_failstop;

  always_comb begin : gen_completion
    for (int c = 0; c < NRQ; c++) begin
      comp_push[c] = (c < NCH) & ch_commit_now[c];
      comp_sink[c] = comp_push[c] & tqsink_q[c];
      inj_push[c]  = inj_req & (inj_rq_req == 5'(c));
      susp_ovf[c]  = ((comp_push[c] & ~comp_sink[c]) | inj_push[c]) &
                     (rq_cnt_q[c] == RQ_CNT_W'(RQ_DEPTH));
    end
    susp_ovf_rq = 5'd0;
    for (int c = NRQ - 1; c >= 0; c--) begin
      if (susp_ovf[c]) susp_ovf_rq = 5'(c);
    end
    susp_ovf_failstop = policy_q[3];
  end

  // ---------------- QSYNC release (anchor) --------------------------------
  assign sync_anchor_o = sync_busy_q & (sync_cnt_q == 32'd0) &
                         ~sync_stall_q & sync_req_i.valid;

  // ---------------- P2 realignment pulse ----------------------------------
  assign gc_realign_o = realign_req;

  // ---------------- CSR split bus (frozen adapter protocol) ---------------
  logic        ch_idx_ok;
  logic        rq_idx_ok;
  logic [48:0] gamma49;
  assign ch_idx_ok = (tqidx_q[4:0] < 5'(NCH));
  assign rq_idx_ok = (tqidx_q[4:0] < 5'(NRQ));
  // ADR C15: gamma = TLR - elapsed (signed 48-bit as 49-bit
  // two's complement). The TLR arrives on the CSR read request
  // (CD-local; QWAIT never reaches the DD).
  assign gamma49 = {1'b0, csr_req_i.tlr} - {1'b0, elapsed_q};

  always_comb begin : gen_csr_rsp
    csr_rsp_o = '{valid: csr_req_i.valid, rdata: 32'd0, illegal: 1'b0};
    if (csr_req_i.valid) begin
      case (csr_req_i.addr)
        12'h7C0:   csr_rsp_o.rdata = {2'b0, nb_q, 6'(NRQ), 6'(NCH),
                                      4'($clog2(RQ_DEPTH)),
                                      5'($clog2(TQ_DEPTH)), 8'(TQ_GUARD)};
        12'h7C3:   csr_rsp_o.rdata = 32'd0;
        12'h7C4:   csr_rsp_o.rdata = policy_q;
        12'h7C5:   csr_rsp_o.rdata = {24'b0, tqidx_q};
        12'h7C6:   csr_rsp_o.rdata = tqsink_q;
        12'h7C7:   csr_rsp_o.rdata = 32'd0;
        12'hFC0:   csr_rsp_o.rdata = gc_q[31:0];
        12'hFC1:   csr_rsp_o.rdata = gch_snap_q;
        12'hFC4:   csr_rsp_o.rdata = {29'b0, halted_q, anchored_dd_q, run_q};
        12'hFC6:   begin
          // ADR C16: tqidx[7:5] category select
          if (tqidx_q[7:5] == 3'd0)
            csr_rsp_o.rdata = rq_idx_ok ?
                              rq_latest_q[tqidx_q[4:0]] : 32'd0;
          else if (tqidx_q[7:5] == 3'd1)
            csr_rsp_o.rdata = rq_idx_ok ?
                              {29'b0, rq_cnt_q[tqidx_q[4:0]]} : 32'd0;
          else if (tqidx_q[7:5] == 3'd2)
            csr_rsp_o.rdata = ch_idx_ok ?
                              32'(TQ_DEPTH) -
                              {29'b0, ch_max_used_q[tqidx_q[4:0]]} : 32'd0;
          else
            csr_rsp_o.rdata = (tqidx_q[4:0] <= 5'd10) ?
                              err_cnt_q[tqidx_q[4:0]] : 32'd0;
        end
        12'hFC8:   csr_rsp_o.rdata = TIDE_STUB_SCHEMA;
        12'hFC9:   csr_rsp_o.rdata = gamma49[31:0];
        12'hFCA:   csr_rsp_o.rdata = {16'b0, gamma49[47:32]};
        default:   csr_rsp_o.rdata = 32'd0;
      endcase
    end
  end

  // ---------------- MMIO configuration plane ------------------------------
  always_comb begin : gen_mmio_rsp
    mmio_rsp_o = '{valid: mmio_req_i.valid, rdata: 32'd0, err: 1'b0};
    if (mmio_req_i.valid) begin
      mmio_rsp_o.rdata = (mmio_req_i.addr[15:12] == 4'd0) ?
                         TIDE_STUB_CAP : mmio_mem[mmio_req_i.addr[14:2]];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : mmio_mem_reg
    if (!rst_n) begin
      for (int i = 0; i < MMIO_WORDS; i++) mmio_mem[i] <= 32'd0;
    end else if (mmio_req_i.valid & mmio_req_i.write &
                 (mmio_req_i.addr[15:12] != 4'd0)) begin
      if (mmio_req_i.be[0]) mmio_mem[mmio_req_i.addr[14:2]][ 7: 0] <=
                            mmio_req_i.wdata[ 7: 0];
      if (mmio_req_i.be[1]) mmio_mem[mmio_req_i.addr[14:2]][15: 8] <=
                            mmio_req_i.wdata[15: 8];
      if (mmio_req_i.be[2]) mmio_mem[mmio_req_i.addr[14:2]][23:16] <=
                            mmio_req_i.wdata[23:16];
      if (mmio_req_i.be[3]) mmio_mem[mmio_req_i.addr[14:2]][31:24] <=
                            mmio_req_i.wdata[31:24];
    end
  end

  // ---------------- counters / anchor / halt ------------------------------
  always_ff @(posedge clk or negedge rst_n) begin : tide_counters_reg
    if (!rst_n) begin
      gc_q          <= 64'd0;
      elapsed_q     <= 48'd0;
      anchored_dd_q <= 1'b0;
      halted_q      <= 1'b0;
      run_q         <= 1'b1;
      nb_q          <= 1'b0;
      policy_q      <= 32'd0;
      tqidx_q       <= 8'd0;
      tqsink_q      <= 32'd0;
      gch_snap_q    <= 32'd0;
      for (int i = 0; i < 11; i++) err_cnt_q[i] <= 32'd0;
    end else begin
      gc_q <= gc_q + 64'd1;
      if (realign_req) begin
        // P2 global alignment: GC restarts, queued events gone
        gc_q          <= 64'd0;
        elapsed_q     <= 48'd0;
        anchored_dd_q <= 1'b0;
        halted_q      <= 1'b0;
        run_q         <= 1'b1;
      end else begin
        if (sync_anchor_o) begin
          anchored_dd_q <= 1'b1;
          elapsed_q     <= 48'd0;
        end else if (anchored_dd_q) begin
          elapsed_q <= elapsed_q + 48'd1;
        end
        // fail-stop sources: W1S tqhalt_req, stub task, suspended overflow
        if (csr_req_i.valid & csr_req_i.write &
            (csr_req_i.addr == 12'h7C3)) begin
          halted_q <= 1'b1;
          run_q    <= 1'b0;
        end else if ((trap_req & trap_fs_req) |
                     (susp_ovf[susp_ovf_rq] & susp_ovf_failstop)) begin
          halted_q <= 1'b1;
          run_q    <= 1'b0;
        end
        // CSR mirror writes
        if (csr_req_i.valid & csr_req_i.write) begin
          case (csr_req_i.addr)
            12'h7C0:   nb_q     <= csr_req_i.wdata[29];
            12'h7C4:   policy_q <= csr_req_i.wdata;
            12'h7C5:   tqidx_q  <= csr_req_i.wdata[7:0];
            12'h7C6:   tqsink_q <= csr_req_i.wdata;
            default: ;
          endcase
        end
        // tqgc read latches the GC high snapshot (ISA section 5.1)
        if (csr_req_i.valid & ~csr_req_i.write &
            (csr_req_i.addr == 12'hFC0)) begin
          gch_snap_q <= gc_q[63:32];
        end
      end
      // ADR C16: saturating TQ_* error counters (tqrdata cat 3)
      if (realign_req) begin
        for (int i = 0; i < 11; i++) err_cnt_q[i] <= 32'd0;
      end else begin
        if (enq_active & any_late)
          err_cnt_q[0] <= sat_inc(err_cnt_q[0]);
        if (enq_active & any_full & nb_q)
          err_cnt_q[1] <= sat_inc(err_cnt_q[1]);
        if (susp_ovf[susp_ovf_rq])
          err_cnt_q[3] <= sat_inc(err_cnt_q[3]);
        if (trap_req)
          err_cnt_q[trap_cause_req] <= sat_inc(err_cnt_q[trap_cause_req]);
      end
    end
  end

  // ---------------- sync FSM ----------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin : tide_sync_reg
    if (!rst_n) begin
      sync_busy_q  <= 1'b0;
      sync_cnt_q   <= 32'd0;
      sync_stall_q <= 1'b0;
    end else begin
      sync_stall_q <= sync_stall_req;
      if (sync_req_i.valid & ~sync_busy_q) begin
        sync_busy_q <= 1'b1;
        sync_cnt_q  <= 32'(SYNC_LAT);
      end else if (sync_busy_q) begin
        if (~sync_stall_q & (sync_cnt_q != 32'd0)) begin
          sync_cnt_q <= sync_cnt_q - 32'd1;
        end else if (~sync_stall_q & (sync_cnt_q == 32'd0) &
                     sync_req_i.valid) begin
          // anchor fires this cycle; release the FSM
          sync_busy_q <= 1'b0;
        end
      end
    end
  end

  // ---------------- timed queues ------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin : tide_ch_reg
    if (!rst_n) begin
      for (int c = 0; c < NCH; c++) begin
        ch_cnt_q[c]      <= '0;
        ch_head_q[c]     <= '0;
        ch_last_ts_q[c]  <= 48'd0;
        ch_max_used_q[c] <= '0;
      end
    end else begin
      for (int c = 0; c < NCH; c++) begin
        automatic logic [CH_IDX_W:0] tail_idx;
        automatic logic              do_pop;
        automatic logic              do_push;
        tail_idx = {1'b0, ch_head_q[c]} + {1'b0, ch_cnt_q[c][CH_IDX_W-1:0]};
        do_pop  = ch_commit_now[c];
        do_push = enq_commit & enq_mask[c];
        if (realign_req) begin
          ch_cnt_q[c]     <= '0;
          ch_head_q[c]    <= '0;
          ch_last_ts_q[c] <= 48'd0;
        end else if (csr_req_i.valid & csr_req_i.write &
                     (csr_req_i.addr == 12'h7C7)) begin
          // W1S tqflush: drop all queued events
          ch_cnt_q[c]     <= '0;
          ch_head_q[c]    <= '0;
          ch_last_ts_q[c] <= 48'd0;
        end else begin
          // QSYNC release clears the C2 baseline (ISA section 4.4)
          if (sync_anchor_o) ch_last_ts_q[c] <= 48'd0;
          else if (do_push)  ch_last_ts_q[c] <= enq_req_i.ts_prime[47:0];
          if (do_pop) begin
            ch_head_q[c] <= (ch_head_q[c] == CH_IDX_W'(TQ_DEPTH - 1)) ?
                            '0 : ch_head_q[c] + 1'b1;
          end
          if (do_push) begin
            ch_mem[c][tail_idx[CH_IDX_W-1:0]] <=
                {enq_req_i.ts_prime[47:0], enq_req_i.code};
          end
          case ({do_pop, do_push})
            2'b01:   ch_cnt_q[c] <= ch_cnt_q[c] + 1'b1;
            2'b10:   ch_cnt_q[c] <= ch_cnt_q[c] - 1'b1;
            default: ch_cnt_q[c] <= ch_cnt_q[c];
          endcase
          // ADR C16: watermark history since anchor/realign/reset
          if (sync_anchor_o) ch_max_used_q[c] <= '0;
          else if (ch_cnt_q[c] > ch_max_used_q[c])
            ch_max_used_q[c] <= ch_cnt_q[c];
        end
      end
    end
  end

  // ---------------- readout queues ----------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin : tide_rq_reg
    if (!rst_n) begin
      for (int r = 0; r < NRQ; r++) begin
        rq_cnt_q[r]    <= '0;
        rq_head_q[r]   <= '0;
        rq_latest_q[r] <= 32'd0;
      end
    end else begin
      for (int r = 0; r < NRQ; r++) begin
        automatic logic [RQ_IDX_W:0] tail_idx;
        automatic logic              do_pop;
        automatic logic [79:0]       push_rec;
        automatic logic              do_push;
        tail_idx = {1'b0, rq_head_q[r]} + {1'b0, rq_cnt_q[r][RQ_IDX_W-1:0]};
        do_pop  = rq_pop_now & (rq_req_i.rq_idx == 5'(r));
        if (r < NCH) begin
          // identity map: channel r commits -> queue r
          do_push  = comp_push[r] & ~comp_sink[r] & ~susp_ovf[r];
          push_rec = {ch_mem[r][ch_head_q[r]][31:0], elapsed_q};
        end else begin
          do_push  = 1'b0;
          push_rec = '0;
        end
        // test injection (pre-loaded completion records)
        if (inj_push[r] & ~susp_ovf[r]) begin
          do_push  = 1'b1;
          push_rec = {inj_result_req, inj_tdone_req};
        end
        if (realign_req) begin
          rq_cnt_q[r]    <= '0;
          rq_head_q[r]   <= '0;
          rq_latest_q[r] <= 32'd0;
        end else begin
          if (do_push) rq_latest_q[r] <= push_rec[79:48]; // ADR C16: result field
          if (do_pop) begin
            rq_head_q[r] <= (rq_head_q[r] == RQ_IDX_W'(RQ_DEPTH - 1)) ?
                            '0 : rq_head_q[r] + 1'b1;
          end
          if (do_push) begin
            rq_mem[r][tail_idx[RQ_IDX_W-1:0]] <= push_rec;
          end
          case ({do_pop, do_push})
            2'b01:   rq_cnt_q[r] <= rq_cnt_q[r] + 1'b1;
            2'b10:   rq_cnt_q[r] <= rq_cnt_q[r] - 1'b1;
            default: rq_cnt_q[r] <= rq_cnt_q[r];
          endcase
        end
      end
    end
  end

  // ---------------- trap pulse --------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin : tide_trap_reg
    if (!rst_n) begin
      trap_arm_q   <= 1'b0;
      force_late_q <= 1'b0;
    end else begin
      trap_arm_q <= 1'b0;
      // one-shot stimulus, consumed by the next enqueue attempt
      if (force_late_q & enq_req_i.valid) begin
        force_late_q <= 1'b0;
      end else if (force_late_req) begin
        force_late_q    <= 1'b1;
        force_late_ch_q <= force_late_ch_req;
      end
      // internal suspended overflow wins over an external task pulse
      if (susp_ovf[susp_ovf_rq]) begin
        trap_arm_q        <= 1'b1;
        trap_failstop_arm <= susp_ovf_failstop;
        trap_cause_arm    <= TideTqCauseSuspOvf;
        trap_class_arm    <= TideTrapClassAsync;
        trap_isqueue_arm  <= 1'b1;
        trap_idx_arm      <= susp_ovf_rq;
        trap_ts_arm       <= (inj_push[susp_ovf_rq] ? inj_tdone_req
                                                    : elapsed_q);
        trap_gid_arm      <= 32'd0;
      end else if (trap_req) begin
        trap_arm_q        <= 1'b1;
        trap_failstop_arm <= trap_fs_req;
        trap_cause_arm    <= trap_cause_req;
        trap_class_arm    <= trap_class_req;
        trap_isqueue_arm  <= trap_isqueue_req;
        trap_idx_arm      <= trap_idx_req;
        trap_ts_arm       <= trap_ts_req;
        trap_gid_arm      <= trap_gid_req;
      end
    end
  end

  assign trap_o = '{
    valid           : trap_arm_q,
    is_failstop     : trap_failstop_arm,
    tqcause         : trap_cause_arm,
    trap_class      : trap_class_arm,
    target_is_queue : trap_isqueue_arm,
    target_idx      : trap_idx_arm,
    ts              : trap_ts_arm,
    gid             : trap_gid_arm
  };
  assign halt_o = halted_q;

  // ---------------- test hooks (public) ------------------------------------
  // Each hook asserts a request line, waits one edge (the registers capture
  // it), then clears the line. No blocking-assignment race with the design
  // always_ff blocks.
  task automatic stub_wait(input int n);
    repeat (n) @(posedge clk);
  endtask

  task automatic stub_realign();
    realign_req = 1'b1;
    @(posedge clk);
    realign_req = 1'b0;
  endtask

  task automatic stub_pulse_trap(input tide_tqcause_e cause,
                                 input bit is_failstop,
                                 input tide_trap_class_e cls,
                                 input bit target_is_queue,
                                 input logic [4:0] idx,
                                 input logic [47:0] ts,
                                 input logic [31:0] gid);
    trap_req         = 1'b1;
    trap_fs_req      = is_failstop;
    trap_cause_req   = cause;
    trap_class_req   = cls;
    trap_isqueue_req = target_is_queue;
    trap_idx_req     = idx;
    trap_ts_req      = ts;
    trap_gid_req     = gid;
    @(posedge clk);
    trap_req = 1'b0;
  endtask

  task automatic stub_inject_completion(input logic [4:0] rq,
                                        input logic [31:0] result,
                                        input logic [47:0] t_done);
    inj_req        = 1'b1;
    inj_rq_req     = rq;
    inj_result_req = result;
    inj_tdone_req  = t_done;
    @(posedge clk);
    inj_req = 1'b0;
  endtask

  task automatic stub_force_enq_late(input logic [4:0] ch);
    force_late_req    = 1'b1;
    force_late_ch_req = ch;
    @(posedge clk);
    force_late_req = 1'b0;
  endtask

  task automatic stub_sync_stall(input bit on);
    sync_stall_req = on;
  endtask

endmodule