#!/bin/bash 
# Used only during development to remove all containers and images !!
# 
# Delete all containers 
docker rm $(docker ps -a -q) 
# Delete all images 
docker rmi $(docker images -q)
