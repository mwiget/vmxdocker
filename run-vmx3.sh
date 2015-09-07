docker run --name vmx1 --rm --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-14.1R5.4-1.tgz" \
  --env CFG="vmx1.cfg" \
  --env DEV="0000:04:00.0 0000:04:00.1 br0 br1 br2" \
  --env PFE="lite" \
  -i -t marcelwiget/vmx:latest
