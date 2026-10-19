# create_integration_project.tcl
# Builds a Vivado project for Integration_Top (everyone's part) from the files
# in this branch (branch-team-integration), used in place. The project is created NEXT TO the repo
# folder, so TradingSimProject.xpr is never touched.
#
# Usage, in the Vivado Tcl Console (forward slashes, even on Windows):
#   source C:/EE2026/TradingSimProject/integration/create_integration_project.tcl
# Option (set before sourcing):  set proj_dir C:/somewhere/else

set here  [file dirname [file normalize [info script]]]
set repo  [file normalize "$here/.."]
set srcs  "$repo/TradingSimProject.srcs/sources_1"
if {![info exists proj_dir]} { set proj_dir [file normalize "$repo/../Integration_vivado"] }
puts "Repo   : $repo"
puts "Project: $proj_dir"

create_project Integration $proj_dir -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

proc add_list {fileset files} {
    foreach f $files {
        if {![file exists $f]} { error "missing file: $f" }
    }
    add_files -fileset $fileset -norecurse $files
}

# ---------------------------------------------------------------- Yi An: market engine
set a "$srcs/imports/storage"
add_list sources_1 [list \
    "$a/A_top.v" "$a/day_ticker.v" "$a/get_30_values.v" "$a/lfsr.v" "$a/market_state.v" \
    "$a/normalise_lfsr.v" "$a/startup_seed.v" "$a/stock.v" "$a/storage_buffer.v" \
    "$a/AMD_seed.mem" "$a/MCD_seed.mem"]

# ---------------------------------------------------------------- Douglas: orders
set n "$srcs/new"
add_list sources_1 [list \
    "$n/B_order_top.v" "$n/order_entry.v" "$n/order_validate.v" "$n/exec_engine.v" \
    "$n/order_book.v" "$n/spread_calc.v" "$n/ticket_screen.v" "$n/b_bin2bcd_seq.v" \
    "$n/stub_font.v" "$n/trading_defs.vh" "$n/ticket_layout.vh"]
set_property include_dirs [list "$n"] [get_filesets sources_1]

# ---------------------------------------------------------------- Tricia: ledger
add_list sources_1 [list "$srcs/new/ledger.v" "$srcs/new/seq_divider.v"]

# ---------------------------------------------------------------- Matthew: game, display
# Only Matthew's copies of slower_clk and oled_display: the older imports/new copies
# define the same modules and would clash.
set d "$srcs/imports/verilog_code_snippets"
add_list sources_1 [list \
    "$srcs/new/game_fsm.v" "$srcs/new/OLED_Renderer.v" "$srcs/new/text_layer.v" \
    "$srcs/new/font_renderer.v" "$srcs/new/quantity_7seg.v" "$srcs/new/binary_to_bcd_14bit.v" \
    "$d/input_btn/debouncer.v" "$d/clocks/slower_clk.v" "$d/output_oled/oled_display.v"]

# ---------------------------------------------------------------- top + constraints
add_list sources_1 [list "$here/Integration_Top.v"]
set_property top Integration_Top [get_filesets sources_1]
add_list constrs_1 [list "$here/Integration.xdc"]

# ---------------------------------------------------------------- simulation
set t "$repo/TradingSimProject.srcs/sim_1/new"
# Every testbench in the branch, plus Douglas's test stand-ins (stub market, stub ledger). Pick one
# with right-click > Set as Top under Simulation Sources, or run them all with
#   source <repo>/integration/run_all_tests.tcl
add_list sim_1 [list \
    "$here/tb_integration.v" \
    "$here/tests/tb_yian_market.v" \
    "$here/tests/tb_matthew_game_fsm.v" \
    "$t/tb_ledger.v" \
    "$srcs/new/tb_seq_divider.v" \
    "$t/tb_BC_ledger.v" "$t/stub_market.v" "$t/stub_ledger.v" \
    "$t/tb_order_validate.v" "$t/tb_order_book.v" "$t/tb_exec_engine.v" \
    "$t/tb_ticket_screen.v" "$t/tb_B_order_top.v"]
# (Yi An's .mem files are in sources_1, which sim_1 inherits; the simulator copies them to its run folder.)
set_property include_dirs [list "$n"] [get_filesets sim_1]
set_property top tb_integration [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Done. Next:"
puts "  Tests: source $here/run_all_tests.tcl   (runs every testbench, prints a summary)"
puts "  Generate Bitstream, check the timing summary (WNS > 0), then program the board"
