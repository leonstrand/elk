#!/bin/bash

# leonstrand@gmail.com


name='logstash'
directory=$(pwd)
directory_logs=/pai-logs

# determine ip address
ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)
service_name='logstash'


echo

# get list of server log directories
echo
echo $0: getting list of log directories, one per server
servers=$(find $directory_logs -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)
echo $0: servers: $servers

# get list of passing logstash service ids
echo
echo $0: getting list of passing logstash service ids
echo curl -sS http://$ip:8500/v1/health/service/$service_name?passing \| jq -r \''.[] .Service | .ID'\'
service_ids=$(curl -sS http://$ip:8500/v1/health/service/$service_name?passing | jq -r '.[] .Service | .ID')
echo service_ids: $service_ids

# handle first unhandled server
echo
echo $0: seeking first unhandled server
handled=0
for server in $servers; do
  echo -n $0: server: $server\ 
  # check consul to see if server not handled
  if [[ $service_ids != *$server* ]]; then
    echo not already handled
    # determine container name
    echo
    echo $0: determining container name
    last_container=$(docker ps -af name=${name}- | grep -v CONTAINER | awk '{print $NF}' | sort | tail -1)
    if [ -z "$last_container" ]; then
      next_container=${name}-1
    else
      next_container=${name}-$(expr $(echo $last_container | awk 'BEGIN { FS = "-" } ; { print $NF }') + 1)
    fi
    echo next_container: $next_container

    # discover elasticsearch nodes passing consul check
    echo
    echo $0: discovering elasticsearch nodes passing consul check
    echo curl -sS $ip:8500/v1/catalog/service/elasticsearch-http?passing
    #elasticsearch_hosts=$(curl -sS $ip:8500/v1/catalog/service/elasticsearch-http | jq -jr '.[] | "\"" + .ServiceAddress + ":" + "\(.ServicePort)" + "\","' | sed 's/,$//')
    elasticsearch_hosts=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | "\"" + .Address + ":" + "\(.Port)" + "\","' | sed 's/,$//')
    if [ -z "$elasticsearch_hosts" ]; then
      echo $0: fatal: could not find any elasticsearch host
      exit 1
    fi
    elasticsearch_hosts='['$elasticsearch_hosts']'
    echo elasticsearch_hosts: $elasticsearch_hosts

    # configure logstash
    echo
    echo $0: configuring logstash
    [ -d $directory/logstash/containers/$next_container ] && rm -rv $directory/logstash/containers/$next_container
    mkdir -vp $directory/logstash/containers/$next_container
    cp -vr $directory/logstash/config $directory/logstash/containers/$next_container
    echo $0: configuring logstash input
    sed 's/REPLACE_SERVER/'$server'/' logstash/template/100-input-logstash.conf  | tee $directory/logstash/containers/$next_container/config/100-input-logstash.conf
    echo $0: configuring logstash output
    sed 's/REPLACE/'$elasticsearch_hosts'/' logstash/template/300-output-logstash.conf | tee $directory/logstash/containers/$next_container/config/300-output-logstash.conf
    echo $0: configuring logstash heartbeat
    sed 's/REPLACE_CONSUL_HOST/'$ip'/' logstash/template/400-heartbeat-logstash.conf > $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf
    sed -i 's/REPLACE_LOGSTASH_SERVER/'$server'/' $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf
    cat $directory/logstash/containers/$next_container/config/400-heartbeat-logstash.conf

      #-v $directory/logstash/containers/$next_container/config:/etc/logstash/conf.d \
    # spin up logstash container
    echo
    echo $0: spinning up logstash container
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

    # register logstash
    echo
    echo $0: registering logstash
    echo curl -v -X PUT http://192.168.1.167:8500/v1/agent/service/register \
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
      $ip)
    "
    curl -v -X PUT http://192.168.1.167:8500/v1/agent/service/register \
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
      $name \
      $server \
      $ip)
    "
    handled=1
    break
  else
    echo already handled
  fi
done
if [ $handled -eq 0 ]; then
  echo $0: info: nothing to handle
fi

echo
docker ps -f name=$name
echo
