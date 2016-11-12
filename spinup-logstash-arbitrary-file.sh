#!/bin/bash

# leonstrand@gmail.com


echo
echo

# set initial variables
directory=$(pwd)
if [ -z "$1" ] || [ -n "$2" ]; then
  echo $0: fatal: must specify one and only one file
  exit 1
fi
file="$1"
echo -n $0: debug: file:\ 
ls -alh $file
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
  --verbose \
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

# watch for pipeline start (processing begin), fail after about five minutes
echo
echo
echo $0: info: $name status: processing begin \(pipeline start\)
loop_threshold_pipeline=300
loop=0
until docker logs $name | grep ':message=>"starting pipeline",'; do
  loop=$(expr $loop + 1)
  if [ $loop -ge $loop_threshold_pipeline ]; then
    echo $0: fatal: loop count $loop equal to or greater than threshold $loop_threshold
    exit 1
  fi
  sleep 1
done
# watch for sincedb file data (processing end), fail after about a day (24 hours * 60 minutes * 60 seconds = 86400 / 5 second check interval = 17280)
echo
echo
echo $0: info: $name status: waiting for processing end \(sincedb has size\)
loop_threshold_sincedb=17280
loop=0
until [ -n "$(docker exec $name find /var/lib/logstash -type f -name '.sincedb_*' -exec cat {} \;)" ]; do
  loop=$(expr $loop + 1)
  if [ $loop -ge $loop_threshold_sincedb ]; then
    echo $0: fatal: loop count $loop equal to or greater than threshold $loop_threshold
    exit 1
  fi
  echo -n .
  sleep 5
done
echo
echo
echo
echo $0: info: $name status: processing end \(sincedb has size\)
echo $(docker exec $name find /var/lib/logstash -type f -name '.sincedb_*'): $(docker exec $name find /var/lib/logstash -type f -name '.sincedb_*' -exec cat {} \;)


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

# remove container files
echo
echo
echo rm -rv $directory/logstash/containers/$name
rm -rv $directory/logstash/containers/$name
echo
