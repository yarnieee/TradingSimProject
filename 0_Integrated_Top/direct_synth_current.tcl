# Synthesize the current Integration_Top sources without Vivado run metadata.
# This is used when the project launcher is blocked by a GUI-owned .xpr or by
# stale Tcl-app state.  It intentionally reads the checked-out source files
# directly and emits a checkpoint for the separate implementation script.

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
set part xc7a35tcpg236-1
if {![info exists output_dir]} { set output_dir [file normalize "$repo/.b/direct"] }
set synth_dcp [file join $output_dir Integration_Top_synth.dcp]

file mkdir $output_dir

create_project -in_memory -part $part

set source_files [list [file normalize "$repo/0_Integrated_Top/Integration_Top.v"]]
foreach pattern [list \
    "$repo/1_Shared_Modules/*" \
    "$repo/2_YiAn_Market_Engine/*.v" "$repo/2_YiAn_Market_Engine/submodules/*" \
    "$repo/3_Douglas_Orders/*.v"     "$repo/3_Douglas_Orders/submodules/*" \
    "$repo/4_Tricia_Ledger/*.v"      "$repo/4_Tricia_Ledger/submodules/*" \
    "$repo/5_Matthew_Display/*.v"    "$repo/5_Matthew_Display/submodules/*" \
    "$repo/5_Matthew_Display/title_art_*.mem"] {
    set source_files [concat $source_files [glob -nocomplain $pattern]]
}

foreach seed_file [glob -nocomplain "$repo/2_YiAn_Market_Engine/data/*.mem"] {
    lappend source_files $seed_file
}

foreach source_file $source_files {
    if {[file extension $source_file] in {.v .vh .mem}} {
        add_files -quiet -norecurse [file normalize $source_file]
    }
}

set include_dirs [list \
    [file normalize "$repo/0_Integrated_Top"] \
    [file normalize "$repo/1_Shared_Modules"] \
    [file normalize "$repo/2_YiAn_Market_Engine"] \
    [file normalize "$repo/2_YiAn_Market_Engine/submodules"] \
    [file normalize "$repo/3_Douglas_Orders"] \
    [file normalize "$repo/3_Douglas_Orders/submodules"] \
    [file normalize "$repo/4_Tricia_Ledger"] \
    [file normalize "$repo/4_Tricia_Ledger/submodules"] \
    [file normalize "$repo/5_Matthew_Display"] \
    [file normalize "$repo/5_Matthew_Display/submodules"]]

read_xdc [file normalize "$repo/0_Integrated_Top/Integration.xdc"]
# Use the standard synthesis flow with the real bot explicitly enabled.
# No area directive is needed to meet the LUT budget.
synth_design -top Integration_Top -part $part -include_dirs $include_dirs \
    -flatten_hierarchy rebuilt -directive Default -generic ENABLE_BOT=1
write_checkpoint -force $synth_dcp
report_utilization -file [file join $output_dir Integration_Top_utilization_synth.rpt]
report_utilization -hierarchical -file [file join $output_dir Integration_Top_utilization_hier_synth.rpt]
puts "SYNTHESIS_SUCCESS: $synth_dcp"
close_design
