#!/bin/bash

# leonstrand@gmail.com


elasticsearch_host='10.153.13.35'
elasticsearch_port='19206'

#2016-12-14 12:22:55.2948|PAIAPPMV131|5436|44|Info|NServiceBus.Distributor.MSMQ.MsmqWorkerAvailabilityManager|Worker at 'mede.pai.ac.submission.gateway@PAIAPPV143' is available to take on more work.|
pai_path=/pai-logs/PAIAPPMV131/PAI/logs/Mede.Pai.AC.Submission.Gateway.20161214.log
tail_lines=2

echo
echo
echo tail -$tail_lines $pai_path
tail -$tail_lines $pai_path
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
  
  echo
  echo
  echo event processing
  event=$(echo $event | sed 's/\s*|\s*$//')
  echo event: $event
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
  echo pai_timestamp: $pai_timestamp
  echo pai_path: $pai_path
  echo pai_hostname: $pai_hostname
  echo pai_process_id: $pai_process_id
  echo pai_thread_id: $pai_thread_id
  echo pai_log_level: $pai_log_level
  echo pai_message_source: $pai_message_source
  echo pai_message: $pai_message
  echo pai_service: $pai_service
  
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
    echo
    echo elasticsearch response
    $command $command_options $uri '-d' "$command_payload" | $command_suffix
    $command $command_options $uri '-d' "$command_payload" | $command_suffix
  done
  
done
