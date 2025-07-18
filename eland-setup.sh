#!/bin/bash

# Script to download project results from Elastic Cloud

# Check if required environment variable is set
if [ -z "$PROXY_ES_KEY_BROKER" ]; then
    echo "Error: PROXY_ES_KEY_BROKER environment variable is not set"
    exit 1
fi

# Fetch project results and store in /tmp/project_results.json
echo "Fetching project results from $PROXY_ES_KEY_BROKER..."

MAX_RETRIES=10
RETRY_WAIT=30

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $attempt of $MAX_RETRIES at $(date)"
    
    # Fetch the response
    curl -s $PROXY_ES_KEY_BROKER > /tmp/project_results.json
    
    if [ $? -eq 0 ]; then
        echo "Project results saved to /tmp/project_results.json"
        echo "Download completed successfully!"
        exit 0
    else
        echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
        [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
    fi
done

echo "Error: Failed to download project results after $MAX_RETRIES attempts"
exit 1
