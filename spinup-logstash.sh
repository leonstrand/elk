#!/bin/bash

# leonstrand@gmail.com


echo

name='ls'
directory=$(pwd)
last_container=$(docker ps -af name=${name}- | grep -v CONTAINER | awk '{print $NF}' | sort | tail -1)
if [ -z "$last_container" ]; then
  next_container=${name}-1
else
  next_container=${name}-$(expr $(echo $last_container | awk 'BEGIN { FS = "-" } ; { print $NF }') + 1)
fi
echo next_container: $next_container


# determine ip address
ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)

# consul discovery of any existing elasticsearch nodes
elasticsearch_hosts=$(curl -sS $ip:8500/v1/catalog/service/elasticsearch-http | jq -jr '.[] | "\"" + .ServiceAddress + ":" + "\(.ServicePort)" + "\","' | sed 's/,$//')
if [ -z "$elasticsearch_hosts" ]; then
  echo $0: fatal: could not find any elasticsearch host via:
  echo curl -sS $ip:8500/v1/catalog/service/elasticsearch-http
  exit 1
fi
elasticsearch_hosts='['$elasticsearch_hosts']'
echo elasticsearch_hosts: $elasticsearch_hosts

[ -d $directory/logstash/containers/$next_container ] && rm -rv $directory/logstash/containers/$next_container
mkdir -vp $directory/logstash/containers/$next_container
cp -vr $directory/logstash/config $directory/logstash/containers/$next_container
sed 's/REPLACE/'$elasticsearch_hosts'/' logstash/template/300-output-logstash.conf  | tee $directory/logstash/containers/$next_container/config/300-output-logstash.conf

  #-v $directory/logstash/containers/$next_container/config:/etc/logstash/conf.d \
command="
docker run -d \
  --name $next_container \
  -v /pai-logs:/pai-logs \
  -v $directory/logstash/elasticsearch-template.json:/opt/logstash/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch-2.7.1-java/lib/logstash/outputs/elasticsearch/elasticsearch-template.json \
  -v $directory/logstash/containers/$next_container/config:/config \
  logstash \
  -f /config/ \
  --auto-reload
"
echo $command
eval $command

echo
docker ps -f name=$name
echo
echo
