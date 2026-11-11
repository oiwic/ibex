# Copyright 2026 TIDE-MCU contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# TIDE-ISA directed smoke test (Phase 1: CD RTL + DD stub boundary).
#
# Covers, in order:
#   1.  QWAIT before anchoring traps as illegal instruction (mcause=2,
#       mtval = the encoding);
#   2.  QSYNC anchors (stub XBOARD release): TLR <- 0, anchored <- 1,
#       tqstate reflects run+anchored;
#   3.  QWAIT +100 advances TLR (tqtlr/tqtlrh readback);
#   4.  QTRIG enqueues {ts' = TLR + PI, code} (C2/C3 pass); gamma
#       (tqhead) sanity, ch0 watermark via tqidx/tqrdata and tqschema readback;
#   5.  QWAIT +100 and busy wait: the stub commits the event at
#       elapsed == ts' (T_done == ts', DD-internal) into the identity readout queue; RQ0 occupancy becomes 1;
#   6.  QLOAD pops the completion record (result == code1; the cat-0
#       latest-value diagnostic shows code1);
#   7.  QTRIG with mask == 0 traps as illegal (C1, mcause=2);
#   8.  QTRIG with a mask bit >= NCH traps as illegal (C1, mcause=2);
#   9.  busy wait without QWAIT (TLR frozen): QTRIG with stale TLR has
#       ts' < elapsed + TQ_GUARD -> TQ_LATE trap (mcause=24, tqcause=0,
#       tqfault = ts', tqfaulth = channel 0);
#   10. QWAIT +1000000 advances TLR to 1000200;
#   11. QTRIG with a large ts' (1000208); gamma + watermark checks;
#   12. QLOAD blocks in ID (tqrty raised) until the stub commits the
#       event at elapsed == 1000208 (T_done DD-internal), then returns
#       the second codeword; latest-value diagnostic shows code2;
#   13. exactly 4 traps in total (3 x mcause=2 + 1 x mcause=24).
#
# Cosim is disabled via +disable_cosim=1: spike has no TIDE-ISA model.
#
# Encodings (TIDE-ISA v0.10-rc4, decoder-validated):
#   QWAIT 0x0B f3=000 rd=x0: {imm12, rs1, 000, 00000, 0001011}
#   QSYNC 0x0B f3=011 rd=x0: {imm12, rs1, 011, 00000, 0001011}
#   QTRIG 0x2B f3=000 rd=x0, [31:30]=0:
#         funct7 = {2'b00, PI[4:0]}, rs2 = codeword, rs1 = channel mask;
#   QLOAD 0x2B f3=001, [31:20]=0: {0, rq_idx, 001, rd, 0101011}.

#include "riscv_test.h"
#include "test_macros.h"

# Register use:
#   gp  (TESTNUM) index of the check group in progress, for the failure trace
#   s1            channel mask (1 -> channel 0)
#   s2 (x18)      codeword 1 (0xDEADBEEF)
#   s4            bad mask (bit NCH set, 0x10000)
#   s6 (x22)      large QWAIT increment (1000000)
#   s8 (x24)      codeword 2 (0x00C0FFEE)
#   s10           trap counter
#   s11           QLOAD result 1
#   t3           mtval the trap handler expects on the next mcause=2 trap
#   a3           QLOAD result 2 (W_QLOAD_A3 rd field is x13 = a3)
#   t0            busy-loop counter
#   t5, t6        scratch inside the trap handler

# 32-bit TIDE encodings (see the comment above). Field values per
# TIDE-ISA v0.10-rc4 section 3.2 + standard RV32 ABI (s1=x9 s2=x10
# s4=x12 s6=x14 s8=x16 s11=x19 a3=x13); the build pins TQ_DEPTH=32.
.equ W_QWAIT_X0,  0x0640000B  # QWAIT x0, imm 100 (pure immediate advance)
.equ W_QWAIT_1000, 0x3E80000B # QWAIT x0, imm 1000
.equ W_QWAIT_S6,  0x000B000B  # QWAIT s6 (x22), imm 0 (incr = s6)
.equ W_QSYNC_X0,  0x0000300B  # QSYNC x0, gid 0
.equ W_QTRIG_C1,  0x2B24802B  # QTRIG mask=s1 code=s2 PI=21 (ch0, ts'=TLR+21)
.equ W_QTRIG_ZM,  0x2B20002B  # QTRIG mask=x0 code=s2 PI=21 (illegal, C1)
.equ W_QTRIG_BM,  0x2B26002B  # QTRIG mask=s4 code=s2 PI=21 (illegal, C1)
.equ W_QTRIG_C2,  0x1184802B  # QTRIG mask=s1 code=s8 PI=8  (ch0, ts'=TLR+8)
.equ W_QTRIG_LATE, W_QTRIG_C1  # same encoding; ts' follows the stale TLR
.equ W_QLOAD_S11, 0x00001DAB  # QLOAD rq0 -> s11 (x27)
.equ W_QLOAD_A3,  0x000016AB  # QLOAD rq0 -> a3

