#!/bin/bash

# leonstrand@gmail.com


echo
echo

elasticsearch_indices_path=/elk
directory=$(pwd)

# determine container name
name='elasticsearch-data-ingest'
label='elasticsearch'
last_container=$(docker ps -af name=${name} | grep -v CONTAINER | awk '{print $NF}' | sort -V | tail -1)
if [ -z "$last_container" ]; then
  next_container=${name}-1
else
  next_container=${name}-$(expr $(echo $last_container | awk 'BEGIN { FS = "-" } ; { print $NF }') + 1)
fi
echo $0: info: container name: $next_container

# determine ip address
ip=$(ip -o -4 address | awk '$2 !~ /lo|docker/ {print $4}' | head -1 | cut -d/ -f1)
echo $0: info: network publish host: $ip

# select next free http port over $base_port
base_port=10000
last_http_port=$(for i in $(docker ps -qf name=$label); do docker port $i | awk '/^9200/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_http_port" ]; then
  next_http_port=$(expr $base_port + 9200 + 1)
else
  next_http_port=$(expr $last_http_port + 1)
fi
echo $0: info: http port: $next_http_port

# select next free transport port over $base_port
last_transport_port=$(for i in $(docker ps -qf name=$label); do docker port $i | awk '/^9300/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_transport_port" ]; then
  next_transport_port=$(expr $base_port + 9300 + 1)
else
  next_transport_port=$(expr $last_transport_port + 1)
fi
echo $0: info: transport port: $next_transport_port

# consul discovery of any existing elasticsearch nodes
unicast_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-transport?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + ","' | sed 's/,$//')
if [ -n "$unicast_hosts" ]; then
  echo $0: info: live elasticsearch nodes:
  echo $unicast_hosts | tr , \\n
else
  echo $0: info: no live elasticsearch nodes, setting unicast hosts to self
  unicast_hosts=$ip':'$next_transport_port
fi

# prepare indices directory
echo
echo
echo $0: info: preparing indices directory in $elasticsearch_indices_path
[ -d $elasticsearch_indices_path/elasticsearch/$next_container ] && echo rm -fr $elasticsearch_indices_path/elasticsearch/$next_container && rm -fr $elasticsearch_indices_path/elasticsearch/$next_container
mkdir -vp $elasticsearch_indices_path/elasticsearch/$next_container/data

#-Des.logger.level=DEBUG
echo
echo
echo $0: info: starting container $next_container
command="
docker run -d
  --name $next_container
  --label $label
  -p $next_http_port:9200
  -p $next_transport_port:9300
  -v $elasticsearch_indices_path/elasticsearch/$next_container/data:/usr/share/elasticsearch/data
  -v $directory/elasticsearch/jvm.options:/etc/elasticsearch/jvm.options:ro
  elasticsearch
  -Enetwork.bind_host=0.0.0.0
  -Enetwork.publish_host=$ip
  -Ehttp.publish_host=$ip
  -Enode.name=$(hostname)-$next_container
  -Ecluster.name=elasticsearch-mede
  -Ehttp.publish_port=$next_http_port
  -Etransport.publish_port=$next_transport_port
  -Ediscovery.zen.ping.unicast.hosts=$unicast_hosts
  -Eindex.codec=best_compression
  -Enode.master=false
  -Enode.data=true
  -Enode.ingest=true
"
  #-Ediscovery.zen.minimum_master_nodes=2
echo $0: info: command:
echo $command
result=$(eval $command)
echo $0: info: result: $result
echo
echo docker ps -f name=$next_container
docker ps -f name=$next_container
echo
echo netstat -lnt \| egrep \''Active|Proto|'$next_http_port\'
netstat -lnt | egrep 'Active|Proto|'$next_http_port
echo
echo $0: info: waiting for $next_container container to respond on http port $next_http_port with status 200
echo curl $ip:$next_http_port
until curl $ip:$next_http_port 1>/dev/null 2>&1; do
  sleep 1
done
curl $ip:$next_http_port

# consul registration
echo
echo
if curl $ip:$next_http_port 1>/dev/null 2>&1; then
  CONSUL_IP=$ip
  CONSUL_PORT=8500

  # register es transport
  echo $0: info: registering elasticsearch transport service with consul
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
  echo $0: info: registering elasticsearch http service with consul
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

  # register es http data ingest
  echo
  echo $0: info: registering elasticsearch http data ingest service with consul
  echo curl -v --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf \''{
    "ID":"%s",
    "Name":"elasticsearch-http-data-ingest",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }'\' \
  elasticsearch-http-data-ingest-$ip:$next_http_port \
  $ip \
  $next_http_port \
  $ip \
  $next_http_port)"

  curl -v --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf '{
    "ID":"%s",
    "Name":"elasticsearch-http-data-ingest",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }' \
  elasticsearch-http-data-ingest-$ip:$next_http_port \
  $ip \
  $next_http_port \
  $ip \
  $next_http_port)"
fi

echo
echo
echo $0: info: running containers labeled $name
echo docker ps -f label=$name
docker ps -f label=$name
echo
