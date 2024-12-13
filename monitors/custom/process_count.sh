#!/bin/bash

# Name: Process Count
# User: dashboard
# Period: 5 minutes
# Threshold: 1
# Direction: Below

ROOTDIR=/opt/dashboard
ETCDIR=$ROOTDIR/etc
LOGDIR=$ROOTDIR/log

if [ -f "$ETCDIR/config.settings" ]; then
    source $ETCDIR/config.settings
fi

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <monitor_id> <process name>"
    exit 1
fi

MONITOR_ID=$1
PROCESS_NAME=$2
URL="https://dashboard.absoluteops.com/webhook-monitor/$MONITOR_ID"

if [ "$LOG_OUTPUT" == "true" ]; then
    LOG_FILE="$LOGDIR/monitor.log"
    exec > >(tee -a "$LOG_FILE" | sed "s/^/[$(basename $0)] /") 2>&1
    exec 2>&1
fi

# Check the number of processes running with $PROCESS_NAME
PROCESS_COUNT=$(ps -ef | grep -w $PROCESS_NAME | grep -v grep | wc -l)

# Send the process count to the monitor
echo curl --silent --request POST --url "$URL?value=$PROCESS_COUNT"
if [ $? != 0 ]; then
    echo "Failed to send process count."
fi

