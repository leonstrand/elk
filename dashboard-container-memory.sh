#!/bin/bash

# leon.strand@gmail.com


types='
consul
elasticsearch
logstash
kibana
'

output_memory_in_megabytes() {
  memory=$(echo 'scale=0;('$memory'+500)/1000' | bc)
  printf '%-16s %5s\n' $name ${memory}m
}
consul() {
  printf '%-16s %5s\n' $(docker exec consul-1 ps -o comm,rss | grep consul)
}
logstash() {
  container_ids=$(docker ps -qf name=logstash)
  if [ -n "$container_ids" ]; then
    echo
    for container_id in $container_ids; do
      name=$(docker ps -f id=$container_id --format="{{.Names}}")
      memory=$(docker exec $container_id ps -u logstash -o rss=)
      output_memory_in_megabytes
    done | sort -V
  fi
}
elasticsearch() {
  echo
  for container_id in $(docker ps -qf label=elasticsearch); do
    name=$(docker ps -f id=$container_id --format="{{.Names}}")
    memory=$(docker exec $container_id ps -u elasticsearch -o rss --no-headers | tr -cd '[:print:]')
    output_memory_in_megabytes
  done | sort -V
}
kibana() {
  echo
  name='kibana-1'
  memory=$(docker exec kibana-1 ps -AF | grep kibana | grep -v grep | awk '{print $6}')
  output_memory_in_megabytes
  name='kibana-1-es-lb'
  memory=$(docker exec kibana-1-elasticsearch-loadbalancer ps -AF | grep java | grep -v grep | awk '{print $6}')
  output_memory_in_megabytes
}


consul
logstash
elasticsearch
kibana
