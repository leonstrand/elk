#!/bin/bash

# leonstrand@gmail.com


name='kb'
directory=$(pwd)

# determine container name
last_container=$(docker ps -af name=${name}- | grep -v CONTAINER | awk '{print $NF}' | sort | tail -1)
if [ -z "$last_container" ]; then
  next_container=${name}-1
else
  next_container=${name}-$(expr $(echo $last_container | awk 'BEGIN { FS = "-" } ; { print $NF }') + 1)
fi
echo next_container: $next_container


# identify ip address
ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)
echo ip: $ip

# identify elasticsearch host
elasticsearch_host=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -r '.[0] | .Service | .Address + ":" + "\(.Port)"')
if [ -z "$elasticsearch_host" ]; then
  echo $0: fatal: no elasticsearch host found
  exit 1
fi
elasticsearch_port=$(echo $elasticsearch_host | cut -d: -f2)
elasticsearch_host=$(echo $elasticsearch_host | cut -d: -f1)
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
echo sed -i 's/REPLACE_KIBANA_CONTAINER/'$next_container'/' $directory/kibana/containers/$next_container/docker-compose.yml
sed -i 's/REPLACE_KIBANA_CONTAINER/'$next_container'/' $directory/kibana/containers/$next_container/docker-compose.yml

# start kibana
command="cd $directory/kibana/containers/$next_container && time docker-compose up -d"
echo $command
eval $command

cd $directory

echo
docker ps -f name=$name
echo
echo
