#!/bin/bash

# leonstrand@gmail.com


name='consul-1'
echo

interface=$(ip -o link | awk '{print $2}' | egrep -v 'lo|loopback|docker' | tr -d :)
echo $0: interface: $interface

command="docker run \
  -d \
  --net=host \
  --name $name \
  -e CONSUL_BIND_INTERFACE=$interface \
  -e CONSUL_CLIENT_INTERFACE=$interface \
  consul \
    agent \
    -server \
    -bootstrap
"
echo $command
eval $command

echo
docker ps -f name=$name
echo
echo
