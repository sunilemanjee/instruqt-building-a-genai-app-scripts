#!/bin/bash

# Script to download project results from Elastic Cloud and set environment variables

# Check if required environment variable is set
if [ -z "$PROXY_ES_KEY_BROKER" ]; then
    echo "Error: PROXY_ES_KEY_BROKER environment variable is not set"
    exit 1
fi

# Validate that the URL looks reasonable
if [[ ! "$PROXY_ES_KEY_BROKER" =~ ^https?:// ]]; then
    echo "Error: PROXY_ES_KEY_BROKER does not appear to be a valid URL"
    exit 1
fi

# Check if /tmp is writable
if [ ! -w "/tmp" ]; then
    echo "Error: /tmp directory is not writable"
    exit 1
fi

# Fetch project results and store in /tmp/project_results.json
echo "Fetching project results from $PROXY_ES_KEY_BROKER..."

MAX_RETRIES=10
RETRY_WAIT=30
DOWNLOAD_SUCCESS=false

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $attempt of $MAX_RETRIES at $(date)"
    
    # Fetch the response with proper error handling
    if curl -s -f "$PROXY_ES_KEY_BROKER" > /tmp/project_results.json 2>/dev/null; then
        echo "Project results saved to /tmp/project_results.json"
        DOWNLOAD_SUCCESS=true
        break
    else
        echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "Waiting $RETRY_WAIT seconds before retry..."
            sleep $RETRY_WAIT
        fi
    fi
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "Error: Failed to download project results after $MAX_RETRIES attempts"
    exit 1
fi

# Verify the downloaded file exists and is not empty
if [ ! -f "/tmp/project_results.json" ] || [ ! -s "/tmp/project_results.json" ]; then
    echo "Error: Downloaded file is empty or missing"
    exit 1
fi

# Verify it's valid JSON
if ! jq empty /tmp/project_results.json 2>/dev/null; then
    echo "Error: Downloaded content is not valid JSON"
    exit 1
fi

echo "Parsing /tmp/project_results.json..."

# Try to use jq if available
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    
    # Extract ES_API_KEY and ES_URL using jq
    API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json 2>/dev/null)
    ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
    
    # Validate the extracted values
    if [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ] && [ ! -z "$ES_URL" ] && [ "$ES_URL" != "null" ]; then
        echo "API key found successfully: ${API_KEY:0:10}..."
        echo "ES URL found: $ES_URL"
        
        # Export environment variables
        export ES_API_KEY="$API_KEY"
        export ES_URL="$ES_URL"
        
        echo "Environment variables set successfully:"
        echo "ES_API_KEY: ${ES_API_KEY:0:10}..."
        echo "ES_URL: $ES_URL"
        
        # Output variables in a format that can be sourced
        echo ""
        echo "# Environment variables for sourcing:"
        echo "export ES_API_KEY=\"$ES_API_KEY\""
        echo "export ES_URL=\"$ES_URL\""
        
        exit 0
    else
        echo "API key or ES URL not found or invalid in response"
        exit 1
    fi
else
    echo "Using grep/sed fallback to parse JSON..."
    # Fallback to grep/sed if jq is not available
    API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
    ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
    
    # Validate the extracted values
    if [ ! -z "$API_KEY" ] && [ ! -z "$ES_URL" ]; then
        echo "API key found successfully: ${API_KEY:0:10}..."
        echo "ES URL found: $ES_URL"
        
        # Export environment variables
        export ES_API_KEY="$API_KEY"
        export ES_URL="$ES_URL"
        
        echo "Environment variables set successfully:"
        echo "ES_API_KEY: ${ES_API_KEY:0:10}..."
        echo "ES_URL: $ES_URL"
        
        # Output variables in a format that can be sourced
        echo ""
        echo "# Environment variables for sourcing:"
        echo "export ES_API_KEY=\"$ES_API_KEY\""
        echo "export ES_URL=\"$ES_URL\""
        
        exit 0
    else
        echo "API key or ES URL not found in response"
        exit 1
    fi
fi
