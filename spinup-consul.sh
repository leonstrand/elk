#!/bin/bash

# leonstrand@gmail.com


name='consul-1'

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
  b|boot|bootstrap)
    echo $0: bootstrap mode selected by input \'$1\'
    command=$command' -bootstrap'
  ;;
  '')
    echo
    echo
    echo $0: fatal: must provide input string \'bootstrap\' or consul server hostname or ip address
    echo
    echo $0: bootstrap examples:
    echo $0: usage $0 b
    echo $0: usage $0 boot
    echo $0: usage $0 bootstrap
    echo
    echo $0 hostname or ip address examples
    echo $0: usage $0 foo.bar.local
    echo $0: usage $0 1.1.1.1
    echo
    exit 1
  ;;
  *) command=$command' -join '$1;;
esac
echo $command
eval $command

echo
echo
docker ps -f name=$name
echo
