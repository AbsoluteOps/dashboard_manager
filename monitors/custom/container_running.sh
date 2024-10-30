#!/bin/bash

# Name: Container Running
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
    echo "Usage: $0 <monitor_id> <container_name>"
    exit 1
fi

MONITOR_ID=$1
CONTAINER_NAME=$2
URL="https://dashboard.absoluteops.com/webhook-monitor/$MONITOR_ID"

if [ "$LOG_OUTPUT" == "true" ]; then
    LOG_FILE="$LOGDIR/monitor.log"
    exec > >(tee -a "$LOG_FILE" | sed "s/^/[$(basename $0)] /") 2>&1
    exec 2>&1
fi

# Check if the Docker container is running
CONTAINER_RUNNING=$(docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" --format "{{.Names}}" | grep -w "$CONTAINER_NAME" | wc -l)

# Send the container running status to the monitor
curl --silent --request POST --url "$URL?value=$CONTAINER_RUNNING"
if [ $? != 0 ]; then
    echo "Failed to send container running status."
fi
