# create_integration_project.tcl
# Builds the team Vivado project (top: Integration_Top) from the files in this
# repo, used in place. The project is created NEXT TO the repo folder.
#
# Usage, in the Vivado Tcl Console (forward slashes, even on Windows):
#   source C:/EE2026/TradingSimProject/0_Integrated_Top/create_integration_project.tcl
# Option (set before sourcing):  set proj_dir C:/somewhere/else

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
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
# a person's folder: the top module(s) at its root, plus everything in submodules/
proc add_person {dir} {
    add_list sources_1 [glob "$dir/*.v"]
    if {[file isdirectory "$dir/submodules"]} {
        add_list sources_1 [glob "$dir/submodules/*"]
    }
}

# ---------------------------------------------------------------- design
add_list sources_1 [list "$here/Integration_Top.v"]
add_list sources_1 [glob "$repo/1_Shared_Modules/*"]
add_person "$repo/2_YiAn_Market_Engine"
add_list sources_1 [glob "$repo/2_YiAn_Market_Engine/data/*.mem"]
add_person "$repo/3_Douglas_Orders"
add_person "$repo/4_Tricia_Ledger"
add_person "$repo/5_Matthew_Display"
add_list sources_1 [glob "$repo/5_Matthew_Display/title_art_*.mem"]

set incdirs [list "$repo/1_Shared_Modules" "$repo/3_Douglas_Orders/submodules"]
set_property include_dirs $incdirs [get_filesets sources_1]
set_property top Integration_Top [get_filesets sources_1]

add_list constrs_1 [list "$here/Integration.xdc"]

# ---------------------------------------------------------------- testbenches
# Every tb/ folder. Pick one with right-click > Set as Top under Simulation
# Sources, or run them all with   source <repo>/0_Integrated_Top/run_all_tests.tcl
add_list sim_1 [list "$here/tb_integration.v"]
foreach person {2_YiAn_Market_Engine 3_Douglas_Orders 4_Tricia_Ledger 5_Matthew_Display} {
    add_list sim_1 [glob "$repo/$person/tb/*.v"]
}
set_property include_dirs $incdirs [get_filesets sim_1]
set_property top tb_integration [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Done. Next:"
puts "  Tests: source $here/run_all_tests.tcl   (runs every testbench, prints a summary)"
puts "  Generate Bitstream, check utilisation and timing (WNS > 0), then program the board"
