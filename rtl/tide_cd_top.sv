// Copyright lowRISC contributors (TIDE-MCU project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// TIDE-ISA v0.10-rc4 CD-side top (tide_doc ch10 section 3.3, Version A).
//
// Synthesized boundary of the classic domain (CD):
//   - ibex_core carrying the TIDE CD-side execution logic (ID stage),
//   - the FF register file,
//   - the Ibex-equivalent core clock gating (ch10: register file / clock
//     gating follow the equivalent Ibex implementation).
//
// The frozen port surface (ch10 section 3.3, groups 1-9) is implemented
// 1:1. One documented adaptation (see the tide_doc change record):
//   - tide_gc_realign_i (group 8): P2 global realignment pulse from the DD
//     (GC <- 0, queued events gone, TLR restart). The original frozen
//     sketch predates the ID-stage TLR handling (ch09 section 4.3).
//
// RVFI/trace is deliberately not exported at this top (frozen note 10);
// a simulation wrapper can bring it out when needed.
//
// Non-TIDE core parameters stay at their upstream defaults, which
// constitute Version A: RV32IMC + Zca/Zcb/Zcmp, no ICache, no PMP,
// no branch predictor, single-stage writeback, non-secure.

module tide_cd_top
  import ibex_pkg::*;
  import ibex_tide_pkg::*;
