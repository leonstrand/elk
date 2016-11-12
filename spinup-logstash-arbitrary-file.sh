#!/bin/bash

# leonstrand@gmail.com


# set initial variables
directory=$(pwd)
echo $0: debug: file: $file
if [ -z "$1" ] || [ -n "$2" ]; then
  echo $0: fatal: must specify one and only one file
  exit 1
fi
file="$1"
if [ -z "$file" ]; then
  echo $0: fatal: must specify file
  exit 1
fi
if [ ! -f "$file" ]; then
  echo $0: fatal: $file is not a file
  exit 1
fi
if [ ! -s "$file" ]; then
  echo $0: fatal: $file has no size
  exit 1
fi

# generate unique logstash container name
name='logstash-arbitrary-file-'"$(date '+%N')"
until [ -z "$(docker ps -q -f name=$name)" ]; do
  name='logstash-arbitrary-file-'"$(date '+%N')"
done
echo $0: debug: name: $name

# determine ip address
ip=$(ip -o -4 address | awk '$2 !~ /lo|docker/ {print $4}' | head -1 | cut -d/ -f1)
echo $0: debug: ip: $ip

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
echo $0: debug: elasticsearch_hosts: $elasticsearch_hosts

# configure logstash
echo
echo
echo $0: info: configuring logstash
[ -d $directory/logstash/containers/$name ] && rm -rv $directory/logstash/containers/$name
mkdir -vp $directory/logstash/containers/$name
cp -vr $directory/logstash/config $directory/logstash/containers/$name
echo
echo $0: info: configuring logstash input
echo $0: info: logstash configuration file: $directory/logstash/containers/$name/config/100-input-logstash.conf
sed 's|REPLACE_FILE|'$file'|' $directory/logstash/template/100-input-logstash-arbitrary-file.conf  | tee $directory/logstash/containers/$name/config/100-input-logstash-arbitrary-file.conf
echo
echo $0: info: configuring logstash output
echo $0: info: logstash configuration file: $directory/logstash/containers/$name/config/300-output-logstash.conf
sed 's/REPLACE/'$elasticsearch_hosts'/' $directory/logstash/template/300-output-logstash.conf | tee $directory/logstash/containers/$name/config/300-output-logstash.conf

# spin up logstash container
echo
echo
echo $0: info: starting container $name
command="
docker run -d \
  --name $name \
  -e LS_HEAP_SIZE=4096m \
  -v /pai-logs:/pai-logs:ro \
  -v $directory/logstash/elasticsearch-template.json:/opt/logstash/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch-2.7.1-java/lib/logstash/outputs/elasticsearch/elasticsearch-template.json:ro \
  -v $directory/logstash/containers/$name/config:/config:ro \
  logstash \
  -f /config/ \
  --debug \
  --auto-reload
"
echo $0: info: command:
echo $command
result=$(eval $command)
echo $0: info: result: $result

# show docker container
echo
echo
echo docker ps -f name=$name
docker ps -f name=$name

# watch for event submission, exit if none in last five minutes
echo
echo
check_start_threshold=1000000
check_threshold=1000
loop_threshold=1000000
timestamp_difference_threshold=300
loop=0
echo $0: info: $name status: waiting for pipeline start
until docker logs $name | grep ':message=>"starting pipeline",'; do
  loop=$(expr $loop + 1)
  echo $0: debug: docker container $name starting pipeline loop $loop
done
while [ $loop -lt $loop_threshold ]; do
  echo
  echo
  # :message=>"starting pipeline",
  loop=$(expr $loop + 1)
  for check in $(seq $check_threshold); do
    echo $0: debug: check: $check
    event="$(docker logs --details --timestamps --tail 1000 $name | grep ':message=>"Event now: ",' | tail -1)"
    [ -n "$event" ] && break
  done
  echo $0: debug: event: $event
  timestamp="$(echo $event | awk '{print $1}')"
  echo $0: debug: timestamp: $timestamp
  timestamp_event="$(date --date $timestamp '+%s')"
  timestamp_now="$(date '+%s')"
  echo $0: debug: timestamp_event: $timestamp_event
  echo $0: debug: timestamp_now: $timestamp_now
  timestamp_difference=$(expr $timestamp_now - $timestamp_event)
  echo $0: debug: timestamp_difference: $timestamp_difference
  if [ $timestamp_difference -ge $timestamp_difference_threshold ]; then
    echo $0: debug: $timestamp_difference greater than or equal to $timestamp_difference_threshold
    break
  fi
  echo sleep 5
  sleep 5
done

# stop docker container
echo
echo
echo docker stop $name
docker stop $name

# remove docker container
echo
echo
echo docker rm $name
docker rm $name
echo
