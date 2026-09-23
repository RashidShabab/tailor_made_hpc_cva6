#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
for top in tb_tmh_event_gen_linear tb_cva6_tmh_unit; do
  out="$PWD/build/$top"
  mkdir -p "$out"
  verilator --binary --timing --trace --assert --timescale 1ns/1ps \
    --top-module "$top" --Mdir "$out/obj" \
    ../include/ariane_pkg_stub.sv ../include/tmh_pkg.sv \
    ../rtl/tmh_event_gen.sv ../rtl/tmh_counter_bank.sv \
    ../rtl/tmh_csr.sv ../rtl/cva6_tmh_unit.sv "../tb/$top.sv" \
    >"$out/build.log" 2>&1 || { cat "$out/build.log"; exit 1; }
  (cd "$out" && "./obj/V$top") | tee "$out/run.log"
done
