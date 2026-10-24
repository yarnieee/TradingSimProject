# Recreate the integration project from the repository and run Module A tests.
# This is a short, reproducible wrapper around the shared test runner.

set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
set proj_dir [file normalize "$repo/../Integration_vivado"]

source [file join $here create_integration_project.tcl]

set only_tbs {tb_stock_price tb_yian_market}
source [file join $here run_all_tests.tcl]

close_project
