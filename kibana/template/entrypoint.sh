#!/usr/bin/env bash

# Wait for the Elasticsearch container to be ready before starting Kibana.
echo "$0: Waiting for connection to docker container REPLACE_ELASTICSEARCH_HOST:REPLACE_ELASTICSEARCH_PORT"
while true; do
    nc -q 1 REPLACE_ELASTICSEARCH_HOST REPLACE_ELASTICSEARCH_PORT 2>/dev/null && break
done
echo "$0: Connected to docker container REPLACE_ELASTICSEARCH_HOST:REPLACE_ELASTICSEARCH_PORT"
echo "$0: Starting Kibana"
exec kibana
