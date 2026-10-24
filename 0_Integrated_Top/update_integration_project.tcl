# update_integration_project.tcl
# Add newly introduced display sources to an already-created Integration
# project. Run this from Vivado's Tcl console while Integration.xpr is open:
#
#   source C:/path/to/TradingSimProject/0_Integrated_Top/update_integration_project.tcl
#
# This script is intentionally non-destructive: it only adds files that are
# not already in sources_1 and refreshes Vivado's compile order.

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]

if {[llength [get_projects -quiet]] == 0} {
    set default_project [file normalize "$repo/../Integration_vivado/Integration.xpr"]
    if {![file exists $default_project]} {
        error "No Vivado project is open and could not find $default_project"
    }
    open_project $default_project
}

set project_name [get_property NAME [current_project]]
if {$project_name ne "Integration"} {
    puts "WARNING: current project is '$project_name'; expected 'Integration'."
}

set source_set [get_filesets sources_1]
set display_sources [glob -nocomplain -types f "$repo/5_Matthew_Display/submodules/*.v"]

foreach source_file $display_sources {
    set source_file [file normalize $source_file]
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -fileset $source_set -norecurse $source_file
        puts "Added source: $source_file"
    }
}

set_property top Integration_Top $source_set
update_compile_order -fileset $source_set
puts "Updated '$project_name': top=Integration_Top; display submodules are in sources_1."
