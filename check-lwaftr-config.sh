#!/bin/bash
PASSWORD=lwaftr1
CONFIG=$1
touch /tmp/lwaftr-config    # avoid killing snabb the first time

while :
do
  sleep 30 
  IP=`grep '172.17.0' /u/$CONFIG |cut -d's' -f 3|cut -d'/' -f1 |sed 's/ //'`
  if [ "X$IP" == "X" ]; then
    IP=`grep fxp0 /u/$CONFIG|cut -d' ' -f7|cut -d'/' -f1`
  fi
  if [ "X$IP" == "X" ]; then
    echo "Can't determine IP address of fxp0. Stopping lwaftr check"
    exit 1
  fi
#  echo "vMX fxp0 has IP $IP"
  sshpass -p lwaftr1 ssh -o StrictHostKeyChecking=no lwaftr@$IP "show conf groups" > /tmp/lwaftr-config.new
  diff /tmp/lwaftr-config.new /tmp/lwaftr-config >/dev/null 2>&1
  if [ $? != 0 ]; then
     rm -f /tmp/lwaftr-xe*.cfg
     if [ -s /tmp/lwaftr-config.new ]; then
       # new non empty config. Lets process it!
       /parse-lwaftr-config.pl < /tmp/lwaftr-config.new
     fi
     # restart snabb. 
     cp /tmp/lwaftr-config.new /tmp/lwaftr-config
     killall snabb
  fi
done
