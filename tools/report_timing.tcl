# Post-fit timing evidence only. Never changes SDC constraints or exceptions.
# quartus_sta -t tools/report_timing.tcl --help-api does not open a project.
load_package sta

if {$quartus(args) eq "--help-api"} {
    foreach command {
        project_open project_close create_timing_netlist read_sdc
        get_available_operating_conditions get_operating_conditions_info
        set_operating_conditions update_timing_netlist
        report_timing report_min_pulse_width report_clock_transfers
        report_ucp check_timing report_sdc report_clocks
        get_timing_paths get_path_info
    } {
        puts "API_BEGIN $command"
        if {[catch {$command -long_help} detail]} {puts "HELP_ERROR $detail"} else {puts $detail}
        puts "API_END $command"
    }
    return
}

# Use only completed, quiescent build snapshots. A successful report run means
# evidence was generated, not that timing or constraint coverage passed review.
proc hq_write {path contents} {
    set channel [open $path w]
    puts $channel $contents
    close $channel
}

proc hq_cell {value} {
    return [string map [list "\t" " " "\n" " " "\r" " "] $value]
}

proc hq_report {directory name command} {
    global hq_failures hq_commands
    puts $hq_commands [list $name $command]
    flush $hq_commands
    if {[catch {uplevel #0 $command} result]} {
        incr hq_failures
        hq_write [file join $directory "$name.error.txt"] $result
        puts "REPORT_ERROR $name: $result"
        return [list 0 $result]
    }
    return [list 1 $result]
}

proc hq_main {arguments} {
    global quartus hq_failures hq_commands hq_summary hq_open hq_netlist
    if {[llength $arguments] < 3 || [llength $arguments] > 5} {
        error "Usage: quartus_sta -t report_timing.tcl <project.qpf> <revision> <new-output-directory> ?npaths=20? ?mode=full|clock-paths|reset-chain?"
    }
    set project_path [file normalize [lindex $arguments 0]]
    if {[file extension $project_path] ne ".qpf"} {append project_path ".qpf"}
    set revision [lindex $arguments 1]
    set output [file normalize [lindex $arguments 2]]
    set npaths 20
    if {[llength $arguments] >= 4} {set npaths [lindex $arguments 3]}
    set mode full
    if {[llength $arguments] == 5} {set mode [lindex $arguments 4]}
    if {$mode ne "full" && $mode ne "clock-paths" && $mode ne "reset-chain"} {error "mode must be full, clock-paths or reset-chain"}
    if {![string is integer -strict $npaths] || $npaths < 1} {error "npaths must be a positive integer"}
    if {![file isfile $project_path]} {error "Project not found: $project_path"}
    if {[file exists $output]} {error "Use a new output directory to preserve previous evidence: $output"}

    set project_directory [file dirname $project_path]
    set project [file rootname [file tail $project_path]]
    # This repository's project files use output_files. Never fall back to a
    # synthesis netlist if the fitter failed or has not completed.
    set fit_summary [file join $project_directory output_files "$revision.fit.summary"]
    if {![file isfile $fit_summary]} {error "Completed fitter summary not found: $fit_summary"}
    set input [open $fit_summary r]
    set fit_text [read $input]
    close $input
    if {![regexp {Fitter Status[^\r\n]*Successful} $fit_text]} {
        error "Fitter summary does not report success: $fit_summary"
    }

    file mkdir $output
    set hq_commands [open [file join $output commands.log] w]
    set hq_summary [open [file join $output timing-summary.tsv] w]
    puts $hq_summary "corner\tdisplay_name\tanalysis\treported_paths\tworst_slack\treported_path_TNS\tstatus"
    set metadata [open [file join $output run.txt] w]
    puts $metadata "REPORT GENERATION ONLY; REVIEW TIMING AND CONSTRAINT COVERAGE BEFORE SIGN-OFF."
    puts $metadata "UTC: [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]"
    puts $metadata "Quartus: $quartus(version)"
    puts $metadata "Project: $project_path"
    puts $metadata "Revision: $revision"
    puts $metadata "Fit summary: $fit_summary"
    puts $metadata "npaths=$npaths, nworst=1; report_timing returns path count and worst slack, not TNS."
    puts $metadata "Mode: $mode. Focused modes supplement the full review; reset-chain requires one retained meta and sync register."
    puts $metadata "SDC: read_sdc with original project assignment order; no added/removed constraints."
    puts $metadata "Corner source: get_available_operating_conditions -all, without speed/grade overrides."
    close $metadata
    hq_write [file join $output fitter-summary.txt] $fit_text

    cd $project_directory
    project_open -revision $revision $project
    set hq_open 1
    create_timing_netlist
    set hq_netlist 1
    read_sdc
    update_timing_netlist
    set conditions [get_available_operating_conditions -all]
    set corner_channel [open [file join $output corners.tsv] w]
    puts $corner_channel "corner\tdisplay_name\tmodel\ttemperature_C\tvoltage_mV\tgrade\tspeed"
    set index 0
    foreach_in_collection corner $conditions {
        incr index
        set id [format "corner-%02d" $index]
        set name [get_operating_conditions_info -display_name $corner]
        set values [list $id [hq_cell $name]]
        foreach property {model temperature voltage grade speed} {
            lappend values [hq_cell [get_operating_conditions_info -$property $corner]]
        }
        puts $corner_channel [join $values "\t"]
        flush $corner_channel
        set directory [file join $output $id]
        file mkdir $directory
        if {[catch {set_operating_conditions $corner; update_timing_netlist} detail]} {
            incr hq_failures
            hq_write [file join $directory corner.error.txt] $detail
            puts "REPORT_ERROR $id: $detail"
            continue
        }
        set analyses {setup hold recovery removal}
        if {$mode eq "clock-paths"} {set analyses {video-setup video-hold hdmi-setup hdmi-hold}}
        if {$mode eq "reset-chain"} {set analyses {reset-setup reset-hold}}
        foreach analysis $analyses {
            set report [file join $directory "$analysis.rpt"]
            if {$mode eq "reset-chain"} {
                set kind [lindex [split $analysis -] 1]
                set meta [get_registers {*hq2x_reset_meta*}]
                set sync [get_registers {*hq2x_reset_sync*}]
                foreach role {meta sync} {
                    set count 0
                    foreach_in_collection node [set $role] {incr count}
                    if {$count != 1} {error "Expected exactly one retained reset $role register; found $count"}
                }
                set command [list report_timing -$kind -from $meta -to $sync -npaths 1 -nworst 1 -detail full_path -file $report]
            } elseif {$mode eq "clock-paths"} {
                set kind [lindex [split $analysis -] 1]
                set pattern {emu|pll2|*divclk}
                if {[string match hdmi-* $analysis]} {set pattern {pll_hdmi|*divclk}}
                set selected [get_clocks $pattern]
                set count 0
                foreach_in_collection clock $selected {incr count}
                if {$count != 1} {error "Expected exactly one clock for $pattern; found $count"}
                set command [list report_timing -$kind -from_clock $selected -to_clock $selected -npaths $npaths -nworst 1 -detail full_path -file $report]
            } else {
                set command [list report_timing -$analysis -npaths $npaths -nworst 1 -detail full_path -file $report]
            }
            set response [hq_report $directory $analysis $command]
            set status report_error
            set paths NA
            set slack NA
            set tns NA
            if {[lindex $response 0]} {
                set result [lindex $response 1]
                if {[llength $result] >= 2 && [string is integer -strict [lindex $result 0]]} {
                    set paths [lindex $result 0]
                    set status no_paths
                    if {$paths > 0} {
                        set slack [lindex $result 1]
                        set status review_report
                        if {[string is double -strict $slack]} {
                            if {$slack < 0} {set status negative_slack} else {set status nonnegative_slack}
                        }
                    }
                } else {
                    incr hq_failures
                    set status unexpected_return_value
                    hq_write [file join $directory "$analysis.return.txt"] $result
                }
            }
            if {$mode eq "reset-chain" && $paths ne "1"} {
                incr hq_failures
                set status reset_chain_path_missing
                hq_write [file join $directory "$analysis.chain.error.txt"] "Expected one real meta-to-sync path; reported_paths=$paths. Matched register names alone do not prove the chain."
            }
            puts $hq_summary [join [list $id [hq_cell $name] $analysis $paths $slack $tns $status] "\t"]
            flush $hq_summary
            if {$mode eq "full"} {
                hq_report $directory "clock-transfers-$analysis" [list report_clock_transfers -$analysis -file [file join $directory "clock-transfers-$analysis.rpt"]]
            }
        }
        if {$mode ne "full"} {
            hq_report $directory clocks [list report_clocks -file [file join $directory clocks.rpt]]
            puts "CORNER_REPORTED $id $name"
            continue
        }
        hq_report $directory min-pulse-width [list report_min_pulse_width -nworst $npaths -detail full_path -file [file join $directory min-pulse-width.rpt]]
        hq_report $directory clocks [list report_clocks -file [file join $directory clocks.rpt]]
        hq_report $directory unconstrained [list report_ucp -file [file join $directory unconstrained.rpt]]
        hq_report $directory sdc [list report_sdc -file [file join $directory sdc.rpt]]
        hq_report $directory sdc-ignored [list report_sdc -ignored -file [file join $directory sdc-ignored.rpt]]
        set checks {no_clock multiple_clock generated_clock loops latches no_input_delay no_output_delay partial_input_delay partial_output_delay uncertainty partial_multicycle multicycle_consistency}
        hq_report $directory check-timing [list check_timing -include $checks -file [file join $directory check-timing.rpt]]
        puts "CORNER_REPORTED $id $name"
    }
    close $corner_channel
    if {$index == 0} {error "No available operating conditions returned"}
    delete_timing_netlist
    set hq_netlist 0
    project_close -dont_export_assignments
    set hq_open 0
    puts $hq_commands "REPORT_COMMAND_FAILURES $hq_failures"
    close $hq_commands
    set hq_commands ""
    close $hq_summary
    set hq_summary ""
    if {$hq_failures > 0} {error "$hq_failures reporting operations failed; inspect .error.txt files and log"}
    hq_write [file join $output REPORTS_GENERATED.txt] "Generated $index corner reports in $mode mode. This marker does not assert timing closure. Review negative slack, pulse width, ignored constraints and unconstrained paths; clock-paths mode alone does not collect all required checks."
    puts "REPORTS_GENERATED_REVIEW_REQUIRED $output"
}

set hq_failures 0
set hq_open 0
set hq_netlist 0
set hq_commands ""
set hq_summary ""
if {[catch {hq_main $quartus(args)} hq_error]} {
    if {$hq_netlist} {catch {delete_timing_netlist}}
    if {$hq_open} {catch {project_close -dont_export_assignments}}
    if {$hq_commands ne ""} {catch {close $hq_commands}}
    if {$hq_summary ne ""} {catch {close $hq_summary}}
    error $hq_error
}
