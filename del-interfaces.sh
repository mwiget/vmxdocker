#!/bin/bash
# helper script to clean up tap and virtual bridges during development

TAPS=`ifconfig -a|grep ^v|cut -d' ' -f1`
for INT in $TAPS; do
  echo INT=$INT
  sudo ip tuntap del mode tap dev $INT
done
TAPS=`ifconfig -a|grep ^g|cut -d' ' -f1`
for INT in $TAPS; do
  echo INT=$INT
  sudo ip tuntap del mode tap dev $INT
done

BRIDGES=`brctl show|grep ^br|grep -v bridge|cut -d' ' -f1`

for BRIDGE in $BRIDGES; do
  echo BRIDGE=$BRIDGE
  sudo ifconfig $BRIDGE down
  sudo brctl delbr $BRIDGE
done
