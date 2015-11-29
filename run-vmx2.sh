#!/bin/bash
docker run --name vmx2 --rm --privileged \
  -v $PWD:/u:ro \
  --env TAR="vmx-14.1R5.4-1.tgz" \
  --env CFG="vmx2.cfg" \
  --env DEV="0000:05:00.0 0000:05:00.1" \
  --env PFE="lite" \
  --env MEM="5000" --env VCPU="3" \
  -i -t marcelwiget/vmx:latest
