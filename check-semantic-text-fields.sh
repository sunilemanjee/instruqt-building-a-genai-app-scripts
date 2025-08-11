#!/bin/bash

# Script to check if properties index exists and has correct field mappings

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

INDEX_NAME="properties"
echo "Checking if index '$INDEX_NAME' exists and has correct field mappings..."

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

# Embedded Python script to check index and field mappings
python3 << EOF
import requests
import json
import sys

# Configuration
es_url = "$ES_URL"
api_key = "$API_KEY"
index_name = "$INDEX_NAME"

# Headers for authentication
headers = {
    'Authorization': f'ApiKey {api_key}',
    'Content-Type': 'application/json'
}

try:
    # Check if index exists using HEAD request
    index_response = requests.head(f"{es_url}/{index_name}", headers=headers, timeout=30)
    
    if index_response.status_code != 200:
        print(f"✗ Index '{index_name}' does not exist")
        sys.exit(1)
    
    print(f"✓ Index '{index_name}' exists")
    
    # Get the mapping
    mapping_response = requests.get(f"{es_url}/{index_name}/_mapping", headers=headers, timeout=30)
    
    if mapping_response.status_code != 200:
        print(f"Error: Could not retrieve mapping for index '{index_name}'")
        sys.exit(1)
    
    mapping_data = mapping_response.json()
    
    # Check if the index has mappings
    if index_name not in mapping_data:
        print(f"Error: Index '{index_name}' not found in mapping response")
        sys.exit(1)
    
    properties = mapping_data[index_name].get('mappings', {}).get('properties', {})
    
    # Check for body_content_e5 field
    if 'body_content_e5' not in properties:
        print(f"✗ Field 'body_content_e5' does not exist in index '{index_name}'")
        sys.exit(1)
    
    body_content_e5_config = properties['body_content_e5']
    if body_content_e5_config.get('inference_id') != 'my-e5-endpoint':
        print(f"✗ Field 'body_content_e5' does not have inference_id: my-e5-endpoint")
        sys.exit(1)
    
    print(f"✓ Field 'body_content_e5' exists with correct inference_id")
    
    # Check for body_content_elser field
    if 'body_content_elser' not in properties:
        print(f"✗ Field 'body_content_elser' does not exist in index '{index_name}'")
        sys.exit(1)
    
    body_content_elser_config = properties['body_content_elser']
    actual_inference_id = body_content_elser_config.get('inference_id', 'not found')
    if actual_inference_id != '.elser-2-elastic':
        print(f"✗ Field 'body_content_elser' does not have inference_id: .elser-2-elastic")
        print(f"  Actual inference_id: {actual_inference_id}")
        sys.exit(1)
    
    print(f"✓ Field 'body_content_elser' exists with correct inference_id")
    
    print(f"\\n✓ Index '{index_name}' exists and has correct mappings for both 'body_content_e5' and 'body_content_elser'!")
    sys.exit(0)
        
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
    echo "Properties index check completed successfully"
    exit 0
else
    echo "Fail - Properties index check failed"
    fail-message "Properties index check failed"
fi 