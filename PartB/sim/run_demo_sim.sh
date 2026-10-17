#!/usr/bin/env bash
# Simulate the board-test top (B_demo_top) end to end, including the real
# Oled_Display driver. Takes a couple of minutes (160 ms of board time).
#   sim/run_demo_sim.sh          with the stub ledger
#   sim/run_demo_sim.sh partC    with C's real ledger (run sim/run_integration.sh first to fetch it)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
OUT="$ROOT/sim/out"; V="${1:-stub}"; RUN="$OUT/demo_$V"
mkdir -p "$RUN"
EXTRA=(); DEF=()
if [ "$V" = partC ]; then DEF=(-DUSE_PART_C); EXTRA=("$OUT/partC/ledger.v" "$OUT/partC/seq_divider.v"); fi
iverilog -g2005 ${DEF[@]+"${DEF[@]}"} -I "$ROOT/src/shared" -I "$ROOT/src/B_orders" -s tb_B_demo_top -o "$RUN/sim.vvp" \
    "$ROOT"/src/B_orders/*.v "$ROOT"/sim/stubs/*.v "$ROOT"/board/*.v \
    "$REPO/TradingSimProject.srcs/sources_1/imports/new/Oled_Display.v" \
    "$REPO/TradingSimProject.srcs/sources_1/imports/new/slower_clk.v" \
    ${EXTRA[@]+"${EXTRA[@]}"} "$ROOT/sim/integration/tb_B_demo_top.v" || exit 1
(cd "$RUN" && vvp -n sim.vvp) > "$RUN/log.txt" 2>&1
grep -E "^(PASS|FAIL)" "$RUN/log.txt"
[ -f "$RUN/demo_frame.hex" ] && python3 "$ROOT/tools/hex2png.py" "$RUN/demo_frame.hex" "$RUN/demo_frame.png" >/dev/null && echo "frame: $RUN/demo_frame.png"
grep -q "^PASS" "$RUN/log.txt"
