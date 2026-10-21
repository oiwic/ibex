// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "uvm_macros.svh"
`include "dv_macros.svh"
`include "prim_assert.sv"

module core_ibex_tb_top;

  import uvm_pkg::*;
  import core_ibex_test_pkg::*;

  wire clk;
  wire rst_n;

  clk_rst_if     ibex_clk_if(.clk(clk), .rst_n(rst_n));
  irq_if         irq_vif(.clk(clk));
  ibex_mem_intf  data_mem_vif(.clk(clk));
  ibex_mem_intf  instr_mem_vif(.clk(clk));


  // DUT probe interface
  core_ibex_dut_probe_if dut_if(.clk(clk));

  // Instruction monitor interface
  core_ibex_instr_monitor_if instr_monitor_if(.clk(clk));

  // RVFI interface
  core_ibex_rvfi_if rvfi_if(.clk(clk));

  // CSR access interface
  core_ibex_csr_if csr_if(.clk(clk));

  core_ibex_ifetch_if ifetch_if(.clk(clk));

  core_ibex_ifetch_pmp_if ifetch_pmp_if(.clk(clk));

  // VCS does not support overriding enum and string parameters via command line. Instead, a
  // `define is used that can be set from the command line. If no value has been specified, this
  // gives a default. Other simulators don't take the detour via `define and can override the
  // corresponding parameters directly.
  `ifndef IBEX_CFG_BaseIsa
    `define IBEX_CFG_BaseIsa ibex_pkg::BaseIsaRV32I
  `endif

  `ifndef IBEX_CFG_RV32M
    `define IBEX_CFG_RV32M ibex_pkg::RV32MFast
  `endif

  `ifndef IBEX_CFG_RV32B
    `define IBEX_CFG_RV32B ibex_pkg::RV32BNone
  `endif

  `ifndef IBEX_CFG_RegFile
    `define IBEX_CFG_RegFile ibex_pkg::RegFileFF
  `endif

  // Ibex Parameters
  parameter ibex_pkg::base_isa_e BaseIsa  = `IBEX_CFG_BaseIsa;
  parameter bit          PMPEnable        = 1'b0;
  parameter int unsigned PMPGranularity   = 0;
  parameter int unsigned PMPNumRegions    = 4;
  parameter int unsigned MHPMCounterNum   = 0;
  parameter int unsigned MHPMCounterWidth = 40;
  parameter bit RV32E                     = 1'b0;
  parameter ibex_pkg::rv32m_e RV32M       = `IBEX_CFG_RV32M;
  parameter ibex_pkg::rv32b_e RV32B       = `IBEX_CFG_RV32B;
  parameter ibex_pkg::regfile_e RegFile   = `IBEX_CFG_RegFile;
  parameter bit BranchTargetALU           = 1'b0;
  parameter bit WritebackStage            = 1'b0;
  parameter bit ICache                    = 1'b0;
  parameter bit ICacheECC                 = 1'b0;
  parameter bit ICacheTweakInfection      = 1'b0;
  parameter bit BranchPredictor           = 1'b0;
  parameter bit SecureIbex                = 1'b0;
  parameter int unsigned LockstepOffset   = 1;
  parameter bit ICacheScramble            = 1'b0;
  parameter bit DbgTriggerEn              = 1'b0;
`ifdef TIDE_REAL_DD
  parameter bit TIDE_EN                   = 1'b1;
`else
  parameter bit TIDE_EN                   = 1'b0;