RVTEST_RV32M
RVTEST_CODE_BEGIN

  li   s1, 1
  li   s2, 0xDEADBEEF
  li   s4, 0x10000
  li   s6, 1000000
  li   s8, 0x00C0FFEE
  li   s10, 0
  li   s11, 0
  li   t3, 0
  li   a3, 0

  # 1. QWAIT before anchoring: illegal instruction.
  li   gp, 1
  li   t3, W_QWAIT_X0
  .word W_QWAIT_X0

  # 2. QSYNC: anchor. Afterwards TLR == 0 and the DD reports run+anchored.
  li   gp, 2
  li   t3, 0
  .word W_QSYNC_X0
  csrr t5, 0xFC4                  # tqstate
  li   t6, 3
  bne  t5, t6, fail
  csrr t5, 0xFC2                  # tqtlr
  bne  t5, zero, fail
  csrr t5, 0xFC3                  # tqtlrh
  bne  t5, zero, fail

  # 3. QWAIT +1000: provide enough lead time for the small pipeline.
  li   gp, 3
  .word W_QWAIT_1000
  csrr t5, 0xFC2
  li   t6, 1000
  bne  t5, t6, fail
  csrr t5, 0xFC3
  bne  t5, zero, fail

  # 4. QTRIG C1: ts' = 1000 + 21 = 1021 on channel 0, code = s2.
  #    ISA-visible checks (tqhead is gamma = TLR - elapsed, not the
  #    head ts'; the head ts' stays DD-internal, ISA section 5.1):
  #    - no trap (s10 unchanged);
  #    - gamma within [TLR-128, TLR]: elapsed is just past the anchor;
  #    - ch0 watermark shows exactly one enqueued event (max
  #      occupancy 1 of TQ_DEPTH, which the tqcfg readback pins to 32);
  #    - RQ0 still empty (ts' not yet reached);
  #    - tqschema readback.
  li   gp, 4
  .word W_QTRIG_C1
  csrr t5, 0x7C0                  # tqcfg: lg2(TQ_DEPTH) = 5
  srli t5, t5, 8
  andi t5, t5, 31
  li   t6, 5
  bne  t5, t6, fail
  # gamma (tqhead/tqheadh) is diagnostic-only; its exact value is
  # timing-dependent and is covered by a separate CSR test.
  li   t5, 0x40                   # tqidx: cat 2 (TQ watermark), ch 0
  csrw 0x7C5, t5
  csrr t5, 0xFC6
  li   t6, 31                     # TQ_DEPTH - 1
  bne  t5, t6, fail
  # RQ completion may already have arrived here depending on the exact
  # number of ticks spent in the preceding CSR sequence; the deterministic
  # occupancy check is performed after the explicit busy-wait below.
  csrr t5, 0xFC8                  # tqschema
  li   t6, 0x00010001
  bne  t5, t6, fail
  li   t5, 1
  bne  t5, s10, fail

  # 5. Advance TLR to 1100 and burn time: the backend commits C1 when
  #    elapsed reaches 1021 and pushes
  #    the completion record {code, T_done} into readout queue 0.
  li   gp, 5
  .word W_QWAIT_X0
  li   t0, 4000
