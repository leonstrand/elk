#!/bin/bash

# leonstrand@gmail.com


echo
echo
echo

# set initial variables
directory=$(pwd)
if [ -z "$1" ] || [ -n "$2" ]; then
  echo $0: fatal: must specify one and only one directory
  exit 1
fi
target_directory="$1"
echo -n $0: debug: target_directory:\ 
ls -alhd $target_directory
if [ ! -d "$target_directory" ]; then
  echo $0: fatal: $target_directory is not a directory
  exit 1
fi
directory_data=/elk

# generate unique logstash container name
name='logstash-arbitrary-directory-'"$(date '+%N')"
until [ -z "$(docker ps -q -f name=$name)" ]; do
  name='logstash-arbitrary-directory-'"$(date '+%N')"
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
echo $0: info: logstash configuration file: $directory/logstash/containers/$name/config/100-input-logstash-arbitrary-directory.conf
sed 's|REPLACE_DIRECTORY|'$target_directory'|' $directory/logstash/template/100-input-logstash-arbitrary-directory.conf | tee $directory/logstash/containers/$name/config/100-input-logstash-arbitrary-directory.conf
echo
echo $0: info: configuring logstash output
echo $0: info: logstash configuration file: $directory/logstash/containers/$name/config/300-output-logstash.conf
sed 's/REPLACE/'$elasticsearch_hosts'/' $directory/logstash/template/300-output-logstash.conf | tee $directory/logstash/containers/$name/config/300-output-logstash.conf

# prepare data directory
echo
echo
echo $0: info: preparing data directory
[ -d $directory_data/logstash/$name ] && rm -rv $directory_data/logstash/$name
echo mkdir -vpm 777 $directory_data/logstash/$name/data
mkdir -vpm 777 $directory_data/logstash/$name/data

# spin up logstash container
echo
echo
echo $0: info: starting container $name
  #-e LS_HEAP_SIZE=2048m \
command="
docker run -d \
  --name $name \
  -v /pai-logs:/pai-logs \
  -v $directory/logstash/elasticsearch-template.json:/opt/logstash/vendor/bundle/jruby/1.9/gems/logstash-output-elasticsearch-2.7.1-java/lib/logstash/outputs/elasticsearch/elasticsearch-template.json \
  -v $directory/logstash/containers/$name/config:/config \
  -v $directory/logstash/logstash.yml:/etc/logstash/logstash.yml:ro \
  -v $directory_data/logstash/$name/data:/usr/share/logstash/data \
  logstash \
  -f /config/
"
echo $0: info: command:
echo $command
result=$(eval $command)
echo $0: info: result: $result

echo
echo
docker ps -f name=$name
echo

