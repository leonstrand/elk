#!/bin/bash

# leonstrand@gmail.com


name='kibana'
directory=$(pwd)
name_elasticsearch='elasticsearch'


echo
echo
# determine container name
last_container=$(docker ps -af name=${name}- | grep -v CONTAINER | awk '{print $NF}' | sort | tail -1)
if [ -z "$last_container" ]; then
  next_container=${name}-1
else
  next_container=${name}-$(expr $(echo $last_container | awk 'BEGIN { FS = "-" } ; { print $NF }') + 1)
fi
next_container_elasticsearch_loadbalancer=$next_container'-elasticsearch-loadbalancer'
echo next_container: $next_container
echo next_container_elasticsearch_loadbalancer: $next_container_elasticsearch_loadbalancer

# identify ip address
ip=$(ip -o -4 address | awk '$2 !~ /lo|docker/ {print $4}' | head -1 | cut -d/ -f1)
echo ip: $ip

# select next free http port over $base_port
base_port=10000
last_http_port=$(for i in $(docker ps -qf name=$name_elasticsearch); do docker port $i | awk '/^9200/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_http_port" ]; then
  next_http_port=$(expr $base_port + 9200 + 1)
else
  next_http_port=$(expr $last_http_port + 1)
fi
echo next_http_port: $next_http_port
# TODO open port check

# select next free transport port over $base_port
last_transport_port=$(for i in $(docker ps -qf name=$name_elasticsearch); do docker port $i | awk '/^9300/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_transport_port" ]; then
  next_transport_port=$(expr $base_port + 9300 + 1)
else
  next_transport_port=$(expr $last_transport_port + 1)
fi
echo next_transport_port: $next_transport_port
# TODO open port check

# discover responsive elasticsearch nodes
unicast_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-transport?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + ","' | sed 's/,$//')
echo unicast_hosts: $unicast_hosts
if [ -z "$unicast_hosts" ]; then
  unicast_hosts=$ip':'$next_transport_port
fi

#-Des.logger.level=DEBUG
echo
echo
echo $0: info starting container $next_container_elasticsearch_loadbalancer
command="
docker run -d \
  --name $next_container_elasticsearch_loadbalancer \
  -p $next_http_port:9200 \
  -p $next_transport_port:9300 \
  elasticsearch \
  -Dnetwork.host=0.0.0.0 \
  -Des.node.name=$(hostname)-$next_container_elasticsearch_loadbalancer \
  -Des.node.master=false \
  -Des.node.data=false \
  -Des.cluster.name=elasticsearch-pai \
  -Dnetwork.publish_host=$ip \
  -Dhttp.publish_port=$next_http_port \
  -Dtransport.publish_port=$next_transport_port \
  -Des.discovery.zen.ping.multicast.enabled=false \
  -Des.discovery.zen.ping.unicast.hosts=$unicast_hosts \
  -Dindex.codec=best_compression
"
echo $0: info: command:
echo $command
result=$(eval $command)
echo $0: info: result: $result

# consul registration
echo
echo
until curl $ip:$next_http_port 1>/dev/null 2>&1; do
  #echo -n .
  echo
  echo
  docker ps -f name=$name
  echo
  netstat -lnt | egrep 'Active|Proto|$next_http_port'
  #sleep 0.2
  sleep 1
done

echo
if curl $ip:$next_http_port 1>/dev/null 2>&1; then
  CONSUL_IP=$ip
  CONSUL_PORT=8500

  # register es transport
  echo $0: info: registering elasticsearch load balancer transport service with consul
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
  echo $0: info: registering elasticsearch load balancer http service with consul
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
echo $0: elasticsearch http nodes:
until curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + "\n"' | grep -q $next_http_port; do
  sleep 0.1
done
curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + "\n"'

echo
# identify elasticsearch host
#elasticsearch_host=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -r '.[0] | .Service | .Address + ":" + "\(.Port)"')
elasticsearch_host=$ip
#elasticsearch_port=$(docker inspect kb-1-elasticsearch-loadbalancer | grep http.publish_port | head -1 | cut -d= -f2 | tr -d '",')
elasticsearch_port=$next_http_port
echo elasticsearch host: $elasticsearch_host:$elasticsearch_port

# configure kibana build
[ -d $directory/kibana/containers ] || mkdir -vp $directory/kibana/containers
[ -d $directory/kibana/containers/$next_container ] && rm -rv $directory/kibana/containers/$next_container
cp -vr $directory/kibana/template $directory/kibana/containers/$next_container
#cp -v $directory/kibana/template/kibana.yml $directory/kibana/containers/$next_container/config
find $directory/kibana/containers/$next_container -type f -exec sed -i 's/REPLACE_ELASTICSEARCH_HOST/'$elasticsearch_host'/g' {} \;
find $directory/kibana/containers/$next_container -type f -exec sed -i 's/REPLACE_ELASTICSEARCH_PORT/'$elasticsearch_port'/g' {} \;
# send this to build
#sed 's/REPLACE_KIBANA_CONTAINER/'$next_container'/' $directory/docker-compose-kibana-template.yml >$directory/docker-compose.yml
echo sed -i \''s/REPLACE_KIBANA_CONTAINER/'$next_container'/'\' $directory/kibana/containers/$next_container/docker-compose.yml
sed -i 's/REPLACE_KIBANA_CONTAINER/'$next_container'/' $directory/kibana/containers/$next_container/docker-compose.yml

# start kibana
echo
echo
echo $0: info: starting container $next_container
command="cd $directory/kibana/containers/$next_container && docker-compose up --build -d"
echo $0: info: command:
echo $command
eval $command

cd $directory

echo
echo
echo $0: info: docker ps -f name=$name
docker ps -f name=$name
echo
