set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
# This is a one-time pre-optimization capture. Never overwrite the original
# measurements with a checkpoint or source tree from the optimized design.
if {[file exists "$repo/.b/bot_baseline/Integration_Top_utilization_synth.rpt"]} {
    error "Original bot baseline already captured in .b/bot_baseline; refusing to overwrite it"
}
# Recover the exact disabled hierarchy from the last verified checkpoint.
open_checkpoint "$repo/.b/direct/Integration_Top_synth.dcp"
report_utilization -hierarchical -file "$repo/.b/direct/Integration_Top_utilization_hier_disabled.rpt"
close_project
set output_dir [file normalize "$repo/.b/bot_baseline"]
source "$here/direct_synth_current.tcl"
