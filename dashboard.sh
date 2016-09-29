#!/bin/bash

# leon.strand@medeanalytics.com


log_directory=/pai-logs


ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ {print $4}' | cut -d/ -f1)
if [ -z "$ip" ]; then
  echo $0: fatal: could not determine self ip address with:
  echo ip -o address \| awk \'\$2 !\~ /lo\|docker/ \&\& \$3 \~ /inet$/ {print \$4}\' \| cut -d/ -f1
  exit 1
fi
address=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[0] | .Service | "\(.Address)"')
if [ -z "$address" ]; then
  echo $0: fatal: could not find a live elasticsearch node with:
  echo curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing \| jq -jr \''.[0] | .Service | "\(.Address)"'\'
  exit 1
fi
port=$(curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing | jq -jr '.[0] | .Service | "\(.Port)"')
if [ -z "$port" ]; then
  echo $0: fatal: could not find port associated with a live elasticsearch node with:
  echo curl -sS $ip:8500/v1/health/service/elasticsearch-http?passing \| jq -jr \''.[0] | .Service | "\(.Port)"'\'
  exit 1
fi
if ! nc -w1 $address $port </dev/null; then
  echo $0: fatal: could not connect to elasticsearch at $address:$port
  exit 1
fi


execute() {
  echo $@
  eval $@
}

command='curl -sS '$address':'$port'/_cat/indices?v | sort -k3'
execute $command

docs_count=$(curl -sS $address:$port/_cat/indices?v | egrep -v 'health|kibana' | awk '{sum += $6} END {print sum}')
docs_deleted=$(curl -sS $address:$port/_cat/indices?v | egrep -v 'health|kibana' | awk '{sum += $7} END {print sum}')
printf '%s %19s %12s\n' 'total documents excluding kibana' $docs_count $docs_deleted


echo
echo $0: storage usage
echo -e index\\t\\t\\tes\\tfile
while read index size; do
  index_elasticsearch=$index
  index=$(echo $index | cut -d- -f2)
  index=$(echo $index | sed 's/\.//g')
  size_file=$(du -csh $(find /pai-logs -type f -name \*$index\*) | grep total | awk '{print $1}')
  echo -e $index_elasticsearch\\t$size\\t$size_file
done < <(curl -sS $address:$port/_cat/indices?v | grep logstash | awk '{print $3, $NF}' | sort)


echo
command='curl -sS '$address':'$port'/_cluster/state/version,master_node?pretty'
execute $command

echo
echo $0: elasticsearch cluster nodes
echo -e 'ip address\tport\trole'
master_node=$(curl -sS $address:$port/_cluster/state/master_node?pretty | grep master_node | awk '{print $NF}' | tr -d \")
elasticsearch_nodes=$(curl -sS $address:$port/_nodes/_all/http_address?pretty | grep -B1 '"name"' | egrep -v '"name"|^--' | awk '{print $1}' | tr -d \")
for elasticsearch_node in $elasticsearch_nodes; do
  http_address=$(curl -sS $address:$port/_nodes/$elasticsearch_node/http_address?pretty | grep '"http_address"' | awk '{print $NF}' | tr -d '",')
  node_ip=$(echo $http_address | cut -d: -f1)
  node_port=$(echo $http_address | cut -d: -f2)
  role=
  if [ "$master_node" == "$elasticsearch_node" ]; then
    role='master, data'
  else
    if curl -sS $address:$port/_nodes/$elasticsearch_node/http_address?pretty | grep -A2 '"attributes"' | grep -v attributes | grep -q '"data" : "false"'; then
      if curl -sS $address:$port/_nodes/$elasticsearch_node/http_address?pretty | grep -A2 '"attributes"' | grep -v attributes | grep -q '"master" : "false"'; then
        role='loadbalancer'
      fi
    else
      role='data'
    fi
  fi
  echo -e $node_ip'\t'$node_port'\t'$role
#done | sort -V
done

echo
echo $0: log directory handling
log_directories=$(find $log_directory -mindepth 1 -maxdepth 1 -type d | sort)
echo -e directory\\t\\tserver\\t\\tstatus
for log_directory in $log_directories; do
  echo -en $log_directory\\t
  #curl -sS http://$ip:8500/v1/health/checks/logstash | jq -r '.[] | select(.ServiceID=="'$(basename $log_directory)'") | .Node + "\t" + .Status'
  status=$(curl -sS http://$ip:8500/v1/health/checks/logstash | jq -r '.[] | select(.ServiceID=="'$(basename $log_directory)'") | select(.Status=="passing") | .Node + "\t" + .Status')
  if [ -n "$status" ]; then
    curl -sS http://$ip:8500/v1/health/checks/logstash | jq -r '.[] | select(.ServiceID=="'$(basename $log_directory)'") | select(.Status=="passing") | .Node + "\t" + .Status'
  else
    echo -e unknown\\t\\tunknown
  fi
done
