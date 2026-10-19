# create_B_demo_project.tcl
# Builds a Vivado project for the Part B board test (B_demo_top), using the
# files in this repo in place (nothing is copied, so a git pull updates it).
# The project is created NEXT TO the repo folder, so the team's
# TradingSimProject.xpr is never touched.
#
# Usage, in the Vivado Tcl Console (use forward slashes, even on Windows):
#   source C:/EE2026/TradingSimProject/PartB/board/create_B_demo_project.tcl
#
# Options (set before sourcing):
#   set USE_PART_C 1        use Tricia's real ledger.v / seq_divider.v instead of the stub
#                           (they must be in TradingSimProject.srcs/sources_1/new/)
#   set proj_dir C:/somewhere/else   where to create the project

set here  [file dirname [file normalize [info script]]]
set partb [file normalize "$here/.."]
set repo  [file normalize "$partb/.."]
set team  "$repo/TradingSimProject.srcs/sources_1/imports/new"
if {![info exists proj_dir]}   { set proj_dir [file normalize "$repo/../B_demo_vivado"] }
if {![info exists USE_PART_C]} { set USE_PART_C 0 }

puts "Part B folder : $partb"
puts "Project folder: $proj_dir"

create_project B_demo $proj_dir -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

# ---------------------------------------------------------------- design sources
set incdirs [list "$partb/src/shared" "$partb/src/B_orders"]
add_files -norecurse [glob "$partb/src/shared/*.vh" "$partb/src/B_orders/*.vh" "$partb/src/B_orders/*.v"]
add_files -norecurse [list \
    "$partb/sim/stubs/stub_font.v" \
    "$partb/sim/stubs/stub_market.v" \
    "$partb/sim/stubs/stub_ledger.v" \
    "$partb/board/B_demo_top.v" \
    "$partb/board/b_demo_btn.v" \
    "$team/Oled_Display.v" \
    "$team/slower_clk.v"]
set_property include_dirs $incdirs [get_filesets sources_1]

if {$USE_PART_C} {
    set cdir "$repo/TradingSimProject.srcs/sources_1/new"
    foreach f {ledger.v seq_divider.v} {
        if {![file exists "$cdir/$f"]} {
            error "USE_PART_C is set but $cdir/$f is missing. Get Tricia's files first (see PartB/README.md)."
        }
        add_files -norecurse "$cdir/$f"
    }
    set_property verilog_define {USE_PART_C} [get_filesets sources_1]
    puts "Ledger: Part C (Tricia's ledger.v)"
} else {
    puts "Ledger: stub_ledger"
}

set_property top B_demo_top [get_filesets sources_1]

# ---------------------------------------------------------------- constraints
add_files -fileset constrs_1 -norecurse "$partb/board/B_demo.xdc"

# ---------------------------------------------------------------- simulation
add_files -fileset sim_1 -norecurse [glob "$partb/sim/B_orders/*.v"]
set_property include_dirs $incdirs [get_filesets sim_1]
set_property top tb_B_order_top [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {300us} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Done. Next:"
puts "  Run Simulation > Run Behavioral Simulation   (look for 'PASS: tb_B_order_top' in this console)"
puts "  Generate Bitstream, then Open Hardware Manager > Program Device"
