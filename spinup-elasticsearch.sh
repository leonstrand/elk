#!/bin/bash

# leonstrand@gmail.com


#name='elasticsearch_loadbalancer_'
#name='eslb'
name='es'
last_container=$(docker ps -f name=${name}- | grep -v CONTAINER | awk '{print $NF}' | sort | tail -1)
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
unicast_hosts=$(curl -sS 192.168.1.167:8500/v1/catalog/service/elasticsearch | jq -jr '.[] | .ServiceAddress + ":" + "\(.ServicePort)" + ","' | sed 's/,$//')
echo unicast_hosts: $unicast_hosts
if [ -z "$unicast_hosts" ]; then
  unicast_hosts=$ip':'$next_transport_port
fi

#-Des.logger.level=DEBUG
command="
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
  -Des.discovery.zen.ping.multicast.enabled=false \
  -Des.discovery.zen.ping.unicast.hosts=$unicast_hosts
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

  #curl -f --retry 7 --retry-delay 3 \
  #http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  #-d "$(printf '{"ID":"%s","Name":"elasticsearch","Address":"%s","Port":%s, "Check":{"HTTP": "http://%s:%s", "Interval": "10s"}}' $next_container $PRIVATE_IP $PRIVATE_PORT $PRIVATE_IP $PRIVATE_PORT)"

  #"deregister_critical_service_after": "1m"
  echo curl -f --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf '{
    "ID":"%s",
    "Name":"elasticsearch",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }' $next_container $ip $next_transport_port $ip $next_http_port)"

  curl -f --retry 7 --retry-delay 3 \
  http://$CONSUL_IP:$CONSUL_PORT/v1/agent/service/register \
  -d "$(printf '{
    "ID":"%s",
    "Node":"%s",
    "Name":"elasticsearch",
    "Address":"%s",
    "Port":%s,
    "Check":{
      "HTTP": "http://%s:%s",
      "Interval": "10s"
    }
  }' $next_container $next_container $ip $next_transport_port $ip $next_http_port)"
fi
