# write_bitstream_from_synth_checkpoint.tcl
# Generate a bitstream directly from the most recent successful synthesis DCP.
# This avoids modifying or reopening the GUI-owned Integration.xpr project.

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
set synth_dcp [file normalize "$repo/../Integration_vivado/Integration.runs/synth_1/Integration_Top.dcp"]
set xdc_file [file normalize "$repo/0_Integrated_Top/Integration.xdc"]
set output_dir [file normalize "$repo/.b/checkpoint_impl"]
set bitstream_file [file join $output_dir Integration_Top.bit]

if {![file exists $synth_dcp]} {
    error "Synthesis checkpoint is missing: $synth_dcp"
}
if {![file exists $xdc_file]} {
    error "Constraints file is missing: $xdc_file"
}
file mkdir $output_dir

# Avoid the broken persistent Tcl-app store initialization on this machine;
# no user Tcl apps are needed for implementation or bitstream generation.
catch {::tclapp::use_local -quiet}
catch {::tclapp::load_apps -quiet}
create_project -in_memory -part xc7a35tcpg236-1
add_files -quiet $synth_dcp
read_xdc $xdc_file
link_design -top Integration_Top -part xc7a35tcpg236-1
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

opt_design
place_design
route_design
write_bitstream -force $bitstream_file

if {![file exists $bitstream_file]} {
    error "Vivado completed write_bitstream without creating $bitstream_file"
}
puts "BITSTREAM_SUCCESS: $bitstream_file"
close_design
