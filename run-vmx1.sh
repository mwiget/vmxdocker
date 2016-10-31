#!/bin/bash
docker run --name vmx1 --rm --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-bundle-16.1R2.11.tgz" \
  --env CFG="vmx1.cfg" \
  --env DEV="br0 br0" \
  --env VCPMEM="1000" \
  --env MEM="4000" \
  --env VCPU="3" \
  -i -t marcelwiget/vmx:latest
