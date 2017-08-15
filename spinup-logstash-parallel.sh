#!/bin/bash

# leonstrand@gmail.com


name='logstash'
directory=$(pwd)
directory_logs=/pai-logs
directory_data=/elk
container_name="$1"
server="$2"

# determine ip address
ip=$(ip -o -4 address | awk '$2 !~ /lo|docker/ {print $4}' | head -1 | cut -d/ -f1)
consul_service_name='logstash-pai'

# get list of server log directories
echo
echo
echo $0: info: log directories in $directory_logs:
find $directory_logs -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
servers=$(find $directory_logs -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort)

# determine container name
echo
echo
next_container=$container_name
echo $0: info: container name: $next_container

# discover elasticsearch nodes passing consul check
echo
echo
echo $0: info: elasticsearch nodes passing consul check
echo curl -sS $ip:8500/v1/catalog/service/elasticsearch-http?passing
elasticsearch_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http-data-ingest?passing | jq -jr '.[] | .Service | "\"" + .Address + ":" + "\(.Port)" + "\","' | sed 's/,$//')
if [ -z "$elasticsearch_hosts" ]; then
  echo $0: fatal: could not find any elasticsearch host
  exit 1
fi
echo $elasticsearch_hosts | tr -d \" | tr , \\n
elasticsearch_hosts='['$elasticsearch_hosts']'

# configure logstash
echo
echo
echo $0: info: configuring logstash
[ -d $directory/logstash/containers/$next_container ] && rm -rv $directory/logstash/containers/$next_container
mkdir -vp $directory/logstash/containers/$next_container
cp -vr $directory/logstash/config $directory/logstash/containers/$next_container
echo
echo $0: info: configuring logstash input
echo $0: info: logstash configuration file: $directory/logstash/containers/$next_container/config/100-input-logstash.conf
sed 's/REPLACE_SERVER/'$server'/' logstash/template/100-input-logstash.conf  | tee $directory/logstash/containers/$next_container/config/100-input-logstash.conf
echo
echo $0: info: configuring logstash output
echo $0: info: logstash configuration file: $directory/logstash/containers/$next_container/config/300-output-logstash.conf
sed 's/REPLACE/'$elasticsearch_hosts'/' logstash/template/300-output-logstash.conf | tee $directory/logstash/containers/$next_container/config/300-output-logstash.conf
echo
echo $0: info: configuring logstash heartbeat
echo $0: info: logstash configuration file: $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf
sed 's/REPLACE_CONSUL_HOST/'$ip'/' logstash/template/400-heartbeat-logstash.conf > $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf
sed -i 's/REPLACE_LOGSTASH_SERVER/'$server'/' $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf
cat $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf

# prepare data directory
echo
echo
echo $0: info: preparing data directory
[ -d $directory_data/logstash/$next_container ] && rm -rv $directory_data/logstash/$next_container
echo mkdir -vpm 777 $directory_data/logstash/$next_container/data
mkdir -vpm 777 $directory_data/logstash/$next_container/data


# spin up logstash container
echo
echo
echo $0: info: starting container $next_container
command="
docker run -d \
  --name $next_container \
  -e LS_HEAP_SIZE=2048m \
  -v /pai-logs:/pai-logs \
  -v $directory/logstash/elasticsearch-template.json:/opt/logstash/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch-2.7.1-java/lib/logstash/outputs/elasticsearch/elasticsearch-template.json \
  -v $directory/logstash/containers/$next_container/config:/config \
  -v $directory/logstash/logstash.yml:/etc/logstash/logstash.yml:ro \
  -v $directory_data/logstash/$next_container/data:/usr/share/logstash/data \
  -v $directory/logstash/log4j2.properties:/etc/logstash/log4j2.properties:ro \
  logstash \
  -f /config/
"
  #--log.level debug
echo $0: info: command:
echo $command
result=$(eval $command)
echo $0: info: result: $result

# consul registration
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
$consul_service_name \
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
$consul_service_name \
$server \
$ip)"

echo
echo
docker ps -f name=$next_container
echo
