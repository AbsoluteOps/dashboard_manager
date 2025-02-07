#!/bin/bash

# Description: Use to log other functions results.
# Expectation: LOGDIR and LOGFILE variables are defined.
#
# Structure: log "<message>" <optional:log_level> <optional:quiet_bool> <optional:log_type>
#   "<message>"   Message enclosed in double quotes to act as initial value.
#   <log_level>   Whatever log level. Current expecting: info (default), warn, error, other.
#   <quiet_bool>  Bool for quiet (true/false). Used to remove output to user when true, but still sends to log.
#   <log_type>    General is defaulted/assumed. When define, must add other optionals. Allowed types:
#                 - GENERAL     Sends to LOGFILE
#                 - MONITOR     Sends to LOGFILE_MONITOR
#                 - CONTROLLER  Sends to LOGFILE_CONTROLLER
#                 - ALL         Sends to all configured log files in log()
#                 - <Other>     More can be added as long as LOGFILE_<TYPE> is set
#
# Usage Examples:
#   log "My info message to user and log file"
#   log "My info message to user and log file" info
#   log "My info message to log file only" info true
#   log "My info message to controller log file only" info true controller
#   log "My error message to user and log file" error
#   log "My error message to log file only" error true
#   log "My warn message to monitor log file and user" warn false monitor
#   log "Some info message for all logs" info false all
#

log() {
    # Provided internal vars
    local log_msg="$1"
    local log_level="${2:-info}"
    local quiet="${3:-false}"
    local log_type="${4:-general}"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")


    # Capitalize log level and format it to fit within 8-character brackets
    local log_level_formatted
    log_level_formatted=$(printf "[%-5s]" "${log_level^^}")

    # Define the log entry format
    local log_entry="[$timestamp] $log_level_formatted $log_msg"

    # Log to file
    case "${log_type,,}" in
        "general")
            echo "$log_entry" >> "$LOGFILE"
            ;;
        "monitor")
            echo "$log_entry" >> "$LOGFILE_MONITOR"
            ;;
        "controller")
            echo "$log_entry" >> "$LOGFILE_CONTROLLER"
            ;;
        "all")
            echo "$log_entry" >> "$LOGFILE"
            echo "$log_entry" >> "$LOGFILE_MONITOR"
            echo "$log_entry" >> "$LOGFILE_CONTROLLER"
            ;;
        *)
            echo "INVALID LOG_TYPE for Log function used" >> "$LOGFILE"
            exit 1
            ;;
    esac

    # Display to user unless "quiet" is set to true
    if [[ "$quiet" != true ]]; then
        echo "  $log_msg"
    fi
}
