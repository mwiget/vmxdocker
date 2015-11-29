#!/bin/bash
docker run --name vmx1 --rm --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-15.1F3.11.tgz" \
  --env CFG="vmx1.cfg" \
  --env CONFIG="vmx1.conf.txt" \
  --env DEV="br0 br0" \
  --env MEM="8000" --env VCPU="7" \
  -i -t marcelwiget/vmx:latest