#(
  parameter bit TIDE_EN = 1'b1,
  parameter int unsigned NCH = 16,
  parameter int unsigned NRQ = 16,
  parameter int unsigned TQ_DEPTH = 32,
  parameter int unsigned RQ_DEPTH = 4,
  parameter int unsigned TQ_GUARD = 8,
  parameter int unsigned NSYNC_SET = 16
) (
  // 1. clock, reset, identity
  input  logic clk_i,
  input  logic rst_ni,
  input  logic [31:0] hart_id_i,
  input  logic [31:0] boot_addr_i,

  // 2. instruction memory
  output logic instr_req_o,
  input  logic instr_gnt_i,
  input  logic instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic instr_err_i,

  // 3. data / MMIO
  output logic data_req_o,
  input  logic data_gnt_i,
  input  logic data_rvalid_i,
  output logic data_we_o,
  output logic [3:0] data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic data_err_i,

  // 4. interrupts, debug and control
  input  logic irq_software_i,
  input  logic irq_timer_i,
  input  logic irq_external_i,
  input  logic [14:0] irq_fast_i,
  input  logic irq_nm_i,
  input  logic debug_req_i,
  input  ibex_mubi_t fetch_enable_i,
  input  ibex_mubi_t mcounteren_writable_i,
  output logic core_busy_o,

  // 5. TIDE event channel (QTRIG enqueue, CD -> DD)
  output tide_enq_req_t tide_enq_req_o,
  input  tide_enq_rsp_t tide_enq_rsp_i,

  // 6. TIDE result channel (QLOAD readout, DD -> CD)
  output tide_rq_req_t tide_rq_pop_o,
  input  tide_rq_rsp_t tide_rq_rsp_i,

  // 7. TIDE sync channel (QSYNC)
  output tide_sync_req_t tide_sync_req_o,
  input  logic tide_sync_anchor_i,

  // 8. TIDE error / fail-stop (+ P2 realignment pulse, see header note)
  input  tide_trap_t tide_trap_i,
  input  logic tide_halt_i,
  input  logic tide_gc_realign_i,

  // 9. TIDE CSR / MMIO configuration surface
  output tide_csr_req_t tide_csr_req_o,
  input  tide_csr_rsp_t tide_csr_rsp_i,
  output tide_mmio_req_t tide_mmio_req_o,
  input  tide_mmio_rsp_t tide_mmio_rsp_i
);

  /////////////////////////////////
  // Ibex-equivalent clock gate //
  // (ibex_top non-secure path)  //
  /////////////////////////////////

  logic        clk;
  logic        clock_en;
  logic        irq_pending;
  ibex_mubi_t  core_busy_d;
  ibex_mubi_t  core_busy_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : core_busy_reg
    if (!rst_ni) begin
      core_busy_q <= IbexMuBiOff;
    end else begin
      core_busy_q <= core_busy_d;
    end
  end

  assign clock_en = core_busy_q[0] | debug_req_i | irq_pending | irq_nm_i;

  assign core_busy_o = core_busy_d[0];

  // The frozen top surface carries no DFT test enable; tie the gate test
  // path off (DFT access, if ever needed, belongs to a platform wrapper).
  prim_clock_gating u_core_clock_gate (
    .clk_i     (clk_i),
    .en_i      (clock_en),
    .test_en_i (1'b0),
    .clk_o     (clk)
  );

  ////////////////////////////////
  // Register file interface    //
  ////////////////////////////////

  logic [4:0] rf_raddr_a, rf_raddr_b, rf_waddr_wb;
  logic       rf_we_wb;
  logic [31:0] rf_rdata_a, rf_rdata_b;
  logic [31:0] rf_wdata_wb;
  logic [ibex_cheriot_pkg::REGCAP_W-1:0] rf_rcap_a, rf_rcap_b, rf_wcap;
  logic       dummy_instr_id, dummy_instr_wb;

  // ICache = 0 in Version A: tie the core icache ports off.
  logic [IC_NUM_WAYS-1:0] ic_tag_req;
  logic                   ic_tag_write;
  logic [IC_INDEX_W-1:0]  ic_tag_addr;
  logic [IC_TAG_SIZE-1:0] ic_tag_wdata;
  logic [IC_NUM_WAYS-1:0] ic_data_req;
  logic                   ic_data_write;
  logic [IC_INDEX_W-1:0]  ic_data_addr;
  logic [IC_LINE_SIZE-1:0] ic_data_wdata;
  logic [IC_TAG_SIZE-1:0] ic_tag_rdata [IC_NUM_WAYS];
  logic [IC_LINE_SIZE-1:0] ic_data_rdata [IC_NUM_WAYS];
  logic                   ic_scr_key_req;

  logic unused_ic_ports;
  assign unused_ic_ports = ^{
    ic_tag_req, ic_tag_write, ic_tag_addr, ic_tag_wdata,
    ic_data_req, ic_data_write, ic_data_addr, ic_data_wdata, ic_scr_key_req
  };

  logic unused_df;
  crash_dump_t unused_crash_dump;

  ////////////////////////////
  // Core instantiation     //
  ////////////////////////////

  ibex_core #(
    .TIDE_EN   (TIDE_EN),
    .NCH       (NCH),
    .NRQ       (NRQ),
    .TQ_DEPTH  (TQ_DEPTH),
    .RQ_DEPTH  (RQ_DEPTH),
    .TQ_GUARD  (TQ_GUARD),
    .NSYNC_SET (NSYNC_SET)
  ) u_ibex_core (
    .clk_i (clk),
    .rst_ni (rst_ni),

    .hart_id_i (hart_id_i),
    .boot_addr_i (boot_addr_i),
    .cheriot_enable_i (IbexMuBiOff),

    // instruction memory
    .instr_req_o (instr_req_o),
    .instr_gnt_i (instr_gnt_i),
    .instr_rvalid_i (instr_rvalid_i),
    .instr_addr_o (instr_addr_o),
    .instr_rdata_i (instr_rdata_i),
    .instr_err_i (instr_err_i),

    // data / MMIO
    .data_req_o (data_req_o),
    .data_gnt_i (data_gnt_i),
    .data_rvalid_i (data_rvalid_i),
    .data_we_o (data_we_o),
    .data_be_o (data_be_o),
    .data_addr_o (data_addr_o),
    .data_wdata_o (data_wdata_o),
    .data_tag_o (),
    .data_rdata_i (data_rdata_i),
    .data_tag_i (1'b0),
    .data_err_i (data_err_i),

    // TIDE-ISA channels (groups 5-9)
    .tide_enq_req_o (tide_enq_req_o),
    .tide_enq_rsp_i (tide_enq_rsp_i),
    .tide_rq_pop_o (tide_rq_pop_o),
    .tide_rq_rsp_i (tide_rq_rsp_i),
    .tide_sync_req_o (tide_sync_req_o),
    .tide_sync_anchor_i (tide_sync_anchor_i),
    .tide_gc_realign_i (tide_gc_realign_i),
    .tide_trap_i (tide_trap_i),
    .tide_halt_i (tide_halt_i),
    .tide_csr_req_o (tide_csr_req_o),
    .tide_csr_rsp_i (tide_csr_rsp_i),
    .tide_mmio_req_o (tide_mmio_req_o),
    .tide_mmio_rsp_i (tide_mmio_rsp_i),

    // register file
    .dummy_instr_id_o (dummy_instr_id),
    .dummy_instr_wb_o (dummy_instr_wb),
    .rf_raddr_a_o (rf_raddr_a),
    .rf_raddr_b_o (rf_raddr_b),
    .rf_waddr_wb_o (rf_waddr_wb),
    .rf_we_wb_o (rf_we_wb),
    .rf_wdata_wb_ecc_o (rf_wdata_wb),
    .rf_rdata_a_ecc_i (rf_rdata_a),
    .rf_rdata_b_ecc_i (rf_rdata_b),
    .rf_wcap_ecc_wb_o (rf_wcap),
    .rf_rcap_a_ecc_i (rf_rcap_a),
    .rf_rcap_b_ecc_i (rf_rcap_b),

    // icache (Version A: ICache = 0, tied off)
    .ic_tag_req_o (ic_tag_req),
    .ic_tag_write_o (ic_tag_write),
    .ic_tag_addr_o (ic_tag_addr),
    .ic_tag_wdata_o (ic_tag_wdata),
    .ic_tag_rdata_i (ic_tag_rdata),
    .ic_data_req_o (ic_data_req),
    .ic_data_write_o (ic_data_write),
    .ic_data_addr_o (ic_data_addr),
    .ic_data_wdata_o (ic_data_wdata),
    .ic_data_rdata_i (ic_data_rdata),
    .ic_scr_key_valid_i (1'b0),
    .ic_scr_key_req_o (ic_scr_key_req),

    // interrupts / debug
    .irq_software_i (irq_software_i),
    .irq_timer_i (irq_timer_i),
    .irq_external_i (irq_external_i),
    .irq_fast_i (irq_fast_i),
    .irq_nm_i (irq_nm_i),
    .irq_pending_o (irq_pending),

    .debug_req_i (debug_req_i),
    .crash_dump_o (unused_crash_dump),
    .double_fault_seen_o (unused_df),

    // control
    .fetch_enable_i (fetch_enable_i),
    .mcounteren_writable_i (mcounteren_writable_i),
    .alert_minor_o (),
    .alert_major_internal_o (),
    .alert_major_bus_o (),
    .core_busy_o (core_busy_d)
  );

  // keep the unused nets tied for lint

  /////////////////////////////////
  // Register file instantiation //
  /////////////////////////////////

  ibex_register_file_ff #(
    .BaseIsa          (BaseIsaRV32I),
    .RV32E            (1'b0),
    .DataWidth        (32),
    .DummyInstructions(1'b0),
    .WordZeroVal      (32'(prim_secded_pkg::SecdedInv3932ZeroWord))
  ) u_register_file (
    .clk_i (clk),
    .rst_ni (rst_ni),

    .test_en_i        (1'b0),
    .dummy_instr_id_i (dummy_instr_id),
    .dummy_instr_wb_i (dummy_instr_wb),
    .cheriot_enable_i (IbexMuBiOff),

    .raddr_a_i (rf_raddr_a),
    .rdata_a_o (rf_rdata_a),
    .rcap_a_o  (rf_rcap_a),
    .raddr_b_i (rf_raddr_b),
    .rdata_b_o (rf_rdata_b),
    .rcap_b_o  (rf_rcap_b),
    .waddr_a_i (rf_waddr_wb),
    .wdata_a_i (rf_wdata_wb),
    .wcap_a_i  (rf_wcap),
    .we_a_i    (rf_we_wb)
  );

endmodule
