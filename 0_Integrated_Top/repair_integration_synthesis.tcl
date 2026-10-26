# repair_integration_synthesis.tcl
# Batch helper: update the existing Integration project and rerun synthesis.
# The project is not recreated and no source files are deleted.

set here [file dirname [file normalize [info script]]]
source [file join $here update_integration_project.tcl]

set synth_run [get_runs synth_1]
reset_run $synth_run
launch_runs $synth_run -jobs 4
wait_on_run $synth_run

set run_status [get_property STATUS $synth_run]
puts "synth_1 status: $run_status"
if {![string match "*Complete*" $run_status]} {
    error "Synthesis did not complete successfully: $run_status"
}

close_project
