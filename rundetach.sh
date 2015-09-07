docker run --name vmx1 -d --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-14.1R5.4-1.tgz" \
  --env CFG="vmx1.cfg" \
  --env DEV="br0 br0" \
  --env PFE="lite" \
  --env MEM="5000" --env VCPU="5" \
  -i -t marcelwiget/vmx:latest