`endif
  parameter int unsigned DmBaseAddr       = 32'h`DM_ADDR;
  parameter int unsigned DmAddrMask       = 32'h`DM_ADDR_MASK;
  parameter int unsigned DmHaltAddr       = 32'h`DEBUG_MODE_HALT_ADDR;
  parameter int unsigned DmExceptionAddr  = 32'h`DEBUG_MODE_EXCEPTION_ADDR;
  // Ibex Inputs
  parameter int unsigned BootAddr         = 32'h`BOOT_ADDR; // ResetVec = BootAddr/256b + 0x80

  // Scrambling interface instantiation
  logic [ibex_pkg::SCRAMBLE_KEY_W-1:0]   scramble_key;
  logic [ibex_pkg::SCRAMBLE_NONCE_W-1:0] scramble_nonce;

  // Initiate push pull interface for connection between Ibex and a scrambling key provider.
  push_pull_if #(
    .DeviceDataWidth(ibex_pkg::SCRAMBLE_NONCE_W + ibex_pkg::SCRAMBLE_KEY_W)
  ) scrambling_key_if (
    .clk(clk),
    .rst_n(rst_n)
  );

  // key and nonce are driven by push_pull Device interface
  assign {scramble_key, scramble_nonce} = scrambling_key_if.d_data;

  // TIDE-ISA v0.10-rc4 CD<->DD boundary (ch09 section 3; ch10 section 3.4).
  // Phase 1: with TIDE_EN=1 the DD side is tide_dd_stub (a test double, not
  // Phase 2 evidence). With TIDE_EN=0 the wires carry the pre-TIDE constants
  // so the build stays bit-identical to the TIDE_EN=0 baseline.
  ibex_tide_pkg::tide_enq_req_t  tide_enq_req_w;
  ibex_tide_pkg::tide_enq_rsp_t  tide_enq_rsp_w;
  ibex_tide_pkg::tide_rq_req_t   tide_rq_req_w;
  ibex_tide_pkg::tide_rq_rsp_t   tide_rq_rsp_w;
  ibex_tide_pkg::tide_sync_req_t tide_sync_req_w;
  logic                          tide_sync_anchor_w;
  logic                          tide_gc_realign_w;
  ibex_tide_pkg::tide_trap_t     tide_trap_w;
  logic                          tide_halt_w;
  ibex_tide_pkg::tide_csr_req_t  tide_csr_req_w;
  ibex_tide_pkg::tide_csr_rsp_t  tide_csr_rsp_w;
  ibex_tide_pkg::tide_mmio_req_t tide_mmio_req_w;
  ibex_tide_pkg::tide_mmio_rsp_t tide_mmio_rsp_w;
  ibex_top_tracing #(
    .BaseIsa              (BaseIsa             ),
    .PMPEnable            (PMPEnable           ),
    .PMPGranularity       (PMPGranularity      ),
    .PMPNumRegions        (PMPNumRegions       ),
    .MHPMCounterNum       (MHPMCounterNum      ),
    .MHPMCounterWidth     (MHPMCounterWidth    ),
    .RV32E                (RV32E               ),
    .RV32M                (RV32M               ),
    .RV32B                (RV32B               ),
    .RegFile              (RegFile             ),
    .BranchTargetALU      (BranchTargetALU     ),
    .WritebackStage       (WritebackStage      ),
    .ICache               (ICache              ),
    .ICacheECC            (ICacheECC           ),
    .ICacheTweakInfection (ICacheTweakInfection),
    .SecureIbex           (SecureIbex          ),
    .LockstepOffset       (LockstepOffset      ),
    .ICacheScramble       (ICacheScramble      ),
    .BranchPredictor      (BranchPredictor     ),
    .DbgTriggerEn         (DbgTriggerEn        ),
    .TIDE_EN              (TIDE_EN             ),
    .DmBaseAddr           (DmBaseAddr          ),
    .DmAddrMask           (DmAddrMask          ),
    .DmHaltAddr           (DmHaltAddr          ),
    .DmExceptionAddr      (DmExceptionAddr     )

  ) dut (
    .clk_i                     (clk                        ),
    .rst_ni                    (rst_n                      ),

    .test_en_i                 (1'b0                       ),
    .scan_rst_ni               (1'b1                       ),
    .ram_cfg_icache_tag_i      ('{default: prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT}),
    .ram_cfg_icache_tag_o      (                           ),
    .ram_cfg_icache_data_i     ('{default: prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT}),
    .ram_cfg_icache_data_o     (                           ),

    .hart_id_i                 (32'b0                      ),
    .boot_addr_i               (BootAddr                   ),
    .trvk_heap_base_addr_i     (32'b0                      ),

    .instr_req_o               (instr_mem_vif.request      ),
    .instr_gnt_i               (instr_mem_vif.grant        ),
    .instr_rvalid_i            (instr_mem_vif.rvalid       ),
    .instr_addr_o              (instr_mem_vif.addr         ),
    .instr_rdata_i             (instr_mem_vif.rdata        ),
    .instr_rdata_intg_i        (instr_mem_vif.rintg        ),
    .instr_err_i               (instr_mem_vif.error        ),

    .data_req_o                (data_mem_vif.request       ),
    .data_gnt_i                (data_mem_vif.grant         ),
    .data_rvalid_i             (data_mem_vif.rvalid        ),
    .data_addr_o               (data_mem_vif.addr          ),
    .data_we_o                 (data_mem_vif.we            ),
    .data_be_o                 (data_mem_vif.be            ),
    .data_rdata_i              (data_mem_vif.rdata         ),
    .data_rdata_intg_i         (data_mem_vif.rintg         ),
    .data_tag_i                (1'b0                       ),
    .data_wdata_o              (data_mem_vif.wdata         ),
    .data_wdata_intg_o         (data_mem_vif.wintg         ),
    .data_tag_o                (                           ),
    .data_err_i                (data_mem_vif.error         ),

    .trvk_revbm_req_o          (                           ),
    .trvk_revbm_gnt_i          (1'b0                       ),
    .trvk_revbm_rvalid_i       (1'b0                       ),
    .trvk_revbm_addr_o         (                           ),
    .trvk_revbm_rdata_i        ('b0                        ),
    .trvk_revbm_rdata_intg_i   ('b0                        ),
    .trvk_revbm_err_i          (1'b0                       ),

    .irq_software_i            (irq_vif.irq_software       ),
    .irq_timer_i               (irq_vif.irq_timer          ),
    .irq_external_i            (irq_vif.irq_external       ),
    .irq_fast_i                (irq_vif.irq_fast           ),
    .irq_nm_i                  (irq_vif.irq_nm             ),

    .scramble_key_valid_i      (scrambling_key_if.ack      ),
    .scramble_key_i            (scramble_key               ),
    .scramble_nonce_i          (scramble_nonce             ),
    .scramble_req_o            (scrambling_key_if.req      ),

    .debug_req_i               (dut_if.debug_req           ),
    .crash_dump_o              (                           ),
    .double_fault_seen_o       (dut_if.double_fault_seen   ),

    .cheriot_enable_i          (ibex_pkg::IbexMuBiOff      ),

    .fetch_enable_i            (dut_if.fetch_enable        ),
    .mcounteren_writable_i     (dut_if.mcounteren_writable ),
    .alert_minor_o             (dut_if.alert_minor         ),
    .alert_major_internal_o    (dut_if.alert_major_internal),
    .alert_major_bus_o         (dut_if.alert_major_bus     ),
    .core_sleep_o              (dut_if.core_sleep          ),

    .lockstep_cmp_en_o         (                           ),
    .data_req_shadow_o         (                           ),
    .data_we_shadow_o          (                           ),
    .data_be_shadow_o          (                           ),
    .data_addr_shadow_o        (                           ),
    .data_wdata_shadow_o       (                           ),
    .data_wdata_intg_shadow_o  (                           ),

    .instr_req_shadow_o        (                           ),
    .instr_addr_shadow_o       (                           ),
    // TIDE-ISA v0.10-rc4 CD<->DD boundary (ch09 section 3; ch10 section 3.4).
    // Phase 1: with TIDE_EN=1 the frozen boundary is driven by tide_dd_stub
    // (gen_tide_dd below); with TIDE_EN=0 the inputs hold the pre-TIDE
    // constants and the core requests are sunk (gen_tide_dd_off).
    .tide_enq_req_o            (tide_enq_req_w           ),
    .tide_enq_rsp_i            (tide_enq_rsp_w           ),
    .tide_rq_pop_o             (tide_rq_req_w            ),
    .tide_rq_rsp_i             (tide_rq_rsp_w            ),
    .tide_sync_req_o           (tide_sync_req_w          ),
    .tide_sync_anchor_i        (tide_sync_anchor_w       ),
    .tide_gc_realign_i         (tide_gc_realign_w        ),
    .tide_trap_i               (tide_trap_w              ),
    .tide_halt_i               (tide_halt_w              ),
    .tide_csr_req_o            (tide_csr_req_w           ),
    .tide_csr_rsp_i            (tide_csr_rsp_w           ),
    .tide_mmio_req_o           (tide_mmio_req_w          ),
    .tide_mmio_rsp_i           (tide_mmio_rsp_w          )
  );

  // TIDE-ISA v0.10-rc4 DD side (Phase 1 test double; ch10 section 3.4). The
  // stub models only the frozen boundary behaviour and is not Phase 2
  // compliance evidence (top-level AGENTS.md section 6, rule 9).
  generate
    if (TIDE_EN) begin : gen_tide_dd
`ifdef TIDE_REAL_DD
      logic [15:0] dd_commit_valid;
      logic [15:0][47:0] dd_commit_ts;
      logic [15:0][31:0] dd_commit_code;
      logic [15:0] dd_completion_valid;
      logic [15:0][31:0] dd_completion_result;
      logic [15:0][47:0] dd_completion_tdone;
      tide_dd_pkg::tide_tqcause_e dd_trap_cause;
      tide_dd_pkg::tide_trap_class_e dd_trap_class;
      logic [1:0] dd_init_realign_q;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) dd_init_realign_q <= 2'b00;
        else if (!(&dd_init_realign_q)) dd_init_realign_q <= dd_init_realign_q + 1'b1;
      end
      assign tide_gc_realign_w = ~(&dd_init_realign_q);

      tide_dd_top #(
        .NHART(1), .NCH(16), .NRQ(16), .TQ_DEPTH(32),
        .RQ_DEPTH(4), .TQ_GUARD(8), .NSYNC_SET(16), .XBOARD_K(2)
      ) u_tide_dd_top (
        .clk_i(clk), .rst_ni(rst_n), .realign_i(tide_gc_realign_w),
        .enq_valid_i(tide_enq_req_w.valid),
        .enq_mask_i(tide_enq_req_w.mask),
        .enq_code_i(tide_enq_req_w.code),
        .enq_pi_i(tide_enq_req_w.pi),
        .enq_ts_i(tide_enq_req_w.ts_prime),
        .enq_pc_i(tide_enq_req_w.pc),
        .enq_stall_o(tide_enq_rsp_w.stall),
        .enq_illegal_o(tide_enq_rsp_w.illegal),
        .enq_tq_err_o(tide_enq_rsp_w.tq_err),
        .enq_tqcause_o(tide_enq_rsp_w.tqcause),
        .enq_ch_o(tide_enq_rsp_w.ch),
        .rq_pop_valid_i(tide_rq_req_w.valid),
        .rq_idx_i(tide_rq_req_w.rq_idx),
        .rq_valid_o(tide_rq_rsp_w.valid),
        .rq_result_o(tide_rq_rsp_w.result),
        .sync_valid_i({tide_sync_req_w.valid}),
        .sync_gid_i({tide_sync_req_w.gid}),
        .sync_anchor_o(tide_sync_anchor_w),
        .trap_valid_o(tide_trap_w.valid),
        .trap_failstop_o(tide_trap_w.is_failstop),
        .trap_cause_o(dd_trap_cause),
        .trap_class_o(dd_trap_class),
        .trap_target_is_queue_o(tide_trap_w.target_is_queue),
        .trap_target_idx_o(tide_trap_w.target_idx),
        .trap_ts_o(tide_trap_w.ts),
        .trap_gid_o(tide_trap_w.gid),
        .halt_o(tide_halt_w),
        .csr_valid_i(tide_csr_req_w.valid),
        .csr_write_i(tide_csr_req_w.write),
        .csr_addr_i(tide_csr_req_w.addr),
        .csr_wdata_i(tide_csr_req_w.wdata),
        .csr_tlr_i(tide_csr_req_w.tlr),
        .csr_rsp_valid_o(tide_csr_rsp_w.valid),
        .csr_rdata_o(tide_csr_rsp_w.rdata),
        .csr_illegal_o(tide_csr_rsp_w.illegal),
        .mmio_valid_i(tide_mmio_req_w.valid),
        .mmio_write_i(tide_mmio_req_w.write),
        .mmio_addr_i(tide_mmio_req_w.addr),
        .mmio_be_i(tide_mmio_req_w.be),
        .mmio_wdata_i(tide_mmio_req_w.wdata),
        .mmio_rsp_valid_o(tide_mmio_rsp_w.valid),
        .mmio_rsp_rdata_o(tide_mmio_rsp_w.rdata),
        .mmio_rsp_err_o(tide_mmio_rsp_w.err),
        .commit_valid_o(dd_commit_valid),
        .commit_ts_o(dd_commit_ts),
        .commit_code_o(dd_commit_code),
        .completion_valid_i(dd_completion_valid),
        .completion_result_i(dd_completion_result),
        .completion_tdone_i(dd_completion_tdone),
        .backend_err_valid_i(1'b0),
        .backend_err_cause_i(tide_dd_pkg::TqCauseFbStale),
        .backend_err_ch_i(5'd0),
        .backend_err_ts_i(48'd0)
      );

      // Identity backend for the integration smoke test: every committed
      // event produces its completion record in the same channel/queue.
      assign dd_completion_valid  = dd_commit_valid;
      assign dd_completion_result = dd_commit_code;
      assign dd_completion_tdone  = dd_commit_ts;
      assign tide_trap_w.tqcause = ibex_tide_pkg::tide_tqcause_e'(dd_trap_cause);
      assign tide_trap_w.trap_class =
          ibex_tide_pkg::tide_trap_class_e'(dd_trap_class);
      // tide_gc_realign_w is generated above as the power-on P2 pulse.
`else
      tide_dd_stub u_tide_dd_stub (
        .clk           (clk                ),
        .rst_n         (rst_n              ),
        .enq_req_i     (tide_enq_req_w     ),
        .enq_rsp_o     (tide_enq_rsp_w     ),
        .rq_req_i      (tide_rq_req_w      ),
        .rq_rsp_o      (tide_rq_rsp_w      ),
        .sync_req_i    (tide_sync_req_w    ),
        .sync_anchor_o (tide_sync_anchor_w ),
        .gc_realign_o  (tide_gc_realign_w  ),
        .trap_o        (tide_trap_w        ),
        .halt_o        (tide_halt_w        ),
        .csr_req_i     (tide_csr_req_w     ),
        .csr_rsp_o     (tide_csr_rsp_w     ),
        .mmio_req_i    (tide_mmio_req_w    ),
        .mmio_rsp_o    (tide_mmio_rsp_w    )
      );
`endif
    end else begin : gen_tide_dd_off
      // TIDE_EN=0: pre-TIDE constants on the DD-side inputs.
      assign tide_enq_rsp_w     = '0;
      assign tide_rq_rsp_w      = '0;
      assign tide_sync_anchor_w = 1'b0;
      assign tide_gc_realign_w  = 1'b0;
      assign tide_trap_w        = '0;
      assign tide_halt_w        = 1'b0;
      assign tide_csr_rsp_w     = '0;
      assign tide_mmio_rsp_w    = '0;
      // TIDE_EN=0: the core's TIDE request outputs are unused.
      logic unused_tide_reqs;
      assign unused_tide_reqs = |{tide_enq_req_w, tide_rq_req_w,
                                   tide_sync_req_w, tide_csr_req_w,
                                   tide_mmio_req_w};
    end
  endgenerate

  `define IBEX_RF_PATH core_ibex_tb_top.dut.u_ibex_top.gen_regfile_ff.register_file_i

  // We should never see any alerts triggered in normal testing
  `ASSERT(NoAlertsTriggered,
    !dut_if.alert_minor && !dut_if.alert_major_internal && !dut_if.alert_major_bus, clk, !rst_n)
  `DV_ASSERT_CTRL("tb_no_alerts_triggered", core_ibex_tb_top.NoAlertsTriggered)

  `DV_ASSERT_CTRL("tb_no_spurious_response",
    core_ibex_tb_top.dut.u_ibex_top.u_ibex_core.NoMemResponseWithoutPendingAccess)
  `DV_ASSERT_CTRL("tb_no_spurious_response",
    core_ibex_tb_top.dut.u_ibex_top.MaxOutstandingDSideAccessesCorrect)
  `DV_ASSERT_CTRL("tb_no_spurious_response",
    core_ibex_tb_top.dut.u_ibex_top.PendingAccessTrackingCorrect)

  if (SecureIbex) begin : g_lockstep_assert_ctrl
    `define IBEX_LOCKSTEP_PATH core_ibex_tb_top.dut.u_ibex_top.gen_lockstep.u_ibex_lockstep
    `DV_ASSERT_CTRL("tb_no_spurious_response",
      `IBEX_LOCKSTEP_PATH.u_shadow_core.NoMemResponseWithoutPendingAccess)
  end

  if (BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT) begin : g_trvk_assert_ctrl
    // Disable TRVK's alignment FIFO assertion alongside the other spurious response checks.
    `DV_ASSERT_CTRL("tb_no_spurious_response",
      core_ibex_tb_top.dut.u_ibex_top.gen_cheriot_trvk.i_ibex_trvk.AlignValidOnRsp_A)
  end

`ifndef DV_FCOV_DISABLE
  assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.rf_glitch_err =
    dut.u_ibex_top.alert_major_internal_o;
  assign dut.u_ibex_top.u_ibex_core.u_fcov_bind.lockstep_glitch_err =
    dut.u_ibex_top.lockstep_alert_major_internal;
`endif

  // Data load/store vif connection
  assign data_mem_vif.reset = ~rst_n;
  // Instruction fetch vif connection
  assign instr_mem_vif.reset = ~rst_n;
  assign instr_mem_vif.we    = 0;
  assign instr_mem_vif.be    = 0;
  assign instr_mem_vif.wdata = 0;
  // RVFI interface connections
  assign rvfi_if.reset                = ~rst_n;
  assign rvfi_if.valid                = dut.rvfi_valid;
  assign rvfi_if.order                = dut.rvfi_order;
  assign rvfi_if.insn                 = dut.rvfi_insn;
  assign rvfi_if.trap                 = dut.rvfi_trap;
  assign rvfi_if.intr                 = dut.rvfi_intr;
  assign rvfi_if.mode                 = dut.rvfi_mode;
  assign rvfi_if.ixl                  = dut.rvfi_ixl;
  assign rvfi_if.rs1_addr             = dut.rvfi_rs1_addr;
  assign rvfi_if.rs2_addr             = dut.rvfi_rs2_addr;
  assign rvfi_if.rs1_rdata            = dut.rvfi_rs1_rdata;
  assign rvfi_if.rs2_rdata            = dut.rvfi_rs2_rdata;
  assign rvfi_if.rd_addr              = dut.rvfi_rd_addr;
  assign rvfi_if.rd_wdata             = dut.rvfi_rd_wdata;
  assign rvfi_if.pc_rdata             = dut.rvfi_pc_rdata;
  assign rvfi_if.pc_wdata             = dut.rvfi_pc_wdata;
  assign rvfi_if.mem_addr             = dut.rvfi_mem_addr;
  assign rvfi_if.mem_rmask            = dut.rvfi_mem_rmask;
  assign rvfi_if.mem_rdata            = dut.rvfi_mem_rdata;
  assign rvfi_if.mem_wdata            = dut.rvfi_mem_wdata;
  assign rvfi_if.ext_pre_mip          = dut.rvfi_ext_pre_mip;
  assign rvfi_if.ext_post_mip         = dut.rvfi_ext_post_mip;
  assign rvfi_if.ext_nmi              = dut.rvfi_ext_nmi;
  assign rvfi_if.ext_nmi_int          = dut.rvfi_ext_nmi_int;
  assign rvfi_if.ext_debug_req        = dut.rvfi_ext_debug_req;
  assign rvfi_if.ext_rf_wr_suppress   = dut.rvfi_ext_rf_wr_suppress;
  assign rvfi_if.ext_mcycle           = dut.rvfi_ext_mcycle;
  assign rvfi_if.ext_mhpmcounters     = dut.rvfi_ext_mhpmcounters;
  assign rvfi_if.ext_mhpmcountersh    = dut.rvfi_ext_mhpmcountersh;
  assign rvfi_if.ext_ic_scr_key_valid = dut.rvfi_ext_ic_scr_key_valid;
  assign rvfi_if.ext_irq_valid        = dut.rvfi_ext_irq_valid;
  // Irq interface connections
  assign irq_vif.reset = ~rst_n;
  // Dut_if interface connections
  assign dut_if.ecall            = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ecall_insn;
  assign dut_if.wfi              = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.wfi_insn;
  assign dut_if.ebreak           = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ebrk_insn;
  assign dut_if.illegal_instr
      = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.illegal_insn_d;
  assign dut_if.dret             = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.dret_insn;
  assign dut_if.mret             = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.mret_insn;
  assign dut_if.reset            = ~rst_n;
  assign dut_if.ic_tag_req       = dut.u_ibex_top.ic_tag_req;
  assign dut_if.ic_tag_write     = dut.u_ibex_top.ic_tag_write;
  assign dut_if.ic_tag_addr      = dut.u_ibex_top.ic_tag_addr;
  assign dut_if.ic_data_req      = dut.u_ibex_top.ic_data_req;
  assign dut_if.ic_data_write    = dut.u_ibex_top.ic_data_write;
  assign dut_if.ic_data_addr     = dut.u_ibex_top.ic_data_addr;
  assign dut_if.priv_mode        = dut.u_ibex_top.u_ibex_core.priv_mode_id;
  assign dut_if.ctrl_fsm_cs      = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ctrl_fsm_cs;
  assign dut_if.debug_mode       = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.debug_mode_q;
  assign dut_if.rf_ren_a         = dut.u_ibex_top.u_ibex_core.rf_ren_a;
  assign dut_if.rf_ren_b         = dut.u_ibex_top.u_ibex_core.rf_ren_b;
  assign dut_if.rf_rd_a_wb_match = dut.u_ibex_top.u_ibex_core.rf_rd_a_wb_match;
  assign dut_if.rf_rd_b_wb_match = dut.u_ibex_top.u_ibex_core.rf_rd_b_wb_match;
  assign dut_if.rf_write_wb      = dut.u_ibex_top.u_ibex_core.rf_write_wb;
  assign dut_if.sync_exc_seen    =
      dut.u_ibex_top.u_ibex_core.cs_registers_i.cpuctrlsts_part_q.sync_exc_seen;
  assign dut_if.csr_save_cause   = dut.u_ibex_top.u_ibex_core.csr_save_cause;
  assign dut_if.exc_cause        = dut.u_ibex_top.u_ibex_core.exc_cause;
  assign dut_if.wb_exception     = dut.u_ibex_top.u_ibex_core.id_stage_i.wb_exception;
  // Instruction monitor connections
  assign instr_monitor_if.reset        = ~rst_n;
  assign instr_monitor_if.valid_id     = dut.u_ibex_top.u_ibex_core.id_stage_i.instr_valid_i;
  assign instr_monitor_if.rvfi_id_done = dut.u_ibex_top.u_ibex_core.rvfi_id_done;

  assign instr_monitor_if.err_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.instr_fetch_err;

  assign instr_monitor_if.is_compressed_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.instr_is_compressed_i;

  assign instr_monitor_if.instr_compressed_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.instr_rdata_c_i;

  assign instr_monitor_if.instr_id = dut.u_ibex_top.u_ibex_core.id_stage_i.instr_rdata_i;
  assign instr_monitor_if.pc_id    = dut.u_ibex_top.u_ibex_core.pc_id;

  assign instr_monitor_if.branch_taken_id =
    dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.branch_set_i;

  assign instr_monitor_if.branch_target_id = dut.u_ibex_top.u_ibex_core.branch_target_ex;
  assign instr_monitor_if.stall_id         = dut.u_ibex_top.u_ibex_core.id_stage_i.stall_id;
  assign instr_monitor_if.jump_set_id      = dut.u_ibex_top.u_ibex_core.id_stage_i.jump_set;
  assign instr_monitor_if.rvfi_order_id    = dut.u_ibex_top.u_ibex_core.rvfi_stage_order_d;
  // CSR interface connections
  assign csr_if.csr_access = dut.u_ibex_top.u_ibex_core.csr_access;
  assign csr_if.csr_addr   = dut.u_ibex_top.u_ibex_core.csr_addr;
  assign csr_if.csr_wdata  = dut.u_ibex_top.u_ibex_core.csr_wdata;
  assign csr_if.csr_rdata  = dut.u_ibex_top.u_ibex_core.csr_rdata;
  assign csr_if.csr_op     = dut.u_ibex_top.u_ibex_core.csr_op;

  assign ifetch_if.reset           = ~dut.u_ibex_top.u_ibex_core.if_stage_i.rst_ni;
  assign ifetch_if.fetch_ready     = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_ready;
  assign ifetch_if.fetch_valid     = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_valid;
  assign ifetch_if.fetch_rdata     = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_rdata;
  assign ifetch_if.fetch_addr      = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_addr;
  assign ifetch_if.fetch_err       = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_err;
  assign ifetch_if.fetch_err_plus2 = dut.u_ibex_top.u_ibex_core.if_stage_i.fetch_err_plus2;

  assign ifetch_pmp_if.reset         = ~dut.u_ibex_top.u_ibex_core.if_stage_i.rst_ni;
  assign ifetch_pmp_if.fetch_valid   = dut.u_ibex_top.u_ibex_core.instr_req_o;
  assign ifetch_pmp_if.fetch_addr    = dut.u_ibex_top.u_ibex_core.instr_addr_o;
  assign ifetch_pmp_if.fetch_pmp_err = dut.u_ibex_top.u_ibex_core.pmp_req_err[ibex_pkg::PMP_I];

  assign data_mem_vif.misaligned_first =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.handle_misaligned_d |
    ((dut.u_ibex_top.u_ibex_core.load_store_unit_i.lsu_type_i == 2'b01) &
     (dut.u_ibex_top.u_ibex_core.load_store_unit_i.data_offset == 2'b01));

  assign data_mem_vif.misaligned_second =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.addr_incr_req_o;

  assign data_mem_vif.misaligned_first_saw_error =
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.addr_incr_req_o &
    dut.u_ibex_top.u_ibex_core.load_store_unit_i.lsu_err_d;

  assign data_mem_vif.m_mode_access =
    dut.u_ibex_top.u_ibex_core.priv_mode_lsu == ibex_pkg::PRIV_LVL_M;

  initial begin
    // Drive the clock and reset lines. Reset everything and start the clock at the beginning of
    // time
    #0; // needed for dsim
    ibex_clk_if.set_active();
    fork
      ibex_clk_if.apply_reset(.reset_width_clks (100));
    join_none

    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "clk_if", ibex_clk_if);
    uvm_config_db#(virtual core_ibex_dut_probe_if)::set(null, "*", "dut_if", dut_if);
    uvm_config_db#(virtual core_ibex_instr_monitor_if)::set(null,
                                                            "*",
                                                            "instr_monitor_if",
                                                            instr_monitor_if);
    uvm_config_db#(virtual core_ibex_csr_if)::set(null, "*", "csr_if", csr_if);
    uvm_config_db#(virtual core_ibex_rvfi_if)::set(null, "*", "rvfi_if", rvfi_if);
    uvm_config_db#(virtual ibex_mem_intf)::set(null, "*data_if_response*", "vif", data_mem_vif);
    uvm_config_db#(virtual ibex_mem_intf)::set(null, "*instr_if_response*", "vif", instr_mem_vif);
    uvm_config_db#(virtual irq_if)::set(null, "*", "vif", irq_vif);
    uvm_config_db#(virtual core_ibex_ifetch_if)::set(null, "*", "ifetch_if", ifetch_if);
    uvm_config_db#(virtual core_ibex_ifetch_pmp_if)::set(null, "*", "ifetch_pmp_if",
                   ifetch_pmp_if);
    uvm_config_db#(scrambling_key_vif)::set(
      null, "*.env.scrambling_key_agent*", "vif", scrambling_key_if);

    // Expose ISA config parameters to UVM DB
    uvm_config_db#(bit)::set(null, "*", "RV32E", RV32E);
    uvm_config_db#(ibex_pkg::rv32m_e)::set(null, "*", "RV32M", RV32M);
    uvm_config_db#(ibex_pkg::rv32b_e)::set(null, "*", "RV32B", RV32B);

    if (PMPEnable) begin
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPNumRegions", PMPNumRegions);
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPGranularity", PMPGranularity);
    end else begin
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPNumRegions", 0);
      uvm_config_db#(bit [31:0])::set(null, "*", "PMPGranularity", 0);
    end

    uvm_config_db#(bit [31:0])::set(null, "*", "MHPMCounterNum", MHPMCounterNum);
    uvm_config_db#(bit)::set(null, "*", "SecureIbex", SecureIbex);
    uvm_config_db#(bit)::set(null, "*", "CHERIoT",
                             BaseIsa == ibex_pkg::BaseIsaRV32IorCHERIoT);
    uvm_config_db#(bit)::set(null, "*", "ICache", ICache);

    run_test();
  end

  // Manually set unused_assert_connected = 1 to disable the AssertConnected_A assertion for
  // prim_count in case lockstep (set by SecureIbex) is enabled and the lockstep offset is
  // larger than 1. If not disabled, DV fails.
  if (SecureIbex && LockstepOffset > 1) begin : gen_disable_count_check
    assign dut.u_ibex_top.gen_lockstep.u_ibex_lockstep.gen_reset_counter.u_rst_shadow_cnt.
          unused_assert_connected = 1;
  end

  ibex_pkg::ctrl_fsm_e controller_state;
  logic                controller_handle_irq;
  ibex_pkg::irqs_t     ibex_irqs, last_ibex_irqs;

  assign controller_state      = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.ctrl_fsm_cs;
  assign controller_handle_irq = dut.u_ibex_top.u_ibex_core.id_stage_i.controller_i.handle_irq;
  assign ibex_irqs             = dut.u_ibex_top.u_ibex_core.irqs;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_ibex_irqs <= '0;
    end else begin
      last_ibex_irqs <= ibex_irqs;
    end
  end

  always_ff @(posedge clk) begin
    if (controller_state == ibex_pkg::IRQ_TAKEN) begin
      if (!controller_handle_irq) begin
        $display("WARNING: Controller in IRQ_TAKEN but no IRQ to handle, returning to DECODE");
        $display("IRQs last cycle: %x, IRQs this cycle: %x", last_ibex_irqs, ibex_irqs);
      end else if (last_ibex_irqs != ibex_irqs) begin
        $display("WARNING: Controller in IRQ_TAKEN and IRQs have just changed");
        $display("IRQs last cycle: %x, IRQs this cycle: %x", last_ibex_irqs, ibex_irqs);
      end
    end
  end
endmodule
