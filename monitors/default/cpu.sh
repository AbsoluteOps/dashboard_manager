#!/bin/bash

# Name: CPU Usage
# User: dashboard
# Period: 5 minutes
# Threshold: 80
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

# Get the CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

# Send the CPU usage to the monitor
curl --silent --request POST --url "$URL?value=$CPU_USAGE"
if [ $? != 0 ]
then
    echo "Failed to send CPU usage."
fi
