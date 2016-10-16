#!/bin/bash

# leon.strand@gmail.com


types='
consul
elasticsearch
logstash
kibana
'

consul() {
  printf '%s\t\t%8s\n' $(docker exec consul-1 ps -o comm,rss | grep consul)
}
logstash() {
  echo
  for container_id in $(docker ps -qf name=logstash); do
    name=$(docker ps -f id=$container_id --format="{{.Names}}")
    memory=$(docker exec $container_id ps -u logstash -o rss=)
    printf '%s\t%8d\n' $name $memory
  done | sort -V
}
elasticsearch() {
  echo
  for container_id in $(docker ps -qf label=elasticsearch); do
    name=$(docker ps -f id=$container_id --format="{{.Names}}")
    memory=$(docker exec $container_id ps -F | grep java | grep -v grep | awk '{print $6}')
    printf '%s\t%8d\n' $name $memory
  done | sort -V
}
kibana() {
  echo
  name='kibana-1'
  memory=$(docker exec kibana-1 ps -AF | grep kibana | grep -v grep | awk '{print $6}')
  printf '%s\t%8d\n' $name $memory
  name='kibana-1-es-lb'
  memory=$(docker exec kibana-1-elasticsearch-loadbalancer ps -AF | grep java | grep -v grep | awk '{print $6}')
  printf '%s\t%8d\n' $name $memory
}


consul
logstash
elasticsearch
kibana
