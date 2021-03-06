#!/bin/bash

# leon.strand@medeanalytics.com


log_directory=/pai-logs
consul_service_name='logstash-pai'


ip=$(ip -o address | awk '$2 !~ /lo|docker/ && $3 ~ /inet$/ && $4 !~ /^169/ {print $4}' | cut -d/ -f1)
if [ -z "$ip" ]; then
  echo $0: fatal: could not determine self ip address with:
  echo ip -o address \| awk \'\$2 !\~ /lo\|docker/ \&\& \$3 \~ /inet$/ {print \$4}\' \| cut -d/ -f1
  exit 1
fi


status="$(curl -sS http://$ip:8500/v1/health/checks/$consul_service_name 2>/dev/null)"
case "$status" in
  'No cluster leader'|'')
    echo $0: fatal: status: $status
    echo $0: fatal: attempted status check with:
    echo curl -sS http://$ip:8500/v1/health/checks/$consul_service_name
    exit 1
  ;;
  *)
    echo
    echo $0: log directory handling
    log_directories=$(find $log_directory -mindepth 1 -maxdepth 1 -type d | sort)
    echo -e directory\\t\\tserver\\t\\tstatus
    for log_directory in $log_directories; do
    echo -en $log_directory\\t
    status=$(curl -sS http://$ip:8500/v1/health/checks/$consul_service_name | jq -r '.[] | select(.ServiceID=="'$(basename $log_directory)'") | select(.Status=="passing") | .Node + "\t" + .Status')
    if [ -n "$status" ]; then
      curl -sS http://$ip:8500/v1/health/checks/$consul_service_name | jq -r '.[] | select(.ServiceID=="'$(basename $log_directory)'") | select(.Status=="passing") | .Node + "\t" + .Status'
    else
      echo -e unknown\\t\\tunknown
    fi
    done
  ;;
esac
