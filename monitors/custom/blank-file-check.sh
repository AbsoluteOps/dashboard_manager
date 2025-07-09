#!/bin/bash

MONITOR_ID=$1
API_URL=https://dashboard.absoluteops.com/webhook-monitor/${MONITOR_ID}?value=
varDate=`date +%y%m%d`
varPath=/opt/bim-cron/xfer/
varFileName=BIM_RPT0034_ACH_FUNDING_$varDate.CSV
varFullPath=$varPath$varFileName
varPhrase="No Records"

if [[ -f $varFullPath ]]; then
        result=`grep 'No Records' $varFullPath`
        if [[ $result == $varPhrase ]]; then
                COUNT=1
                echo "$varFileName is empty"
                curl $API_URL$COUNT
        else
                COUNT=0
                echo "$varFileName is good"
                curl $API_URL$COUNT
        fi
else
        COUNT=1
        echo "File does not exist."
        curl $API_URL$COUNT
fi