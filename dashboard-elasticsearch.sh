#!/bin/bash

# leon.strand@medeanalytics.com


log_directory=/pai-logs


ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ && $4 !~ /^169/ {print $4}' | cut -d/ -f1)
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

tmp=/tmp/dashboard.sh.indices
echo curl -sS $address:$port/_cat/indices?v
curl -sS $ip:19201/_cat/indices?v >$tmp
grep health $tmp >$tmp-reorder
awk '$2 ~ /open/' $tmp | sort -V >>$tmp-reorder
awk '$1 ~ /close/' $tmp | sort -V >>$tmp-reorder
mv $tmp-reorder $tmp

docs_count=$(egrep -v 'health|kibana' $tmp | awk '{sum += $6} END {print sum}')
docs_deleted=$(egrep -v 'health|kibana' $tmp | awk '{sum += $7} END {print sum}')
printf '%s %19s %12s\n' 'total documents excluding kibana' $docs_count $docs_deleted >>$tmp

sed -i 's/\(^health.*$\)/\1\tfile.size/' $tmp


# exclude unresponsively mounted servers from file size check
exclude=''
exclude_prefix='-type d -path'
exclude_suffix='-prune -o'
servers=$(find $log_directory -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
for server in $servers; do
  if [ -z "$(find $log_directory/$server -type f | head -1)" ]; then
    exclude="$exclude $exclude_prefix $log_directory/$server $exclude_suffix"
  fi
done
exclude="$(echo $exclude | sed 's/^\s*//')"

while read index size; do
  index_elasticsearch=$index
  index=$(echo $index | cut -d- -f2)
  index=$(echo $index | sed 's/\.//g')
  size_file=$(du -csh $(find $log_directory $exclude -type f -name \*$index\* -print) | grep total | awk '{print $1}')
  sed -i 's/\(^.*'$index_elasticsearch'.*$\)/\1\t'$size_file'/' $tmp
done < <(curl -sS $address:$port/_cat/indices?v | grep logstash | awk '{print $3, $NF}' | sort)
cat $tmp


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
done | sort -V
