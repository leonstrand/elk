 #!/bin/bash

work() {
  __container=$1
  json="$(docker exec $__container curl -sS localhost:9600/_node/stats/pipeline 2>/dev/null)"
  read duration in filtered out <<<$(echo "$json" | jq -c '.pipeline | .events' | sed -e 's/{"duration_in_millis":/ /' -e 's/,"in":/ /' -e 's/,"filtered":/ /' -e 's/,"out":/ /' -e 's/}//')
  if [ -n "$duration" ]; then
    printf '%33s %14d %9d %9d %9d %9d %14d\n' $__container $(echo "$json" | jq -c '.pipeline | .events' | sed -e 's/{"duration_in_millis":/ /' -e 's/,"in":/ /' -e 's/,"filtered":/ /' -e 's/,"out":/ /' -e 's/}//') $(expr $in - $out) $(expr $in - $filtered)
  else
    printf '%33s\n' $__container
  fi
}
export -f work
printf '%33s %14s %9s %9s %9s %9s %14s\n' container 'duration (ms)' in filtered out 'in - out' 'in - filtered'
parallel -k work ::: $(for i in $(docker ps --filter name=logstash --format {{.Names}} | sort -V); do echo $i; done)
