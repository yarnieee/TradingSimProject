# generate_integration_bitstream.tcl
# Update the active Integration project and run implementation through
# bitstream generation. This does not recreate the project or delete sources.

set here [file dirname [file normalize [info script]]]
source [file join $here update_integration_project.tcl]

set synth_run [get_runs synth_1]
set synth_status [get_property STATUS $synth_run]
if {![string match "*Complete*" $synth_status]} {
    reset_run $synth_run
    launch_runs $synth_run -jobs 4
    wait_on_run $synth_run
    set synth_status [get_property STATUS $synth_run]
}
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis is not complete: $synth_status"
}

set impl_run [get_runs impl_1]
# The current design has an extremely long physical-optimization pass because
# the market module contains a very large date-calculation cone.  Physical
# optimization is optional for bitstream generation, so skip that pass and
# allow placement, routing, and bitstream writing to complete.
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED false $impl_run
reset_run $impl_run
launch_runs $impl_run -to_step write_bitstream -jobs 4
wait_on_run $impl_run

set impl_status [get_property STATUS $impl_run]
puts "impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation/bitstream generation did not complete successfully: $impl_status"
}

set bitstream_file [file join [get_property DIRECTORY $impl_run] Integration_Top.bit]
if {![file exists $bitstream_file]} {
    error "Vivado reported completion but bitstream was not found at $bitstream_file"
}
puts "BITSTREAM_SUCCESS: $bitstream_file"
close_project
