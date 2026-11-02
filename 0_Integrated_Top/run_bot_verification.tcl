# Use an isolated project so the open GUI project cannot lock the test run.
set here [file dirname [file normalize [info script]]]
set repo [file normalize "$here/.."]
set proj_dir [file normalize "$repo/.b/bot_tests"]
source "$here/create_integration_project.tcl"
set summary_file "$repo/.b/bot_tests/test_summary.txt"
source "$here/run_all_tests.tcl"
set failed 0
foreach line $summary {
    if {![regexp {\sPASS\s} $line]} { set failed 1 }
}
close_project
if {$failed} { error "One or more tests failed or did not produce a verdict; see $summary_file" }
puts "ALL_INTEGRATED_TESTS_PASS: $summary_file"
