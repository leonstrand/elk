#!/bin/bash

# leon.strand@gmail.com


types='
consul
elasticsearch
logstash
kibana
'

consul() {
  docker exec consul-1 ps -o comm,rss | grep consul
}
logstash() {
  echo
  for container_id in $(docker ps -qf name=logstash); do
    name=$(docker ps -f id=$container_id --format="{{.Names}}")
    memory=$(docker exec $container_id ps -u logstash -o rss=)
    echo $name $memory
  done | sort -V
}
elasticsearch() {
  echo
  for container_id in $(docker ps -qf label=elasticsearch); do
    name=$(docker ps -f id=$container_id --format="{{.Names}}")
    memory=$(docker exec $container_id ps -F | grep java | grep -v grep | awk '{print $6}')
    echo $name $memory
  done | sort -V
}
kibana() {
  echo
  echo -n kibana-1\ 
  docker exec kibana-1 ps -AF | grep kibana | grep -v grep | awk '{print $6}'
  #echo -n kibana-1-elasticsearch-loadbalancer\ 
  echo -n kibana-1-es-lb\ 
  docker exec kibana-1-elasticsearch-loadbalancer ps -AF | grep java | grep -v grep | awk '{print $6}'
}


consul
logstash
elasticsearch
kibana
