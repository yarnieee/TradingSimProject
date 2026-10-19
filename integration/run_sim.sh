#!/usr/bin/env bash
# Run tb_integration under Icarus Verilog (Mac/Linux). Takes a few minutes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
S="$REPO/TradingSimProject.srcs/sources_1"; O="$HERE/sim_out"
mkdir -p "$O" && ln -sfn "$S/imports/storage" "$O/storage"
iverilog -g2005 -I "$REPO/PartB/src/shared" -I "$REPO/PartB/src/B_orders" -s tb_integration -o "$O/tb.vvp" \
  "$HERE/Integration_Top.v" "$HERE/tb_integration.v" "$S"/imports/storage/*.v \
  "$REPO"/PartB/src/B_orders/*.v "$REPO/PartB/sim/stubs/stub_font.v" \
  "$S/new/ledger.v" "$S/new/seq_divider.v" "$S/new/game_fsm.v" "$S/new/OLED_Renderer.v" \
  "$S/new/text_layer.v" "$S/new/font_renderer.v" "$S/new/quantity_7seg.v" "$S/new/binary_to_bcd_14bit.v" \
  "$S/imports/verilog_code_snippets/input_btn/debouncer.v" \
  "$S/imports/verilog_code_snippets/clocks/slower_clk.v" \
  "$S/imports/verilog_code_snippets/output_oled/oled_display.v" || exit 1
(cd "$O" && vvp -n tb.vvp) > "$O/log.txt" 2>&1
grep -E "^(PASS|FAIL|WARN|     )" "$O/log.txt"
grep -q "^PASS" "$O/log.txt"
