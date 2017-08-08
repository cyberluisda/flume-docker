#!/bin/bash
# Starts flume agent based on name
set -e

#GLOBAL and DEFAULT vars
ME=$(basename $0)
#Only for listed here.
WAIT_FOR_SERVICE_UP="${WAIT_FOR_SERVICE_UP}"
WAIT_FOR_SERVICE_UP_TIMEOUT="${WAIT_FOR_SERVICE_UP_TIMEOUT:-10s}"

function usage() {
  cat << EOF
  $ME [--parametrize [-e name1=value1 ... -e nameN=valueN] ] agent-name
  	 where agent-name is the agent to be executed.

  	 The configuraton file expected is /etc/flume/agent-<agent-name>.conf

  	 Custom log4.properties file can be specified in /etc/ingestion/<agent-name>-log4j.properties

  	 if --parametrize is enabled (present) we look for /etc/flume/params-<agent-name>.conf and it will be
  	 used to replace values into /etc/flume/*<agent-name>* files (except params-<agent-name>.conf)
  	 files on /etc/flume/* will not be edited, instead changed files will be saved in temporal path
  	 and flume executable will be pointed to this configuration.

  	 Format of each line of params-<agent-name>.conf is:

  		 var.name=VALUE : all \${var.name} occurences will be replaced by VALUE on *<agent-name>* files
  			 Special value "__path__" can be used. In this case __path__ will be replaced by effective configuration path.
  			 "Effective configuration path" is temporal directory where files after parametrizacion are saved


  		 \$curl\$var.name=\$localname\$url : Content of \"url\" will be downladed and saved in a file called "localname"
  			 all \${var.name} occurences will be replaced by localname full-path on *<agent-names>* files

  	 You can use -e nameX=valueX to add (on top of) on-fly vars and values (with format previously described) to content
  	 loaded from /etc/flume/params-<agent-name>.conf

     ENVIRONMENT CONFIGURATION.
      There are some configuration and behaviours that can be set using next Environment
      Variables:
          WAIT_FOR_SERVICE_UP. If it is defined we wait (using dockerize) for service(s)
            to be started before to perform any operation. Example values:
            WAIT_FOR_SERVICE_UP="http://server" wait for http connection to server
            are available
            WAIT_FOR_SERVICE_UP="tcp://kafka:9092 tcp://zookeeper:2181" Wait for
            kafka:9092 and zookeeper:2818 connections are avilable.
            If one of this can not be process will exit with error. See
            https://github.com/jwilder/dockerize for more information.
          WAIT_FOR_SERVICE_UP_TIMEOUT. Set timeot when check services listed on
            WAIT_FOR_SERVICE_UP. Current value $WAIT_FOR_SERVICE_UP_TIMEOUT
EOF
}

if [ "$1" == "--help" ]
then
  usage
  exit 0
fi

echo "ARGS: $@"

PARAMETRIZE="no"
ONFLYVARS=""
if [ "$1" == "--parametrize" ]
then
  PARAMETRIZE="yes"
  shift

  #EXTRACT ONFLYVARS
  while [ "$1" == "-e" ]
  do
    if [ -z "$2" ]
    then
      echo "-e definition without value"
      usage
      exit 1
    fi
    ONFLYVARS="${ONFLYVARS}$2\n"
    shift 2
  done

fi

if [ -z "$1" ]; then
  usage
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
  usage
  exit 1
fi

LOGFILECONFIG=""
LOGLEVEL=""
if [ -f "/etc/flume/$AGENTNAME-log4j.properties" ]; then
  LOGFILECONFIG="-Dlog4j.configuration=file:///etc/flume/$AGENTNAME-log4j.properties"
else
  LOGLEVEL="-Dflume.root.logger=$DEFAULTLOGLEVEL,console"
fi

# Wait for services if enabled.
if [ -n "$WAIT_FOR_SERVICE_UP" ]; then
  services=""
  #Set -wait option to use with docerize
  for service in $WAIT_FOR_SERVICE_UP; do
    services="$services -wait $service"
  done
  echo "Waiting till services $WAIT_FOR_SERVICE_UP are accessible (or timeout: $WAIT_FOR_SERVICE_UP_TIMEOUT)"
  dockerize $services -timeout "$WAIT_FOR_SERVICE_UP_TIMEOUT"
fi

#RUN command
if [ "$PARAMETRIZE" == "yes" ]
then
  TEMPDIR=$(mktemp -d)
  cp -rpv /etc/flume/*$AGENTNAME* $TEMPDIR/
  files=$(find $TEMPDIR/ -type f | fgrep -v params-$AGENTNAME.conf | xargs echo)
  touch $TEMPDIR/onflyvars
  if [ -n "$ONFLYVARS" ]
  then
    echo -e "$ONFLYVARS" > $TEMPDIR/onflyvars
  fi
  cat $TEMPDIR/onflyvars /etc/flume/params-$AGENTNAME.conf | egrep -ve "^$" | awk -v files="$files" -v path="$TEMPDIR" -f /usr/var/lib/flume/bin/parametrize.awk > $TEMPDIR/presetup.sh
  chmod a+x $TEMPDIR/presetup.sh
  $TEMPDIR/presetup.sh

  #Resolve again log4j configuration but now based on TEMPDIR
  LOGFILECONFIG=""
  LOGLEVEL=""
  if [ -f "$TEMPDIR/$AGENTNAME-log4j.properties" ]
  then
    LOGFILECONFIG="-Dlog4j.configuration=file://$TEMPDIR/$AGENTNAME-log4j.properties"
  else
    LOGFILECONFIG="-Dlog4j.configuration=file:///usr/var/lib/flume/conf/log4j.properties"
    LOGLEVEL="-Dflume.root.logger=$DEFAULTLOGLEVEL,console"
  fi

  # Trap signal to remove temp path
  trap "rm -fr ${TEMPDIR}; exit" SIGHUP SIGINT SIGTERM

  flume-ng agent --classpath /var/flume/extra-libs/\*:/usr/var/lib/flume/extra-libs/\* --conf $TEMPDIR --conf-file $TEMPDIR/agent-$AGENTNAME.conf --name $AGENTNAME $LOGFILECONFIG $LOGLEVEL $@
else
  flume-ng agent --classpath /var/flume/extra-libs/\*:/usr/var/lib/flume/extra-libs/\* --conf /usr/var/lib/flume/conf --conf-file /etc/flume/agent-$AGENTNAME.conf --name $AGENTNAME $LOGFILECONFIG $LOGLEVEL $@
fi
