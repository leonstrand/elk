#!/bin/bash

# leonstrand@gmail.com


name='kibana'
directory=$(pwd)
name_elasticsearch='elasticsearch'
elasticsearch_cluster_name='elasticsearch-mede'


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
echo $0: info: kibana container name: $next_container
echo $0: info: elasticsearch load balancer container name: $next_container_elasticsearch_loadbalancer

# identify ip address
ip=$(ip -o -4 address | awk '$2 !~ /lo|docker/ {print $4}' | head -1 | cut -d/ -f1)
echo $0: info: elasticsearch load balancer network publish host: $ip

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
echo $0: info: starting container $next_container_elasticsearch_loadbalancer
command="
docker run -d \
  --name $next_container_elasticsearch_loadbalancer \
  -p $next_http_port:9200 \
  -p $next_transport_port:9300 \
  elasticsearch \
  -Enetwork.host=0.0.0.0 \
  -Enode.name=$(hostname)-$next_container_elasticsearch_loadbalancer \
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
echo $0: info: waiting for $next_container_elasticsearch_loadbalancer container on http port $next_http_port to respond with status 200
echo docker ps -f name=$next_container_elasticsearch_loadbalancer
docker ps -f name=$next_container_elasticsearch_loadbalancer
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
echo
echo $0: info: waiting for elasticsearch load balancer container to pass consul check
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

# configure kibana
echo
echo
echo $0: info: configuring kibana
[ -d $directory/kibana/containers ] || mkdir -vp $directory/kibana/containers
[ -d $directory/kibana/containers/$next_container ] && rm -rv $directory/kibana/containers/$next_container
cp -vr $directory/kibana/template $directory/kibana/containers/$next_container
find $directory/kibana/containers/$next_container -type f -exec sed -i 's/REPLACE_ELASTICSEARCH_HOST/'$elasticsearch_host'/g' {} \;
find $directory/kibana/containers/$next_container -type f -exec sed -i 's/REPLACE_ELASTICSEARCH_PORT/'$elasticsearch_port'/g' {} \;
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
