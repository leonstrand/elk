#!/bin/bash

# leonstrand@gmail.com


directory_work=~/elk
directory_data="$1"
date="$2"
if [ -z "$directory_data" ] || ! [ -d "$directory_data" ] || [ -z "$date" ] || [ -n "$3" ]; then
  echo $0: error: fatal: must specify exactly one existing data directory then exactly one date
  echo $0: usage: $0 \<directory\> \<date\>
  echo $0: example: $0 /important/log/directory 20170216
  exit 1
fi

echo
echo $0: matching file list and file count:
echo find "$directory_data" -type f -name \\*"$date"\\* \| tee \>\(wc -l\)
find "$directory_data" -type f -name \*"$date"\* | tee >(wc -l)
sleep 1

echo
echo $0: spinning up one logstash container per matching file in parallel
echo $0: parallelism limited to twice the number of cpu cores at a time
echo cd $directory_work \&\& find "$directory_data" -type f -name \\*"$date"\\* \| time parallel --jobs 200% time ./spinup-logstash-arbitrary-file.sh {} 2\>\&1 \| tee log/spinup-logstash-arbitrary-file.sh.log."$date"
#cd $directory_work && find "$directory_data" -type f -name \*"$date"\* | time parallel --jobs 200% time ./spinup-logstash-arbitrary-file.sh {} 2>&1 | tee log/spinup-logstash-arbitrary-file.sh.log."$date"
