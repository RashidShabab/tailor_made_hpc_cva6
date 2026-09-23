#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export CVA6_REPO_DIR=$(cd "$here/../../cva6-core" && pwd)
export HPDCACHE_DIR="$CVA6_REPO_DIR/core/cache_subsystem/hpdcache"
export TARGET_CFG=cv64a6_imafdc_sv39
baseline=81245a47fad8fe1a5d562d953ef2662e099def76
if [[ $(git -C "$CVA6_REPO_DIR" rev-parse HEAD) != "$baseline" ]]; then
  echo "Expected pinned CVA6 revision $baseline; inspect a changed baseline before testing." >&2
  exit 1
fi
cmp "$here/../include/tmh_pkg.sv" "$CVA6_REPO_DIR/core/tmh/tmh_pkg.sv"
for source in tmh_event_gen tmh_counter_bank tmh_csr cva6_tmh_unit; do
  cmp "$here/../rtl/$source.sv" "$CVA6_REPO_DIR/core/tmh/$source.sv"
done
variant=${1:-enabled}
case "$variant" in
  enabled) enabled=1; scenarios=(0 2 3 4) ;;
  disabled) enabled=0; scenarios=(1) ;;
  *) echo "Usage: $0 [enabled|disabled]" >&2; exit 2 ;;
esac
out="$here/build/cva6_integration_$variant"
mkdir -p "$out"
cd "$CVA6_REPO_DIR"
verilator --binary --timing --trace --assert -j 4 \
  --top-module tb_cva6_tmh_integration --Mdir "$out/obj" \
  -GTmhEnabled="1'b$enabled" \
  --timescale 1ns/1ps --unroll-count 256 \
  -Wno-fatal -Werror-PINMISSING -Werror-IMPLICIT -Wno-BLKANDNBLK \
  verilator_config.vlt -f core/Flist.cva6 \
  "$here/../tb/tb_cva6_tmh_integration.sv" \
  >"$out/build.log" 2>&1 || { tail -n 100 "$out/build.log"; exit 1; }
for scenario in "${scenarios[@]}"; do
  mkdir -p "$out/scenario_$scenario"
  (cd "$out/scenario_$scenario" && ../obj/Vtb_cva6_tmh_integration +SCENARIO="$scenario") | tee "$out/scenario_$scenario/run.log"
done
