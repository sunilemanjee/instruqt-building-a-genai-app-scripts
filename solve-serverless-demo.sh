#!/bin/bash

# Script to setup serverless demo index and template using embedded Python

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

echo "Setting up serverless demo index and template..."

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

# Embedded Python script to setup serverless demo
python3 << EOF
import requests
import json
import sys

# Configuration
es_url = "$ES_URL"
api_key = "$API_KEY"

# Headers for authentication
headers = {
    'Authorization': f'ApiKey {api_key}',
    'Content-Type': 'application/json'
}

def make_request(method, url, data=None):
    """Make HTTP request with error handling"""
    try:
        if method.upper() == 'GET':
            response = requests.get(url, headers=headers, timeout=30)
        elif method.upper() == 'PUT':
            response = requests.put(url, headers=headers, json=data, timeout=30)
        elif method.upper() == 'POST':
            response = requests.post(url, headers=headers, json=data, timeout=30)
        elif method.upper() == 'DELETE':
            response = requests.delete(url, headers=headers, timeout=30)
        else:
            raise ValueError(f"Unsupported method: {method}")
        
        return response
    except requests.exceptions.RequestException as e:
        print(f"Request error: {e}")
        return None

try:
    # Step 1: Delete existing index if it exists
    print("Step 1: Checking and deleting existing serverless-demo-stream index...")
    index_url = f"{es_url}/serverless-demo-stream"
    response = make_request('GET', index_url)
    
    if response and response.status_code == 200:
        print("Found existing serverless-demo-stream index, deleting...")
        delete_response = make_request('DELETE', index_url)
        if delete_response and delete_response.status_code in [200, 404]:
            print("✓ Index deleted successfully")
        else:
            print(f"Warning: Failed to delete index: {delete_response.status_code if delete_response else 'No response'}")
    elif response and response.status_code == 404:
        print("✓ Index does not exist, skipping deletion")
    else:
        print(f"Warning: Could not check index status: {response.status_code if response else 'No response'}")

    # Step 2: Delete existing template if it exists
    print("\\nStep 2: Checking and deleting existing serverless-demo-template...")
    template_url = f"{es_url}/_index_template/serverless-demo-template"
    response = make_request('GET', template_url)
    
    if response and response.status_code == 200:
        print("Found existing serverless-demo-template, deleting...")
        delete_response = make_request('DELETE', template_url)
        if delete_response and delete_response.status_code in [200, 404]:
            print("✓ Template deleted successfully")
        else:
            print(f"Warning: Failed to delete template: {delete_response.status_code if delete_response else 'No response'}")
    elif response and response.status_code == 404:
        print("✓ Template does not exist, skipping deletion")
    else:
        print(f"Warning: Could not check template status: {response.status_code if response else 'No response'}")

    # Step 3: Create the index template
    print("\\nStep 3: Creating serverless-demo-template...")
    template_data = {
        "index_patterns": ["serverless-demo-*"],
        "data_stream": {},
        "template": {
            "mappings": {
                "properties": {
                    "@timestamp": {
                        "type": "date"
                    },
                    "message": {
                        "type": "text"
                    },
                    "user_id": {
                        "type": "keyword"
                    },
                    "event_type": {
                        "type": "keyword"
                    },
                    "value": {
                        "type": "long"
                    }
                }
            }
        }
    }
    
    response = make_request('PUT', template_url, template_data)
    if response and response.status_code == 200:
        print("✓ Index template created successfully")
    else:
        print(f"Error: Failed to create template: {response.status_code if response else 'No response'}")
        if response:
            print(f"Response: {response.text}")
        sys.exit(1)

    # Step 4: Create the index with sample data
    print("\\nStep 4: Creating serverless-demo-stream index with sample data...")
    sample_data = {
        "@timestamp": "2025-01-20T10:00:00.000Z",
        "message": "User login event",
        "user_id": "user_001",
        "event_type": "login",
        "value": 1
    }
    
    doc_url = f"{es_url}/serverless-demo-stream/_doc"
    response = make_request('POST', doc_url, sample_data)
    if response and response.status_code in [200, 201]:
        print("✓ Index and sample document created successfully")
        result = response.json()
        print(f"Document ID: {result.get('_id', 'N/A')}")
    else:
        print(f"Error: Failed to create index/document: {response.status_code if response else 'No response'}")
        if response:
            print(f"Response: {response.text}")
        sys.exit(1)

    # Step 5: Verify the setup
    print("\\nStep 5: Verifying the setup...")
    
    # Check if template exists
    response = make_request('GET', template_url)
    if response and response.status_code == 200:
        print("✓ Template verification successful")
    else:
        print(f"Warning: Template verification failed: {response.status_code if response else 'No response'}")
    
    # Check if index exists
    response = make_request('GET', index_url)
    if response and response.status_code == 200:
        print("✓ Index verification successful")
        index_info = response.json()
        doc_count = index_info.get('serverless-demo-stream', {}).get('total', {}).get('docs', {}).get('count', 0)
        print(f"Document count: {doc_count}")
    else:
        print(f"Warning: Index verification failed: {response.status_code if response else 'No response'}")

    print("\\n✓ Serverless demo setup completed successfully!")
    sys.exit(0)
        
except Exception as e:
    print(f"Unexpected error: {e}")
    sys.exit(1)
EOF

# Capture the exit code from Python
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Serverless demo setup completed successfully"
    exit 0
else
    echo "Fail - Serverless demo setup failed"
    fail-message "Serverless demo setup failed"
fi 