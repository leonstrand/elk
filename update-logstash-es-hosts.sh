#!/bin/bash

# leonstrand@gmail.com


directory=$(pwd)
ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)
echo $0: ip: $ip
elasticsearch_hosts=$(echo -n \[; curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[] | .Service | "\"" + .Address + ":" + "\(.Port)" + "\","' | sed 's/,$//'; echo -n ])
echo $0: elasticsearch_hosts: $elasticsearch_hosts
find $directory/logstash/containers -type f -name '*output*logstash*' -exec sed -i 's/\(\s*hosts\s*=>\s*\).*$/\1'$elasticsearch_hosts'/' {} \;
find $directory/logstash/containers -type f -name '*output*logstash*' -exec grep -Hin hosts {} \;
