#!/bin/bash
# Starts flume agent based on name

#GLOBAL and DEFAULT vars
ME=$(basename $0)

function use() {
  echo -e "$ME [--parametrize] agent-name"
  echo -e "\t where agent-name is the agent to be executed."
  echo ""
  echo -e "\t The configuraton file expected is /etc/flume/agent-<agent-name>.conf"
  echo ""
  echo -e "\t Custom log4.properties file can be specified in /etc/ingestion/<agent-name>-log4j.properties"
  echo ""
  echo -e "\t if --parametrize is enabled (present) we look for /etc/flume/params-<agent-name>.conf and it will be"
  echo -e "\t used to replace values into /etc/flume/*<agent-name>* files (except params-<agent-name>.conf)"
  echo -e "\t files on /etc/flume/* will not be edited, instead changed files will be saved in temporal path"
  echo -e "\t and flume executable will be pointed to this configuration."
  echo ""
  echo -e "\t Format of each line of params-<agent-name>.conf is:"
  echo ""
  echo -e "\t\t var.name=VALUE : all \${var.name} occurences will be replaced by VALUE on *<agent-name>* files"
  echo -e "\t\t\t Special value \"__path__\" can be used. In this case __path__ will be replaced by effective configuration path."
  echo -e "\t\t\t \"Effective configuration path\" is temporal directory where files after parametrizacion are saved"
  echo ""
  echo ""
  echo -e "\t\t \$curl\$var.name=\$localname\$url : Content of \"url\" will be downladed and saved in a file called \"localname\" "
  echo -e "\t\t\t all \${var.name} occurences will be replaced by localname full-path on *<agent-names>* files"
}

if [ "$1" == "--help" ]
then
  use
  exit 0
fi

PARAMETRIZE="no"
if [ "$1" == "--parametrize" ]
then
  PARAMETRIZE="yes"
  shift
fi

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
if [ "$PARAMETRIZE" == "yes" ]
then
  TEMPDIR=$(mktemp -d)
  cp -rpv /etc/flume/*$AGENTNAME* $TEMPDIR/
  files=$(find $TEMPDIR/ -type f | fgrep -v params-$AGENTNAME.conf | xargs echo)
  cat /etc/flume/params-$AGENTNAME.conf | awk -v files="$files" -v path="$TEMPDIR" -f /usr/var/lib/flume/bin/parametrize.awk > $TEMPDIR/presetup.sh
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
