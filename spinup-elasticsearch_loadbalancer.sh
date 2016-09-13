#!/bin/bash

# leonstrand@gmail.com


#name='elasticsearch_loadbalancer_'
name='eslb'
last_container=$(docker ps -qf name=${name}- | awk '{print $NF}' | sort | tail -1)
if [ -z "$last_container" ]; then
  next_container=${name}-1
else
  next_container=${name}-$(expr $(echo $last_container | awk 'FS=-; {print $NF}') + 1)
fi
echo next_container: $next_container


ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)
base_port=10000

# select next free http port over $base_port
last_http_port=$(for i in $(docker ps -qf name=$name); do docker port $i | awk '/^9200/ {print $NF}' | cut -d: -f2; done | sort -n)
if [ -z "$last_http_port" ]; then
  next_http_port=$(expr $base_port + 9200 + 1)
else
  next_http_port=$(expr $last_http_port + 1)
fi
echo next_http_port: $next_http_port

# select next free transport port over $base_port
last_transport_port=$(for i in $(docker ps -qf name=$name); do docker port $i | awk '/^9300/ {print $NF}' | cut -d: -f2; done | sort -n)
if [ -z "$last_transport_port" ]; then
  next_transport_port=$(expr $base_port + 9300 + 1)
else
  next_transport_port=$(expr $last_transport_port + 1)
fi
echo next_transport_port: $next_transport_port

  #-Des.logger.level=DEBUG

echo \
docker run -d \
  --name $next_container \
  -p $next_http_port:9200 \
  -p $next_transport_port:9300 \
  elasticsearch \
  -Dnetwork.host=0.0.0.0 \
  -Des.node.name=$(hostname)-$next_container \
  -Des.cluster.name=elasticsearch-pai \
  -Dnetwork.publish_host=$ip \
  -Dhttp.publish_port=$next_http_port \
  -Dtransport.publish_port=$next_transport_port \
  -Des.node.master=false \
  -Des.node.data=false \
  -Des.discovery.zen.ping.multicast.enabled=false


#CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS                        PORTS                                              NAMES
#8231ba365dfd        elasticsearch       "/docker-entrypoint.s"   9 minutes ago       Up 9 minutes                  0.0.0.0:32780->9200/tcp, 0.0.0.0:32779->9300/tcp   eslb2

#docker exec su -c 'elasticsearch -Dhttp.publish_port=9222' elasticsearch
#docker exec --user elasticsearch elasticsearch elasticsearch -Dhttp.publish_port=9222'
