#!/bin/bash

# Name: Disk Usage
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

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <monitor_id> <filesystem>"
    exit 1
fi

MONITOR_ID=$1
FILESYSTEM=$2
URL="https://dashboard.absoluteops.com/webhook-monitor/$MONITOR_ID"

if [ "$LOG_OUTPUT" == "true" ]; then
    LOG_FILE="$LOGDIR/monitor.log"
    exec > >(tee -a "$LOG_FILE" | sed "s/^/[$(basename $0)] /") 2>&1
    exec 2>&1
fi

# Get the disk usage for the specified filesystem
DISK_USAGE=$(df "$FILESYSTEM" | grep "$FILESYSTEM" | awk '{print $5}' | sed 's/%//g')

# Send the disk usage to the monitor
curl --silent --request POST --url "$URL?value=$DISK_USAGE"
if [ $? != 0 ]; then
    echo "Failed to send disk usage."
fi
