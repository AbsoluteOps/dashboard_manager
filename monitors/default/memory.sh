#!/bin/bash

# Name: Memory Usage
# User: dashboard
# Period: 5 minutes
# Threshold: 80%
# Direction: Above

ROOTDIR=/opt/dashboard
ETCDIR=$ROOTDIR/etc
LOGDIR=$ROOTDIR/log

if [ -f "$ETCDIR/config.settings" ]; then
    source $ETCDIR/config.settings
fi

if [ -z "$1" ]; then
    echo "Usage: $0 <monitor_id>"
    exit 1
fi

MONITOR_ID=$1
URL="https://dashboard.absoluteops.com/webhook-monitor/$MONITOR_ID"

if [ "$LOG_OUTPUT" == "true" ]; then
    LOG_FILE="$LOGDIR/monitor.log"
    exec > >(tee -a "$LOG_FILE" | sed "s/^/[$(basename $0)] /") 2>&1
    exec 2>&1
fi

# Get the memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')

# Send the memory usage to the monitor
curl --silent --request POST --url "$URL?value=$MEMORY_USAGE"
if [ $? != 0 ]; then
    echo "Failed to send memory usage."
fi
