docker run --name vmx3 --rm --privileged --net=host \
  -v $PWD:/u:ro \
  --env TAR="vmx-14.1R5.4-1.tgz" \
  --env CFG="vmx3.cfg" \
  --env DEV="0000:05:00.0 0000:05:00.1" \
  --env PFE="lite" \
  -i -t marcelwiget/vmx:latest
