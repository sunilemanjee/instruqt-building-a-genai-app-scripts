#!/bin/bash

# Script to check if an Elasticsearch datastream exists using embedded Python

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

DATASTREAM_NAME="serverless-demo-stream"
echo "Checking if datastream '$DATASTREAM_NAME' exists..."

# Try to use jq if available to extract credentials
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    
    # Extract ES_API_KEY and ES_URL using jq
    API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json 2>/dev/null)
    ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ] || [ -z "$ES_URL" ] || [ "$ES_URL" = "null" ]; then
        echo "Error: Could not extract API key or ES URL from project results"
        exit 1
    fi
else
    echo "Using grep/sed fallback to parse JSON..."
    # Fallback to grep/sed if jq is not available
    API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
    ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$API_KEY" ] || [ -z "$ES_URL" ]; then
        echo "Error: Could not extract API key or ES URL from project results"
        exit 1
    fi
fi

echo "Using ES URL: $ES_URL"
echo "API key: ${API_KEY:0:10}..."

# Embedded Python script to check if datastream exists
python3 << EOF
import requests
import json
import sys

# Configuration
es_url = "$ES_URL"
api_key = "$API_KEY"
datastream_name = "$DATASTREAM_NAME"

# Headers for authentication
headers = {
    'Authorization': f'ApiKey {api_key}',
    'Content-Type': 'application/json'
}

try:
    # Check if datastream exists using GET _data_stream API
    response = requests.get(f"{es_url}/_data_stream/{datastream_name}", headers=headers, timeout=30)
    
    if response.status_code == 200:
        print(f"✓ Datastream '{datastream_name}' exists")
        sys.exit(0)
    elif response.status_code == 404:
        print(f"✗ Datastream '{datastream_name}' does not exist")
        sys.exit(1)
    else:
        print(f"Error: Unexpected status code {response.status_code}")
        print(f"Response: {response.text}")
        sys.exit(1)
        
except requests.exceptions.RequestException as e:
    print(f"Error connecting to Elasticsearch: {e}")
    sys.exit(1)
except Exception as e:
    print(f"Unexpected error: {e}")
    sys.exit(1)
EOF

# Capture the exit code from Python
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Datastream check completed successfully - datastream exists"
    exit 0
else
    echo "Fail - Datastream serverless-demo-stream does not exist"
   fail-message "Datastream serverless-demo-stream does not exist"
fi 