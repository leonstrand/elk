#!/bin/bash

printf '%-52s %-10s %-8s %6s\n' pagefile date time lines
find /elk/logstash/ -maxdepth 1 -mindepth 1 -type d | sort -V | while read directory; do
  find $directory/data/queue/main -type f -name 'page.*' | sort -V | while read pagefile; do
    printf '%-52s %s %s %6s\n' $pagefile $(ls --full-time $pagefile | awk '{print $6, $7}' | cut -d. -f1) "$(wc -l $pagefile | awk '{print $1}')" 
  done
done
