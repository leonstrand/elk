#!/bin/bash

# leonstrand@gmail.com


name='consul-1'
consul_seed='192.168.1.62'

echo
echo
echo $0: determining self ip address
interface=$(ip -o link | egrep -v 'lo|loopback|docker' | awk '{print $2}' | tr -d :)
echo $0: interface: $interface

echo
echo $0: starting consul container
command="docker run
  -d
  --net=host
  --name $name
  -e CONSUL_BIND_INTERFACE=$interface
  -e CONSUL_CLIENT_INTERFACE=$interface
  consul
    agent
    -server
"
case "$1" in
  b|boot|bootstrap) command=$command' -bootstrap';;
  *) command=$command' -join '$consul_seed;;
esac
echo $command
eval $command

echo
echo
docker ps -f name=$name
echo
