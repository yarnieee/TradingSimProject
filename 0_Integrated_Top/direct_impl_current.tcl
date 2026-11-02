# Implement a synthesized Integration_Top checkpoint and write its bitstream.

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
set part xc7a35tcpg236-1
set synth_dcp [file normalize "$repo/.b/direct/Integration_Top_synth.dcp"]
set output_dir [file normalize "$repo/.b/direct"]
set bitstream_file [file join $output_dir Integration_Top.bit]

if {![file exists $synth_dcp]} {
    error "Synthesis checkpoint is missing: $synth_dcp"
}
file mkdir $output_dir

create_project -in_memory -part $part
read_checkpoint $synth_dcp
link_design -top Integration_Top -part $part
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

opt_design
place_design
route_design
write_checkpoint -force [file join $output_dir Integration_Top_routed.dcp]
report_timing_summary -file [file join $output_dir Integration_Top_timing_summary.rpt]
report_drc -file [file join $output_dir Integration_Top_drc.rpt]
write_bitstream -force $bitstream_file

if {![file exists $bitstream_file]} {
    error "Vivado completed write_bitstream without creating $bitstream_file"
}
report_utilization -file [file join $output_dir Integration_Top_utilization_impl.rpt]
puts "BITSTREAM_SUCCESS: $bitstream_file"
close_design
