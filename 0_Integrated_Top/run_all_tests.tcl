# run_all_tests.tcl
# Runs every testbench in the Integration project (create it first with
# create_integration_project.tcl, in 0_Integrated_Top) and prints one line per testbench.
#
# Usage, in the Vivado Tcl Console, with the Integration project open:
#   source C:/EE2026/TradingSimProject/0_Integrated_Top/run_all_tests.tcl
# To run only some:  set only_tbs {tb_integration tb_yian_market}  before sourcing.

set all_tbs {
    tb_integration
    tb_chart_renderer
    tb_display_numbers
    tb_yian_market
    tb_stock_price
    tb_normalise_lfsr
    tb_matthew_game_fsm
    tb_ledger
    tb_seq_divider
    tb_BC_ledger
    tb_order_validate
    tb_order_book
    tb_exec_engine
    tb_ticket_screen
    tb_B_order_top
}
if {[info exists only_tbs]} { set tbs $only_tbs } else { set tbs $all_tbs }

set proj [current_project]
set log  [file join [get_property DIRECTORY $proj] "$proj.sim" sim_1 behav xsim simulate.log]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

set summary {}
foreach tb $tbs {
    puts "\n=============== $tb ==============="
    catch {close_sim -force -quiet}
    file delete -force $log
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1
    if {[catch {launch_simulation -simset sim_1 -mode behavioral} err]} {
        lappend summary [format "%-18s ERROR  (did not compile or run: see the messages above)" $tb]
        continue
    }
    # read the testbench's own verdict from the simulator log
    set fails 0; set passes 0; set verdict ""
    if {[file exists $log]} {
        set fh [open $log]
        foreach line [split [read $fh] "\n"] {
            if {[regexp {^FAIL} $line] || [regexp {TEST\(S\) FAILED} $line]} { incr fails }
            if {[regexp {^PASS: } $line] || [regexp {ALL .*TESTS PASSED} $line]} { set verdict $line; incr passes }
        }
        close $fh
    }
    if {$fails > 0} {
        lappend summary [format "%-18s FAIL   (%d failing lines; see the log above)" $tb $fails]
    } elseif {$passes > 0} {
        lappend summary [format "%-18s PASS   %s" $tb $verdict]
    } else {
        lappend summary [format "%-18s ??     no verdict found in %s" $tb $log]
    }
    catch {close_sim -force -quiet}
}

puts "\n=============== SUMMARY ==============="
foreach line $summary { puts $line }
puts "(Module A price-model tests are expected to PASS after the signed arithmetic fix.)"
