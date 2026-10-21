// Copyright 2026 TIDE-MCU contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// TIDE-ISA shared types and parameters (CD side landing package).
//
// Frozen data sources:
//   - tide_doc/chapters/09-interface-freeze.md section 3/4 (parameters/types)
//   - tide_doc/chapters/10-implementation-plan.md section 3.3 (top adapter types)
//   - tide_doc/data/tide_params.csv, tide_iface_signals.csv
//   - tide_isa/TIDE-ISA规范.md v0.10-rc4 section 2/4/5/6
//
// This package only carries frozen contracts. It does NOT define or extend
// ISA semantics.

package ibex_tide_pkg;

  /////////////////////////////////////////
  // Parameter freeze (Version A)        //
  /////////////////////////////////////////

  // Synthesis-time gate. TIDE_EN=0 must behave bit-for-bit like upstream Ibex.
  parameter bit TIDE_EN = 1'b1;

  // Number of harts. Version A: 1. All per-hart structures are parameterized
  // by N from day one (tide_doc/chapters/05-dd-unit.md section 1).
  parameter int NHART     = 1;
  // Number of channels (timed queues), 1..32.
  parameter int NCH       = 16;
  // Number of readout queues, 1..32. One-to-one with readout channels.
  parameter int NRQ       = 16;
  // Timed queue depth, >= 2.
  parameter int TQ_DEPTH  = 32;
  // Readout queue (FIFO) depth, >= 2.
  parameter int RQ_DEPTH  = 4;
  // Late-event guard band in ticks, 4..16. Absorbs CDC/compare latency.
  parameter int TQ_GUARD  = 8;
  // Active sync-set capacity of the sync server.
  parameter int NSYNC_SET = 16;
  // Cross-board fixed transfer latency (ticks). Version A: single-board loop.
  parameter int XBOARD_K  = 2;

  // Spec-fixed bit widths (not overridable).
  localparam int TLR_W     = 48; // phase-local timeline
  localparam int ELAPSED_W = 48; // per-hart elapsed counter (DD internal)
  localparam int PI_W      = 5;  // pre-interval, 0..31 ticks
  localparam int TS_W      = 48; // event ts' field
  localparam int CODE_W    = 32; // codeword, opaque to ISA
  localparam int GID_W     = 32; // QSYNC gid = rs1 + imm (mod 2^32)

  // Phase upper bound: 2^48 - 32 (reserves PI headroom, ISA section 4.1).
  localparam logic [TLR_W:0] TLR_MAX = {TLR_W{1'b1}} - 49'd32;

  // Reset defaults for timeout thresholds (ISA section 5.2: non-zero at reset).
  localparam logic [31:0] TQ_RTY_TIMEOUT_RST = 32'd65536; // QLOAD timeout, ticks
  localparam logic [31:0] TQ_SYT_TIMEOUT_RST = 32'd65536; // QSYNC timeout, ticks
  localparam logic [31:0] TQ_RES_KHZ         = 32'd250000; // dispatch clock, kHz

  // tqerr_policy reset: bit2 TQ_UNDERRUN, bit3 TQ_SUSP_OVF,
  // bit6 TQ_FB_STALE, bit7 TQ_CODE_INVALID (ISA section 5.2).
  localparam logic [31:0] TQERR_POLICY_RST = 32'h0000_00CC;

  // tqcfg read-only constant fields (synthesis constants read back).
  localparam logic [31:0] TQCFG_CONST_RST =
      {2'b0, 1'b0 /*bit29 non-blocking, writable*/, 6'(NRQ), 6'(NCH),
       4'($clog2(RQ_DEPTH)), 5'($clog2(TQ_DEPTH)), TQ_GUARD[7:0]};

  // Dispatch frequency and capability constants exposed through RO CSRs.
  localparam logic [31:0] TQFDOM_CONST    = {16'b0, 8'(NHART), 8'h00};
  localparam logic [31:0] TQSYNCCAP_CONST = {15'b0, 1'b0, 16'(NSYNC_SET)};

  /////////////////////////////////////////
  // Type freeze (09-interface-freeze.md //
  // section 4; 10-implementation-plan   //
  // section 3.3)                        //
  /////////////////////////////////////////

  typedef enum logic [2:0] {
    TideOpNone  = 3'd0,
    TideOpQwait = 3'd1,
    TideOpQsync = 3'd2,
    TideOpQtrig = 3'd3,
    TideOpQload = 3'd4
  } tide_op_e;

  // tqcause[3:0]: TQ_* ordinals, ISA section 6.6.
  typedef enum logic [3:0] {
    TideTqCauseLate        = 4'd0,
    TideTqCauseFull        = 4'd1,
    TideTqCauseUnderrun    = 4'd2,
    TideTqCauseSuspOvf     = 4'd3,
    TideTqCauseRdyTimeout  = 4'd4,
    TideTqCauseSyncTimeout = 4'd5,
    TideTqCauseFbStale     = 4'd6,
    TideTqCauseCodeInvalid = 4'd7,
    TideTqCauseSyncErr     = 4'd8,
    TideTqCauseDirty       = 4'd9,
    TideTqCauseHalted      = 4'd10
  } tide_tqcause_e;

  // tqcause[5:4]: detection class.
  typedef enum logic [1:0] {
    TideTrapClassSync    = 2'd0, // synchronous precise exception
    TideTrapClassAsync   = 2'd1, // async trap at commit
    TideTrapClassHaltKill= 2'd2  // killed by fail-stop broadcast
  } tide_trap_class_e;

  // All TQ_* traps share mcause=24 (ISA section 5.4/6.6).
  localparam logic [31:0] TideMcause = 32'd24;

  // NOTE (microarch adaptation, see tide_doc change record): the mask is
  // carried with the full 32-bit transport width so that the C1 legality
  // check (bits >= NCH must be 0) is evaluated on the complete value before
  // any truncation. The frozen ch09 sketch had mask[NCH-1:0], which would
  // silently truncate out-of-range bits and turn an illegal QTRIG into a
  // partial enqueue (ISA section 2.2 C1 violation).
  typedef logic [31:0]      tide_mask_t;
  typedef logic [PI_W-1:0]  tide_pi_t;
  typedef logic [CODE_W-1:0] tide_code_t;
  typedef logic [TS_W-1:0]  tide_ts_t;
  typedef logic [TS_W:0]    tide_tsx_t;  // 49-bit combined result
  typedef logic [31:0]      tide_result_t;
  typedef logic [GID_W-1:0] tide_gid_t;

  // CD -> DD: QTRIG atomic enqueue request (event channel).
  typedef struct packed {
    logic        valid;
    tide_mask_t  mask;
    tide_code_t  code;
    tide_pi_t    pi;
    tide_tsx_t   ts_prime;
    logic [31:0] pc;
  } tide_enq_req_t;

  // DD -> CD: backpressure / illegal / TQ_LATE (or non-blocking TQ_FULL).
  typedef struct packed {
    logic          stall;
    logic          illegal;
    logic          tq_err;
    tide_tqcause_e tqcause;
    logic [4:0]    ch;
  } tide_enq_rsp_t;

  // CD -> DD: QLOAD readout queue pop request (result channel).
  typedef struct packed {
    logic       valid;
    logic [4:0] rq_idx;
  } tide_rq_req_t;

  // DD -> CD: head of FIFO (valid=0 means empty, QLOAD keeps blocking).
  typedef struct packed {
    logic         valid;
    tide_result_t result;
  } tide_rq_rsp_t;

  // CD -> DD: QSYNC gid report (join channel).
  typedef struct packed {
    logic      valid;
    tide_gid_t gid;
  } tide_sync_req_t;

  // DD -> CD: error event / fail-stop kill; synchronous precise or async
  // trap; no mtval2 (ISA section 5.4).
  typedef struct packed {
    logic             valid;
    logic             is_failstop;
    tide_tqcause_e    tqcause;
    tide_trap_class_e trap_class;
    logic             target_is_queue;
    logic [4:0]       target_idx;
    tide_ts_t         ts;
    tide_gid_t        gid;
  } tide_trap_t;

  // Synchronous TIDE trap raised by the ID stage (to ibex_controller).
  // Class is always 0 (synchronous precise). Covers TQ_LATE, TQ_FULL
  // (non-blocking), TQ_RDY_TIMEOUT, TQ_SYNC_TIMEOUT, TQ_HALTED.
  typedef struct packed {
    logic            valid;
    tide_tqcause_e   tqcause;
    logic            target_is_queue; // 0 = channel, 1 = queue/group
    logic [4:0]      target_idx;
    logic [47:0]     ts;              // offending ts'
    logic [31:0]     gid;             // offending group id
  } tide_id_trap_t;

  // TIDE trap context delivered to ibex_cs_registers at trap-save time.
  // Latched by the CSR file into tqcause/tqfault/tqfaulth when mcause=24.
  typedef struct packed {
    logic             valid;
    tide_trap_class_e trap_class;
    tide_tqcause_e    tqcause;
    logic             target_is_queue;
    logic [4:0]       target_idx;
    logic [47:0]      ts;
    logic [31:0]      gid;
  } tide_trap_ctx_t;
  // CD <-> DD CSR split bus (frozen adapter types,
  // tide_doc/chapters/10-implementation-plan.md section 3.3).
  //
  // Protocol: always-ready, combinational read, 1-cycle access.
  //  - req.valid is pulsed for one cycle by the CD for every TIDE CSR
  //    access; write=1 selects a write of wdata to addr.
  //  - rsp is valid in the same cycle as the request (rsp.valid ==
  //    req.valid); rsp.rdata carries the read data for RO accesses.
  //  - Registered side effects (tqgc/tqhead snapshot latches, W1S actions)
  //    happen on the request cycle.
  // RW configuration state mirrored inside the DD (tqcfg bit29,
  // tqerr_policy, tqidx, tqsink) is updated on write accesses; the
  // CD keeps its own copies for readback (single writer: the bus).
  typedef struct packed {
    logic        valid;
    logic        write;
    logic [11:0] addr;
    logic [31:0] wdata;
    // ADR C15 (tide_doc ch09): the CD's current TLR, carried on
    // every read request; meaningful for the 0xFC9/0xFCA reads
    // (gamma = TLR - elapsed), which the DD evaluates in the same
    // cycle. TLR is CD-local (QWAIT never reaches the DD).
    logic [47:0] tlr;
  } tide_csr_req_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] rdata;
    logic        illegal;
  } tide_csr_rsp_t;

  // CD <-> DD MMIO configuration surface (frozen adapter types).
  // 16-bit window offset, 32-bit data, byte enables. Always-ready,
  // 1-cycle (configuration plane; no cycle-accuracy requirement,
  // ISA section 5.3).
  typedef struct packed {
    logic        valid;
    logic        write;
    logic [15:0] addr;
    logic [3:0]  be;
    logic [31:0] wdata;
  } tide_mmio_req_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] rdata;
    logic        err;
  } tide_mmio_rsp_t;

  // DD transport-shell <-> backend boundary (frozen adapter types).
  // commit: DD delivers {ts, code} to the channel backend at commit time.
  typedef struct packed {
    logic        valid;
    logic [31:0] code;
    logic [47:0] ts;
  } tide_commit_t;

  // completion: backend returns {result, t_done} for a measurement event.
  typedef struct packed {
    logic        valid;
    logic [31:0] result;
    logic [47:0] t_done;
  } tide_completion_t;

endpackage
