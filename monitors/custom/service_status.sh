#!/bin/bash

# Name: Service Status
# User: dashboard
# Period: 5 minutes
# Threshold: 1
# Direction: below

ROOTDIR=/opt/dashboard
ETCDIR=$ROOTDIR/etc
LOGDIR=$ROOTDIR/log

if [ -f "$ETCDIR/config.settings" ]; then
    source $ETCDIR/config.settings
fi

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <monitor_id> <service name"
    exit 1
fi

MONITOR_ID=$1
SERVICE_NAME=$2
URL="https://dashboard.absoluteops.com/webhook-monitor/$MONITOR_ID"

if [ "$LOG_OUTPUT" == "true" ]; then
    LOG_FILE="$LOGDIR/monitor.log"
    exec > >(tee -a "$LOG_FILE" | sed "s/^/[$(basename $0)] /") 2>&1
    exec 2>&1
fi

# Get the service status for the specified status
if [[ "$(systemctl is-active $SERVICE_NAME)" == "active" ]]; then SERVICE_STATUS = 0; else SERVICE_STATUS = 1; fi

# Send the disk usage to the monitor
curl --silent --request POST --url "$URL?value=$SERVICE_STATUS"
if [ $? != 0 ]; then
    echo "Failed to send service status."
fi
