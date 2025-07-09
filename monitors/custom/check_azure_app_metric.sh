#!/bin/bash

MON=$1
METRIC=$2
ID=$3

NOW=$(date)
VAL=$(az monitor metrics list --metric $METRIC --interval 5m --offset 10m --resource $ID | jq .value[].timeseries[].data[-1].average)
if [ "$VAL" == "null" ]
then
  echo $VAL >> /opt/dashboard/tmp/nullcounter
fi

NULLS=$(cat /opt/dashboard/tmp/nullcounter | wc -l)
if [ "$VAL" != "null" ] || [ $NULLS -eq 5 ]
then
  cat /dev/null > /opt/dashboard/tmp/nullcounter
  APP=$(echo $ID | awk -F/ '{print $NF}')
  echo "$NOW: $METRIC - $VAL" >> /opt/dashboard/logs/$APP
  curl https://dashboard.absoluteops.com/webhook-monitor/${MON}?value=$VAL
fi
