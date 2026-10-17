#!/usr/bin/env bash
# Run Part B against Part C's real ledger (tb_BC_ledger).
#   sim/run_integration.sh                       C files from origin/branch-tricia-ledger
#   sim/run_integration.sh path/to/C/sources     C files from a folder (ledger.v, seq_divider.v)
# C's files are copied into sim/out/partC/ (git-ignored), never into PartB/.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/sim/out"
C="$OUT/partC"
mkdir -p "$C"

if [ $# -gt 0 ]; then
    cp "$1/ledger.v" "$1/seq_divider.v" "$C/"
else
    REF=origin/branch-tricia-ledger
    git -C "$ROOT" fetch -q origin 2>/dev/null
    for f in ledger.v seq_divider.v; do
        git -C "$ROOT" show "$REF:TradingSimProject.srcs/sources_1/new/$f" > "$C/$f" || exit 1
    done
    echo "Part C from $REF @ $(git -C "$ROOT" rev-parse --short $REF)"
fi

iverilog -g2005 -Wall -I "$ROOT/src/shared" -I "$ROOT/src/B_orders" -s tb_BC_ledger \
    -o "$OUT/tb_BC_ledger.vvp" \
    "$ROOT"/src/B_orders/*.v "$ROOT"/sim/stubs/stub_market.v "$ROOT"/sim/stubs/stub_font.v \
    "$C/ledger.v" "$C/seq_divider.v" "$ROOT/sim/integration/tb_BC_ledger.v" 2>&1 | grep -v "timescale" || true
(cd "$OUT" && vvp -n tb_BC_ledger.vvp) > "$OUT/tb_BC_ledger.log" 2>&1
grep -E "^(----|     |PASS|FAIL)" "$OUT/tb_BC_ledger.log"
grep -q "^PASS: tb_BC_ledger" "$OUT/tb_BC_ledger.log"
