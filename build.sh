#!/bin/bash
#docker build --no-cache=true -t marcelwiget/vmx:latest .
#docker build -t marcelwiget/vmx:latest .
#docker build -t marcelwiget/vmx:lwaftr .
docker build --no-cache=true -t marcelwiget/vmx:lwaftr .
#LEFTOVER=$(docker images | grep "^<none>" | awk '{print $3}')
#if [ ! -z "$LEFTOVER" ]; then
#  docker rmi $(docker images | grep "^<none>" | awk '{print $3}')
#fi
docker push marcelwiget/vmx:lwaftr
