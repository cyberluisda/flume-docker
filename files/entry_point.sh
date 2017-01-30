#!/bin/bash
# Starts flume agent based on name

#GLOBAL and DEFAULT vars
ME=$(basename $0)

function use() {
    echo -e "$ME agent-name"
    echo -e "\t where agent-name is the agent to be executed."
    echo -e "\t the configuraton file expected is /etc/flume/agent-<agent-name>.conf"
    echo -e "\t specifig log4.properties file can be specified in /etc/ingestion/<agent-name>-log4j.properties"

}

if [ -z "$1" ]; then
  use
  exit 1
fi
AGENTNAME="$1"
shift 1

DEFAULTLOGLEVEL="INFO"
if [ ! -z "$1" ]; then
  DEFAULTLOGLEVEL="$1"
  shift 1
fi

#The rest of the args will be passed to agent

if [ ! -f "/etc/flume/agent-$AGENTNAME.conf" ]; then
  echo -e "ERROR: I can not find file /etc/flume/agent-$AGENTNAME.conf \n\n"
  use
  exit 1
fi

LOGFILECONFIG=""
LOGLEVEL=""
if [ -f "/etc/flume/$AGENTNAME-log4j.properties" ]; then
  LOGFILECONFIG="-Dlog4j.configuration=file:///etc/flume/$AGENTNAME-log4j.properties"
else
    LOGLEVEL="-Dflume.root.logger=$DEFAULTLOGLEVEL,console"
fi


#RUN command
flume-ng agent --classpath /var/flume/extra-libs/\*:/usr/var/lib/flume/extra-libs/\* --conf /usr/var/lib/flume/conf --conf-file /etc/flume/agent-$AGENTNAME.conf --name $AGENTNAME $LOGFILECONFIG $LOGLEVEL $@
