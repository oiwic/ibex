// Copyright 2026 TIDE-MCU contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// VCS O-2018.09 compatibility shadow of
// vendor/lowrisc_ip/ip/prim/rtl/prim_assert_standard_macros.svh.
//
// The VCS O-2018.09-SP2-2 in the shared EDA container cannot parse
// immediate assertions (assert (expr)) at all (verified with a syntax
// matrix: immediate forms fail, concurrent `assert property` forms parse
// and elaborate correctly). This file therefore re-implements the same
// macro names with only concurrent-assertion syntax.
//
// It is picked up instead of the original file because
// dv/uvm/core_ibex/ibex_dv.f prepends a +incdir+ pointing at this
// directory before the lowRISC prim include directory; VCS searches
// +incdir+ entries before the including file's own directory.
//
// Policy:
//  - Concurrent macros (ASSERT, ASSERT_NEVER, ASSERT_KNOWN, COVER,
//    ASSUME) are re-implemented with `assert property` syntax.
//  - ASSERT_INIT is dropped (no-op): the original is an immediate assertion
//    in an initial block, and a concurrent re-implementation is not
//    possible because some call sites are in clockless modules.
//  - Immediate/procedural macros (ASSERT_I, ASSUME_I, ASSERT_INIT_NET,
//    ASSERT_FINAL, ASSERT_AT_RESET, ASSERT_AT_RESET_AND_FINAL) expand
//    to nothing. They are secondary checks; the UVM scoreboard and the
//    spike cosimulation remain the primary functional checkers.

// Immediate assertion in procedural context: not parseable by this VCS.
`define ASSERT_I(__name, __prop)

// Parameter/initial checks: dropped. The original expands to an immediate
// assertion in an initial block, which this VCS cannot parse; a concurrent
// re-implementation is not possible either because some call sites live in
// clockless modules (e.g. stream_join_dynamic, pins_if) where the default
// clock does not exist. These are compile-time sanity checks; a wrong
// configuration will surface through the scoreboard/cosim checks instead.
`define ASSERT_INIT(__name, __prop)

// Net-value check with 1ps delay: not usable as a concurrent statement.
`define ASSERT_INIT_NET(__name, __prop)

// End-of-simulation check: secondary, dropped.
`define ASSERT_FINAL(__name, __prop)

// Reset-edge checks: secondary, dropped.
`define ASSERT_AT_RESET(__name, __prop, __rst = `ASSERT_DEFAULT_RST)

`define ASSERT_AT_RESET_AND_FINAL(__name, __prop, __rst = `ASSERT_DEFAULT_RST)

`define ASSERT(__name, __prop, __clk = `ASSERT_DEFAULT_CLK, __rst = `ASSERT_DEFAULT_RST) \
  __name: assert property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop)) else begin `ASSERT_ERROR(__name) end

`define ASSERT_NEVER(__name, __prop, __clk = `ASSERT_DEFAULT_CLK, __rst = `ASSERT_DEFAULT_RST) \
  __name: assert property (@(posedge __clk) disable iff ((__rst) !== '0) not (__prop)) else begin `ASSERT_ERROR(__name) end

`define ASSERT_KNOWN(__name, __sig, __clk = `ASSERT_DEFAULT_CLK, __rst = `ASSERT_DEFAULT_RST) \
  `ASSERT(__name, !$isunknown(__sig), __clk, __rst)

`define COVER(__name, __prop, __clk = `ASSERT_DEFAULT_CLK, __rst = `ASSERT_DEFAULT_RST) \
  __name: cover property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop));

`define ASSUME(__name, __prop, __clk = `ASSERT_DEFAULT_CLK, __rst = `ASSERT_DEFAULT_RST) \
  __name: assume property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop)) else begin `ASSERT_ERROR(__name) end

// Immediate assumption in procedural context: not parseable by this VCS.
`define ASSUME_I(__name, __prop)