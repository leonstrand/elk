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

# determine container name
echo
echo
next_container=$container_name
echo $0: info: container name: $next_container





# spin up dedicated elasticsearch ingest container
name_elasticsearch='elasticsearch'
elasticsearch_cluster_name='elasticsearch-mede'

echo
echo
next_container_elasticsearch_ingest=$next_container'-elasticsearch-ingest'
echo $0: info: elasticsearch ingest container name: $next_container_elasticsearch_ingest

# select next free http port over $base_port
base_port=10000
last_http_port=$(for i in $(docker ps -qf name=$name_elasticsearch); do docker port $i | awk '/^9200/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_http_port" ]; then
  next_http_port=$(expr $base_port + 9200 + 1)
else
  next_http_port=$(expr $last_http_port + 1)
fi
# TODO open port check
echo $0: info: http port: $next_http_port

# select next free transport port over $base_port
last_transport_port=$(for i in $(docker ps -qf name=$name_elasticsearch); do docker port $i | awk '/^9300/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_transport_port" ]; then
  next_transport_port=$(expr $base_port + 9300 + 1)
else
  next_transport_port=$(expr $last_transport_port + 1)
fi
# TODO open port check
echo $0: info: transport port: $next_transport_port

# discover responsive elasticsearch nodes
unicast_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-transport?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + ","' | sed 's/,$//')
echo $0: info: live elasticsearch nodes:
echo $unicast_hosts | tr , \\n
if [ -z "$unicast_hosts" ]; then
  unicast_hosts=$ip':'$next_transport_port
fi

#-Des.logger.level=DEBUG
echo
echo
echo $0: info: starting container $next_container_elasticsearch_ingest
# TODO node.ingest: true 
# TODO search.remote.connect: false
command="
docker run -d \
  --name $next_container_elasticsearch_ingest \
  --label elasticsearch
  -p $next_http_port:9200 \
  -p $next_transport_port:9300 \
  elasticsearch \
  -Enetwork.host=0.0.0.0 \
  -Enode.name=$(hostname)-$next_container_elasticsearch_ingest \
  -Enode.master=false \
  -Enode.data=false \
  -Ecluster.name=$elasticsearch_cluster_name \
  -Enetwork.publish_host=$ip \
  -Ehttp.publish_port=$next_http_port \
  -Etransport.publish_port=$next_transport_port \
  -Ediscovery.zen.ping.unicast.hosts=$unicast_hosts \
  -Eindex.codec=best_compression
"
echo $0: info: command:
echo $command
result=$(eval $command)
echo $0: info: result: $result

# consul registration
echo
echo
echo $0: info: waiting for $next_container_elasticsearch_ingest container on http port $next_http_port to respond with status 200
echo docker ps -f name=$next_container_elasticsearch_ingest
docker ps -f name=$next_container_elasticsearch_ingest
echo
echo netstat -lnt \| egrep \''Active|Proto|'$next_http_port\'
netstat -lnt | egrep 'Active|Proto|'$next_http_port
echo
echo
echo curl $ip:$next_http_port
until curl $ip:$next_http_port 1>/dev/null 2>&1; do
  sleep 1
done
curl $ip:$next_http_port
if curl $ip:$next_http_port 1>/dev/null 2>&1; then
  CONSUL_IP=$ip
  CONSUL_PORT=8500

  # register es transport
  echo $0: info: registering elasticsearch ingest transport service with consul
  echo curl -v --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf \''{
    "ID":"%s",
    "Name":"elasticsearch-transport",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }'\' \
  elasticsearch-transport-$ip:$next_transport_port \
  $ip \
  $next_transport_port \
  $ip \
  $next_http_port)"

  curl -v --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf '{
    "ID":"%s",
    "Name":"elasticsearch-transport",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }' \
  elasticsearch-transport-$ip:$next_transport_port \
  $ip \
  $next_transport_port \
  $ip \
  $next_http_port)"

  # register es http
  echo
  echo $0: info: registering elasticsearch ingest http service with consul
  echo curl -v --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf \''{
    "ID":"%s",
    "Name":"elasticsearch-http",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }'\' \
  elasticsearch-http-$ip:$next_http_port \
  $ip \
  $next_http_port \
  $ip \
  $next_http_port)"

  curl -v --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf '{
    "ID":"%s",
    "Name":"elasticsearch-http",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }' \
  elasticsearch-http-$ip:$next_http_port \
  $ip \
  $next_http_port \
  $ip \
  $next_http_port)"
fi

echo
echo
echo $0: info: waiting for elasticsearch ingest container to pass consul check
echo $0: info: checking with:
echo curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing \| jq -jr \''.[] | .Service | .Address + ":" + "\(.Port)" + "\n"'\' \| grep -q $next_http_port
until curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + "\n"' | grep -q $next_http_port; do
  echo -n .
  sleep 0.1
done
echo
echo -n $0: info: check passed:\ 
curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + "\n"' | grep $next_http_port

# set elasticsearch host
elasticsearch_host=$ip
elasticsearch_port=$next_http_port

# set elasticsearch hosts
elasticsearch_hosts='["'$elasticsearch_host':'$elasticsearch_port'"]'





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
  --label $name \
  -e LS_HEAP_SIZE=2048m \
  -v /pai-logs:/pai-logs \
  -v $directory/logstash/elasticsearch-template.json:/opt/logstash/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch-2.7.1-java/lib/logstash/outputs/elasticsearch/elasticsearch-template.json \
  -v $directory/logstash/containers/$next_container/config:/config \
  -v $directory/logstash/logstash.yml:/etc/logstash/logstash.yml:ro \
  -v $directory_data/logstash/$next_container/data:/usr/share/logstash/data \
  logstash \
  -f /config/
"
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