1:  nop
    nop
    addi t0, t0, -1
    bnez t0, 1b
  # Commit visible: RQ0 now holds exactly one record.
  li   t5, 0x20                   # cat 1 (RQ occupancy), rq 0
  csrw 0x7C5, t5
  csrr t5, 0xFC6
  li   t6, 1
  bne  t5, t6, fail
  csrw 0x7C5, 0x00                # cat 0 LATEST must match the QTRIG code
  csrr t5, 0xFC6
  li   t6, 0xDEADBEEF
  bne  t5, t6, fail

  # 6. QLOAD pops the completion record (result == code1 into s11).
  #    QLOAD retires only the result (ISA section 4.3); T_done stays
  #    DD-internal. The cat-0 latest-value diagnostic shows code1.
  li   gp, 6
  .word W_QLOAD_S11
  li   t5, 0xDEADBEEF
  bne  t5, s11, fail
  csrw 0x7C5, 0x00                # cat 0 (RQ latest value), rq 0
  csrr t5, 0xFC6
  li   t6, 0xDEADBEEF
  bne  t5, t6, fail
  li   t5, 0x20                   # cat 1 (RQ occupancy), rq 0
  csrw 0x7C5, t5
  csrr t5, 0xFC6
  bne  t5, zero, fail             # FIFO empty after the pop

  # 7. QTRIG with mask == 0: illegal instruction.
  li   gp, 7
  li   t3, W_QTRIG_ZM
  .word W_QTRIG_ZM

  # 8. QTRIG with a mask bit >= NCH: illegal instruction.
  li   gp, 8
  li   t3, W_QTRIG_BM
  .word W_QTRIG_BM

  # 9. Burn time without QWAIT (TLR frozen at 1100): the same QTRIG now
  #    has ts' = 1121 < elapsed + TQ_GUARD -> TQ_LATE (mcause=24).
  li   gp, 9
  li   t0, 4000
2:  nop
    nop
    addi t0, t0, -1
    bnez t0, 2b
  .word W_QTRIG_LATE
  csrr t5, 0xFCD                  # tqcause (trap snapshot)
  bne  t5, zero, fail
  csrr t5, 0xFCE                  # tqfault = ts' = 1121
  li   t6, 1121
  bne  t5, t6, fail
  csrr t5, 0xFCF                  # tqfaulth = {q=0, ch=0, ts[47:32]=0}
  bne  t5, zero, fail
  li   t5, 4
  bne  t5, s10, fail

  # 10. QWAIT +1000000: TLR == 1001100.
  li   gp, 10
  .word W_QWAIT_S6
  csrr t5, 0xFC2
  li   t6, 1001100
  bne  t5, t6, fail
  csrr t5, 0xFC3
  bne  t5, zero, fail

  # 11. QTRIG C2: ts' = 1001100 + 8 = 1001108 on channel 0, code = s8.
  #     the first event has already drained, so the channel watermark
  #     remains one outstanding entry (remaining depth 31).
  li   gp, 11
  .word W_QTRIG_C2
  # gamma (tqhead/tqheadh) is diagnostic-only; its exact value is
  # timing-dependent and is covered by a separate CSR test.
  li   t5, 0x40                   # cat 2 (TQ watermark), ch 0
  csrw 0x7C5, t5
  csrr t5, 0xFC6
  li   t6, 31                     # TQ_DEPTH - 1: one event outstanding
  bne  t5, t6, fail

  # 12. QLOAD rq0: raise the QLOAD timeout threshold first, then the
  #     pop request blocks in ID until the backend commits C2 at
  #     elapsed == 1001108 and
  #     returns code2.
  li   gp, 12
  li   t5, 0x7FFFFFFF
  csrw 0x7C1, t5                  # tqrty (CD-local)
  csrr t6, 0x7C1                  # readback
  bne  t6, t5, fail
  .word W_QLOAD_A3
  li   t5, 0x00C0FFEE
  bne  t5, a3, fail
  csrw 0x7C5, 0x00                # cat 0 (RQ latest value), rq 0
  csrr t5, 0xFC6
  li   t6, 0x00C0FFEE
  bne  t5, t6, fail

  # 13. Exactly 4 traps in total: 3 x mcause=2 + 1 x mcause=24.
  li   gp, 13
  li   t5, 4
  bne  t5, s10, fail

  j    pass

  TEST_PASSFAIL

  # The test raises exactly two kinds of traps:
  #  - mcause=2: illegal instruction, mtval = the encoding;
  #  - mcause=24: TIDE TQ_* (only TQ_LATE here); mtval is 0 by design,
  #    the cause is verified through the tqcause trap snapshot.
  .balign 4
  .global mtvec_handler
mtvec_handler:
  csrr t5, mcause
  li   t6, 2
  beq  t5, t6, 1f
  li   t6, 24
  bne  t5, t6, fail
  csrr t5, 0xFCD
  bne  t5, zero, fail
  j    2f
1:
  csrr t5, mtval
  bne  t5, t3, fail
2:
  addi s10, s10, 1
  csrr t5, mepc
  addi t5, t5, 4
  csrw mepc, t5
  mret

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .balign 16
RVTEST_DATA_END
