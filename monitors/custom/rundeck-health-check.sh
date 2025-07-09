#!/bin/bash

MONITOR_ID=$1
if [ "$MONITOR_ID" == "" ]
then
  echo "Usage: $0 <monitor id>"
  exit 1
fi

function join()
{
  local IFS="$1"
  shift
  echo "$*"
}

RUNDECK_CONFIG=/home/rundeck/server/config/rundeck-config.properties
TMPFILE=/tmp/lastrundeckcheck
LASTFAIL=`cat $TMPFILE 2>/dev/null`
if [ "$LASTFAIL" == "" ]
then
  LASTFAIL=`date "+%Y-%m-%d %H:%M:%S" -d "2 hours ago"`
fi

D=`grep "^dataSource.url =" $RUNDECK_CONFIG | awk -F/ '{print $3}' | awk -F: '{print $1}'`
U=`grep "^dataSource.username =" $RUNDECK_CONFIG | awk '{print $3}'`
P=`grep "^dataSource.password =" $RUNDECK_CONFIG | awk '{print $3}'`

ALERTSEV=0
ALERTS=()

RESULTS=`mysql --ssl -h $D -u $U -p$P -B -N -e "select a.id, a.date_completed, IF(b.description LIKE '%CRITICAL%', 2, 1) as criticality, b.job_name from rundeck.execution a, rundeck.scheduled_execution b where b.id=a.scheduled_execution_id and failed_node_list is not NULL and date_completed > '$LASTFAIL'" 2>/dev/null`
if [ $? -ne 0 ]
then
  echo "Unable to connect to the database."
  exit 1
fi


IFS=$'\n'
for RESULT in $RESULTS
do
  JOBID=`echo $RESULT | awk '{print $1}'`
  DATETIME=`echo $RESULT | awk '{print $2 " " $3}'`
  ALERTSEV=`echo $RESULT | awk '{print $4}'`
  JOBNAME=`echo $RESULT | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^ *//'`
  ALERTS+=("$JOBNAME / Job ID $JOBID failed on $DATETIME")
done
COUNT=${#ALERTS[@]}

if [ $COUNT -gt 0 ]
then
  ALERTLIST=`join , "${ALERTS[@]}"`
  LASTFAIL=$DATETIME
  echo $ALERTLIST
  curl https://dashboard.absoluteops.com/webhook-monitor/${MONITOR_ID}?value=2
else
  echo "All good"
  curl https://dashboard.absoluteops.com/webhook-monitor/${MONITOR_ID}?value=1
fi

echo $LASTFAIL > $TMPFILE