#!/bin/bash

# leonstrand@gmail.com


elasticsearch_host='10.153.13.35'
elasticsearch_port='19206'

#2016-12-14 12:22:55.2948|PAIAPPMV131|5436|44|Info|NServiceBus.Distributor.MSMQ.MsmqWorkerAvailabilityManager|Worker at 'mede.pai.ac.submission.gateway@PAIAPPV143' is available to take on more work.|
pai_path=/pai-logs/PAIAPPMV131/PAI/logs/Mede.Pai.AC.Submission.Gateway.20161214.log
tail_lines=32

#echo
#echo
#echo tail -$tail_lines $pai_path
#tail -$tail_lines $pai_path
tail -$tail_lines $pai_path | while read event; do

  #        "_index": "logstash-2016.12.06",
  #        "_type": "logs",
  #        "_id": "fb1ce396aad70660426ea162dd0ea8b5dd2e59a8",
  #        "_score": 1,
  #        "_source": {
  #          "@timestamp": "2016-12-06T12:29:07.738Z",
  #          "@version": "1",
  #          "path": "/pai-logs/PAIAPPMV131/PAI/logs/Mede.Pai.AC.Submission.Gateway.20161206.log",
  #          "Hostname": "PAIAPPMV131",
  #          "ProcessID": "11960",
  #          "ThreadID": "81",
  #          "Log_Level": "Info",
  #          "Message_Source": "NServiceBus.Distributor.MSMQ.MsmqWorkerAvailabilityManager",
  #          "Message": "Worker at 'mede.pai.ac.submission.gateway@PAIAPPV143' is available to take on more work.",
  #          "Environment": "Production",
  #          "Service": "Mede.Pai.AC.Submission.Gateway"
  
  #echo
  #echo
  #echo event processing
  event=$(echo $event | sed 's/\s*|\s*$//')
  #echo event: $event
  pai_timestamp=$(echo $event | awk -F\| '{print $1}')
  pai_hostname=$(echo $event | awk -F\| '{print $2}')
  pai_process_id=$(echo $event | awk -F\| '{print $3}')
  pai_thread_id=$(echo $event | awk -F\| '{print $4}')
  pai_log_level=$(echo $event | awk -F\| '{print $5}')
  pai_message_source=$(echo $event | awk -F\| '{print $6}')
  pai_timestamp=$(echo $pai_timestamp | sed 's/ /T/')
  pai_message=$(echo $event | awk -F\| '{print $NF}')
  pai_service=$pai_path
  pai_service=$(echo $pai_service | sed 's/^.*\///')
  pai_service=$(echo $pai_service | sed 's/\.[0-9]\{8\}.*$//')
  #echo pai_timestamp: $pai_timestamp
  #echo pai_path: $pai_path
  #echo pai_hostname: $pai_hostname
  #echo pai_process_id: $pai_process_id
  #echo pai_thread_id: $pai_thread_id
  #echo pai_log_level: $pai_log_level
  #echo pai_message_source: $pai_message_source
  #echo pai_message: $pai_message
  #echo pai_service: $pai_service
  
  #logstash-2016.12.11/logs/_explain
  #_validate/query
  #_validate/query?explain
  objects='
  _search
  '
  command='curl'
  command_options='-sS -XGET'
  command_payload='{
    "query" : {
      "constant_score" : { 
        "filter" : {
          "bool" : {
            "must" : [
              { "range" : { "@timestamp" : { "gt" : "'$pai_timestamp'||-1s", "lt" : "'$pai_timestamp'||+1s", "time_zone" : "-08:00"}}},
              { "match" : {"path" : { "query" : "'$pai_path'", "operator" : "and"}}},
              { "match" : {"Hostname" : "'$pai_hostname'"}},
              { "term" : {"ProcessID" : "'$pai_process_id'"}},
              { "term" : {"ThreadID" : "'$pai_thread_id'"}},
              { "match" : {"Message_Source" : { "query" : "'"$pai_message_source"'", "operator" : "and"}}},
              { "match" : {"Message" : { "query" : "'"$pai_message"'", "operator" : "and"}}},
              { "match" : {"Service" : { "query" : "'"$pai_service"'", "operator" : "and"}}}
            ]
          }
        }
      }
    }
  }'
  command_suffix='jq -C .'
  
  for object in $objects; do
    uri=$elasticsearch_host':'$elasticsearch_port'/'$object
    #echo
    #echo elasticsearch request
    #echo $command $command_options $uri '-d' \'$(echo $command_payload | jq -C .)\' \| $command_suffix
    #echo
    #echo elasticsearch response
    response="$($command $command_options $uri '-d' "$command_payload")"
    #echo $response | jq -C .

    #echo
    elk_hits="$(echo $response | jq '.hits | .total')"
    #echo elk_hits: $elk_hits
    if [ $elk_hits -ne 1 ]; then
      echo error: elk_hits $elk_hits not equal to 1
      continue
    fi

    #echo
    #echo elasticsearch fields
    elk_timestamp="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .["@timestamp"]')"
    elk_timestamp="$(echo $elk_timestamp | sed 's/Z$//')"
    elk_timestamp="$(date --date='TZ="America/San_Francisco" '$elk_timestamp'' '+%Y-%m-%dT%H:%M:%S.%N' | sed 's/0*$//')"
    elk_path="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .path')"
    elk_hostname="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .Hostname')"
    elk_process_id="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .ProcessID')"
    elk_thread_id="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .ThreadID')"
    elk_log_level="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .Log_Level')"
    elk_message_source="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .Message_Source')"
    elk_message="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .Message')"
    elk_service="$(echo $response | jq -r '.hits | .hits | .[] | ._source | .Service')"
    #echo elk_timestamp: $elk_timestamp
    #echo elk_path: $elk_path
    #echo elk_hostname: $elk_hostname
    #echo elk_process_id: $elk_process_id
    #echo elk_thread_id: $elk_thread_id
    #echo elk_log_level: $elk_log_level
    #echo elk_message_source: $elk_message_source
    #echo elk_message: $elk_message
    #echo elk_service: $elk_service

    #echo
    #echo comparison
    #elk_timestamp
    if [[ "$pai_timestamp" != "$elk_timestamp"* ]]; then
      echo pai_timestamp "$pai_timestamp" not equal to elk_timestamp "$elk_timestamp"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_timestamp "$pai_timestamp" equal to elk_timestamp "$elk_timestamp"
    fi
    #elk_path
    if [[ "$pai_path" != "$elk_path" ]]; then
      echo pai_path "$pai_path" not equal to elk_path "$elk_path"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_path "$pai_path" equal to elk_path "$elk_path"
    fi
    #elk_hostname
    if [[ "$pai_hostname" != "$elk_hostname" ]]; then
      echo pai_hostname "$pai_hostname" not equal to elk_hostname "$elk_hostname"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_hostname "$pai_hostname" equal to elk_hostname "$elk_hostname"
    fi
    #elk_process_id
    if [[ "$pai_process_id" -ne "$elk_process_id" ]]; then
      echo pai_process_id "$pai_process_id" not equal to elk_process_id "$elk_process_id"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_process_id "$pai_process_id" equal to elk_process_id "$elk_process_id"
    fi
    #elk_thread_id
    if [[ "$pai_thread_id" -ne "$elk_thread_id" ]]; then
      echo pai_thread_id "$pai_thread_id" not equal to elk_thread_id "$elk_thread_id"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_thread_id "$pai_thread_id" equal to elk_thread_id "$elk_thread_id"
    fi
    #elk_log_level
    if [[ "$pai_log_level" != "$elk_log_level" ]]; then
      echo pai_log_level "$pai_log_level" not equal to elk_log_level "$elk_log_level"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_log_level "$pai_log_level" equal to elk_log_level "$elk_log_level"
    fi
    #elk_message_source
    if [[ "$pai_message_source" != "$elk_message_source" ]]; then
      echo pai_message_source "$pai_message_source" not equal to elk_message_source "$elk_message_source"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_message_source "$pai_message_source" equal to elk_message_source "$elk_message_source"
    fi
    #elk_message
    if [[ "$pai_message" != "$elk_message" ]]; then
      echo pai_message "$pai_message" not equal to elk_message "$elk_message"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_message "$pai_message" equal to elk_message "$elk_message"
    fi
    #elk_service
    if [[ "$pai_service" != "$elk_service" ]]; then
      echo pai_service "$pai_service" not equal to elk_service "$elk_service"
      echo $event
      echo $response | jq -C .
      continue
    else
      :
      #echo pai_service "$pai_service" equal to elk_service "$elk_service"
    fi
  done
  
done
