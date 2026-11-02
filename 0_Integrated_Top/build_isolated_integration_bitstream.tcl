# build_isolated_integration_bitstream.tcl
#
# Build the integration design in a separate Vivado project.  This keeps the
# bitstream build independent of the GUI-owned Integration.xpr file, which can
# otherwise be opened read-only while Vivado is already running.

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
set build_root [file normalize "$repo/.b"]
set project_dir $build_root

file mkdir $build_root
create_project -force I $project_dir -part xc7a35tcpg236-1

# Same file set as create_integration_project.tcl: each person's top
# module(s), everything in their submodules/ folder, and the .mem data.
set source_files [list "$repo/0_Integrated_Top/Integration_Top.v"]
foreach pattern [list \
    "$repo/1_Shared_Modules/*" \
    "$repo/2_YiAn_Market_Engine/*.v" "$repo/2_YiAn_Market_Engine/submodules/*" \
    "$repo/3_Douglas_Orders/*.v"     "$repo/3_Douglas_Orders/submodules/*" \
    "$repo/4_Tricia_Ledger/*.v"      "$repo/4_Tricia_Ledger/submodules/*" \
    "$repo/5_Matthew_Display/*.v"    "$repo/5_Matthew_Display/submodules/*" \
    "$repo/5_Matthew_Display/title_art_*.mem"] {
    set source_files [concat $source_files [glob $pattern]]
}

foreach source_file $source_files {
    if {![file exists $source_file]} {
        error "Required source file is missing: $source_file"
    }
    add_files -fileset [get_filesets sources_1] -norecurse [file normalize $source_file]
}

foreach seed_file [glob "$repo/2_YiAn_Market_Engine/data/*.mem"] {
    add_files -fileset [get_filesets sources_1] -norecurse [file normalize $seed_file]
}

set xdc_file [file normalize "$repo/0_Integrated_Top/Integration.xdc"]
if {![file exists $xdc_file]} {
    error "Required constraints file is missing: $xdc_file"
}
add_files -fileset [get_filesets constrs_1] -norecurse $xdc_file

set source_set [get_filesets sources_1]
set_property top Integration_Top $source_set
update_compile_order -fileset $source_set
update_compile_order -fileset [get_filesets constrs_1]

set synth_run [get_runs synth_1]
launch_runs $synth_run -jobs 4
wait_on_run $synth_run
set synth_status [get_property STATUS $synth_run]
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis is not complete: $synth_status"
}

set impl_run [get_runs impl_1]
# The market date-calculation cone makes optional physical optimization take
# an excessive amount of time.  It is not required to write a bitstream.
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED false $impl_run
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
