#!/usr/bin/env bash
# Mac/Linux equivalent of run_all_tests.tcl, using Icarus Verilog.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
S="$REPO/TradingSimProject.srcs/sources_1"; B="$REPO/PartB"; O="$HERE/sim_out"
mkdir -p "$O"; ln -sfn "$S/imports/storage/AMD_seed.mem" "$O/AMD_seed.mem"; ln -sfn "$S/imports/storage/MCD_seed.mem" "$O/MCD_seed.mem"
INC=(-I "$B/src/shared" -I "$B/src/B_orders")
A_SRC=("$S"/imports/storage/*.v)
B_SRC=("$B"/src/B_orders/*.v "$B/sim/stubs/stub_font.v")
C_SRC=("$S/new/ledger.v" "$S/new/seq_divider.v")
D_SRC=("$S/new/game_fsm.v" "$S/new/OLED_Renderer.v" "$S/new/text_layer.v" "$S/new/font_renderer.v"
       "$S/new/quantity_7seg.v" "$S/new/binary_to_bcd_14bit.v"
       "$S/imports/verilog_code_snippets/input_btn/debouncer.v"
       "$S/imports/verilog_code_snippets/clocks/slower_clk.v"
       "$S/imports/verilog_code_snippets/output_oled/oled_display.v")
STUBS=("$B/sim/stubs/stub_market.v" "$B/sim/stubs/stub_ledger.v")
run() {   # name, files...
    local tb=$1; shift
    if ! iverilog -g2005 "${INC[@]}" -s "$tb" -o "$O/$tb.vvp" "$@" 2> "$O/$tb.compile.txt"; then
        printf "%-18s ERROR  (compile, see sim_out/%s.compile.txt)\n" "$tb" "$tb"; return; fi
    (cd "$O" && vvp -n "$tb.vvp") > "$O/$tb.log" 2>&1
    if grep -qE "^FAIL|TEST\(S\) FAILED" "$O/$tb.log"; then printf "%-18s FAIL   %s\n" "$tb" "$(grep -E '^FAIL: tb' "$O/$tb.log" | tail -1)"
    elif grep -qE "^PASS: |ALL .*TESTS PASSED" "$O/$tb.log"; then printf "%-18s PASS   %s\n" "$tb" "$(grep -E '^PASS: |ALL .*TESTS PASSED' "$O/$tb.log" | tail -1)"
    else printf "%-18s ??     no verdict (sim_out/%s.log)\n" "$tb" "$tb"; fi
}
run tb_integration    "$HERE/tb_integration.v" "$HERE/Integration_Top.v" "${A_SRC[@]}" "${B_SRC[@]}" "${C_SRC[@]}" "${D_SRC[@]}"
run tb_A_market       "$HERE/tests/tb_A_market.v" "${A_SRC[@]}"
run tb_D_game_fsm     "$HERE/tests/tb_D_game_fsm.v" "$S/new/game_fsm.v"
run tb_ledger         "$REPO/TradingSimProject.srcs/sim_1/new/tb_ledger.v" "${C_SRC[@]}"
run tb_seq_divider    "$S/new/tb_seq_divider.v" "$S/new/seq_divider.v"
run tb_BC_ledger      "$B/sim/integration/tb_BC_ledger.v" "${B_SRC[@]}" "${C_SRC[@]}" "${STUBS[@]}"
for t in tb_order_validate tb_order_book tb_exec_engine tb_ticket_screen tb_B_order_top; do
    run $t "$B/sim/B_orders/$t.v" "${B_SRC[@]}" "${STUBS[@]}"
done
echo "(tb_A_market is expected to FAIL until A's stock.v price fix: see integration/README.md)"
