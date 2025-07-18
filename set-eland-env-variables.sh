#!/bin/bash

# Script to parse project results and set environment variables

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    echo "Please run eland-setup.sh first to download the project results"
    exit 1
fi

echo "Parsing /tmp/project_results.json..."

# Try to use jq if available
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    
    # Extract ES_API_KEY and ES_URL using jq
    API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json 2>/dev/null)
    ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
    
    echo "DEBUG - Raw extracted values:"
    echo "API_KEY: '$API_KEY'"
    echo "ES_URL: '$ES_URL'"
    
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
        echo "DEBUG - Validation failed:"
        echo "API_KEY empty: $([ -z "$API_KEY" ] && echo "YES" || echo "NO")"
        echo "API_KEY null: $([ "$API_KEY" = "null" ] && echo "YES" || echo "NO")"
        echo "ES_URL empty: $([ -z "$ES_URL" ] && echo "YES" || echo "NO")"
        echo "ES_URL null: $([ "$ES_URL" = "null" ] && echo "YES" || echo "NO")"
        exit 1
    fi
else
    echo "Using grep/sed fallback to parse JSON..."
    # Fallback to grep/sed if jq is not available
    API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
    ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
    
    echo "DEBUG - Raw extracted values (grep/sed):"
    echo "API_KEY: '$API_KEY'"
    echo "ES_URL: '$ES_URL'"
    
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
        echo "DEBUG - Validation failed (grep/sed):"
        echo "API_KEY empty: $([ -z "$API_KEY" ] && echo "YES" || echo "NO")"
        echo "ES_URL empty: $([ -z "$ES_URL" ] && echo "YES" || echo "NO")"
        exit 1
    fi
fi 