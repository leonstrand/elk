#!/bin/bash

# leonstrand@gmail.com


name='elasticsearch'
heap_size='1g'
last_container=$(docker ps -af label=${name} | grep -v CONTAINER | awk '{print $NF}' | sort | tail -1)
if [ -z "$last_container" ]; then
  next_container=${name}-1
else
  next_container=${name}-$(expr $(echo $last_container | awk 'BEGIN { FS = "-" } ; { print $NF }') + 1)
fi
echo next_container: $next_container


# determine ip address
ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)

# select next free http port over $base_port
base_port=10000
last_http_port=$(for i in $(docker ps -qf name=$name); do docker port $i | awk '/^9200/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_http_port" ]; then
  next_http_port=$(expr $base_port + 9200 + 1)
else
  next_http_port=$(expr $last_http_port + 1)
fi
echo next_http_port: $next_http_port

# select next free transport port over $base_port
last_transport_port=$(for i in $(docker ps -qf name=$name); do docker port $i | awk '/^9300/ {print $NF}' | cut -d: -f2; done | sort -n | tail -1)
if [ -z "$last_transport_port" ]; then
  next_transport_port=$(expr $base_port + 9300 + 1)
else
  next_transport_port=$(expr $last_transport_port + 1)
fi
echo next_transport_port: $next_transport_port

# consul discovery of any existing elasticsearch nodes
unicast_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-transport?passing | jq -jr '.[] | .Service | .Address + ":" + "\(.Port)" + ","' | sed 's/,$//')
echo unicast_hosts: $unicast_hosts
if [ -z "$unicast_hosts" ]; then
  unicast_hosts=$ip':'$next_transport_port
fi

#-Des.logger.level=DEBUG
command="
docker run -d \
  --name $next_container \
  --label $name \
  -p $next_http_port:9200 \
  -p $next_transport_port:9300 \
  -e ES_HEAP_SIZE=$heap_size
  elasticsearch \
  -Dnetwork.host=0.0.0.0 \
  -Des.node.name=$(hostname)-$next_container \
  -Des.cluster.name=elasticsearch-pai \
  -Dnetwork.publish_host=$ip \
  -Dhttp.publish_port=$next_http_port \
  -Dtransport.publish_port=$next_transport_port \
  -Des.discovery.zen.ping.multicast.enabled=false \
  -Des.discovery.zen.ping.unicast.hosts=$unicast_hosts \
  -Dindex.codec=best_compression
"
  #-Des.node.master=false \
  #-Des.node.data=false \
echo command: $command
result=$(eval $command)
echo result: $result


# consul registration
echo
echo
until curl $ip:$next_http_port 1>/dev/null 2>&1; do
  #echo -n .
  echo
  echo
  docker ps -f label=$name
  echo
  netstat -lnt | egrep 'Active|Proto|$next_http_port'
  #sleep 0.2
  sleep 1
done
echo
if curl $ip:$next_http_port 1>/dev/null 2>&1; then
  CONSUL_IP=$ip
  CONSUL_PORT=8500

  #curl -f --retry 7 --retry-delay 3 \
  #http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  #-d "$(printf '{"ID":"%s","Name":"elasticsearch","Address":"%s","Port":%s, "Check":{"HTTP": "http://%s:%s", "Interval": "10s"}}' $next_container $PRIVATE_IP $PRIVATE_PORT $PRIVATE_IP $PRIVATE_PORT)"

  # register es transport
  echo curl -f --retry 7 --retry-delay 3 \
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
  $next_http_port)
  "

  curl -f --retry 7 --retry-delay 3 \
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
  $next_http_port)
  "

  # register es http
  echo curl -f --retry 7 --retry-delay 3 \
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
  $next_http_port)
  "

  curl -f --retry 7 --retry-delay 3 \
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
  $next_http_port)
  "

fi

echo
docker ps -f label=$name
echo
echo
