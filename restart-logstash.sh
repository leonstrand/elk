#!/bin/bash

# leonstrand@gmail.com


PATH=$PATH:/usr/sbin
containers=$@
if [ -z "$containers" ]; then
  echo $0: fatal: must supply at least one container name
  exit 1
fi

directory=$(pwd)
directory_logs=/pai-logs

# determine ip address
ip=$(ip -o -4 address | awk '$2 !~ /lo|docker/ {print $4}' | head -1 | cut -d/ -f1)

# discover elasticsearch nodes passing consul check
echo
echo
echo $0: info: elasticsearch nodes passing consul check
echo curl -sS $ip:8500/v1/catalog/service/elasticsearch-http?passing
elasticsearch_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | "\"" + .Address + ":" + "\(.Port)" + "\","' | sed 's/,$//')
if [ -z "$elasticsearch_hosts" ]; then
  echo $0: fatal: could not find any elasticsearch host
  exit 1
fi
echo $elasticsearch_hosts | tr -d \" | tr , \\n
elasticsearch_hosts='['$elasticsearch_hosts']'

# configure logstash
for container in $containers; do
  echo
  echo
  echo $0: info: configuring logstash output
  echo $0: info: container $container
  echo $0: info: logstash configuration file: $directory/logstash/containers/$container/config/300-output-logstash.conf
  sed 's/REPLACE/'$elasticsearch_hosts'/' $directory/logstash/template/300-output-logstash.conf | tee $directory/logstash/containers/$container/config/300-output-logstash.conf
done

# start logstash
for container in $containers; do
  echo
  echo
  echo $0: info: starting logstash container $container
  echo time docker start $container
  time docker start $container
done

# consul registration
service_name='logstash-pai'
server=$(grep path $directory/logstash/containers/$container/config/100-input-logstash.conf | awk '{print $NF}' | cut -d/ -f3)
echo
echo
echo $0: registering logstash with consul
echo curl -v -X PUT http://$ip:8500/v1/agent/service/register \
  -d "$(printf \''{
    "Name": "%s",
    "ID": "%s",
    "Address": "%s",
    "Checks": [
      {
        "TTL": "30s"
      }
    ]
  }'\' \
  $service_name \
  $server \
  $ip)"
curl -v -X PUT http://$ip:8500/v1/agent/service/register \
  -d "$(printf '{
    "Name": "%s",
    "ID": "%s",
    "Address": "%s",
    "Checks": [
      {
        "TTL": "30s"
      }
    ]
  }' \
  $service_name \
  $server \
  $ip)"
