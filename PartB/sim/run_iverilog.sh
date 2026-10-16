#!/usr/bin/env bash
# Run Part B testbenches under Icarus Verilog.
#   sim/run_iverilog.sh                 all testbenches
#   sim/run_iverilog.sh tb_order_book   just one
# Output (.vvp, frame dumps, PNGs) goes to sim/out/.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/sim/out"
mkdir -p "$OUT"

SRC=("$ROOT"/src/B_orders/*.v)
STUBS=("$ROOT"/sim/stubs/*.v)
TBS=(tb_order_validate tb_order_book tb_exec_engine tb_ticket_screen tb_B_order_top)
[ $# -gt 0 ] && TBS=("$@")

status=0
for tb in "${TBS[@]}"; do
    if ! iverilog -g2005 -Wall -I "$ROOT/src/shared" -I "$ROOT/src/B_orders" \
            -s "$tb" -o "$OUT/$tb.vvp" \
            "${SRC[@]}" "${STUBS[@]}" "$ROOT/sim/B_orders/$tb.v"; then
        echo "FAIL: $tb did not compile"; status=1; continue
    fi
    log="$OUT/$tb.log"
    (cd "$OUT" && vvp -n "$tb.vvp") > "$log" 2>&1
    grep -E "^(PASS|FAIL)" "$log" || { echo "FAIL: $tb printed no verdict (see $log)"; status=1; }
    grep -q "^FAIL" "$log" && status=1
done

# frame dumps -> PNG
for hex in "$OUT"/*.hex; do
    [ -e "$hex" ] && python3 "$ROOT/tools/hex2png.py" "$hex" "${hex%.hex}.png" >/dev/null
done
exit $status
