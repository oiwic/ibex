// Copyright 2026 TIDE-MCU contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Link shims for the prebuilt spike static libraries in the shared EDA
// container (/tools/riscv-isa-sim/lib).
//
// The archives were built on a newer host (glibc >= 2.34, GCC >= 12) and
// reference two symbols that the container's toolchain (glibc 2.27,
// GCC 7) does not export:
//
//   __libc_single_threaded         (glibc 2.34 global)
//   std::__throw_bad_array_new_length()  (libstdc++ internal helper)
//
// Both are defined here as weak symbols:
//  - On this container the weak definitions satisfy the archives.
//  - On a system whose libc/libstdc++ provides strong definitions, the
//    interposed references still resolve to a single consistent object
//    with identical semantics (glibc keeps updating the same global
//    through its dynamic relocation, and the exception helper performs
//    exactly the throw the real helper performs).
//
// This file is compiled as part of the cosim DPI link (ibex_dv_cosim_dpi.f)
// and is otherwise inert: it defines no DPI entry points and has no
// simulation-time effect.

#include <new>

// glibc >= 2.34: global used by libc to track the single-threaded fast path.
// Initial value false matches the pre-main state.
__attribute__((weak)) bool __libc_single_threaded = false;

namespace std {
// GCC >= 12 libstdc++ internal; hidden (not exported) in GCC 7's
// libstdc++.so, so the prebuilt archives' reference is unresolved without
// this definition.
__attribute__((weak)) [[noreturn]] void __throw_bad_array_new_length() {
  throw bad_array_new_length();
}
}  // namespace std