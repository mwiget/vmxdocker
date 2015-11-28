#!/bin/bash
PASSWORD=lwaftr1
CFG=*.cfg

while :
do
  IP=`grep fxp0 /u/$CFG|cut -d' ' -f7|cut -d'/' -f1`
#  echo "vMX fxp0 has IP $IP"
  sshpass -p lwaftr1 ssh -o StrictHostKeyChecking=no lwaftr@$IP "show conf groups | find lwaftr" > /tmp/lwaftr-config.new
  diff /tmp/lwaftr-config.new /tmp/lwaftr-config >/dev/null 2>&1
  if [ $? != 0 ]; then
     rm -f /tmp/lwaftr-xe*.cfg
     if [ -s /tmp/lwaftr-config.new ]; then
#       echo "new config!"
       cp /tmp/lwaftr-config.new /tmp/lwaftr-config
       /parse-lwaftr-config.pl < /tmp/lwaftr-config
#       echo "restarting snabb"
       killall snabb
     fi
  fi
  sleep 60 
done
