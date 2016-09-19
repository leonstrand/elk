#!/bin/bash

# leonstrand@gmail.com


interface='ens33'
docker run \
  -d \
  --net=host \
  --name consul01 \
  -e CONSUL_BIND_INTERFACE=$interface \
  -e CONSUL_CLIENT_INTERFACE=$interface \
  consul \
    agent \
    -server \
    -bootstrap
