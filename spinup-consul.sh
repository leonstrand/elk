#!/bin/bash

# leonstrand@gmail.com


name='consul-1'
echo

interface='ens33'
docker run \
  -d \
  --net=host \
  --name $name \
  -e CONSUL_BIND_INTERFACE=$interface \
  -e CONSUL_CLIENT_INTERFACE=$interface \
  consul \
    agent \
    -server \
    -bootstrap

echo
docker ps -f name=$name
echo
echo
