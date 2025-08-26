#!/bin/bash

# Script to check if an OpenAI chat completions inference endpoint exists and create it if needed

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

ENDPOINT_NAME="openai_chat_completions"
TASK_TYPE="chat_completion"
echo "Checking if inference endpoint '$ENDPOINT_NAME' exists..."

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

# Embedded Python script to check if inference endpoint exists and create if needed
python3 << EOF
import requests
import json
import sys
import os

# Configuration
es_url = "$ES_URL"
api_key = "$API_KEY"
endpoint_name = "$ENDPOINT_NAME"
task_type = "$TASK_TYPE"

# Get OpenAI credentials from agent variables
llm_key = os.environ.get('LLM_KEY')
llm_chat_url = os.environ.get('LLM_CHAT_URL')

if not llm_key:
    print("Error: LLM_KEY environment variable not set")
    sys.exit(1)

if not llm_chat_url:
    print("Error: LLM_CHAT_URL environment variable not set")
    sys.exit(1)

# Headers for authentication
headers = {
    'Authorization': f'ApiKey {api_key}',
    'Content-Type': 'application/json'
}

def check_endpoint_exists():
    """Check if the inference endpoint exists"""
    try:
        response = requests.get(f"{es_url}/_inference/{task_type}/{endpoint_name}", headers=headers, timeout=30)
        
        if response.status_code == 200:
            print(f"✓ Inference endpoint '{endpoint_name}' exists")
            return True
        elif response.status_code == 404:
            print(f"✗ Inference endpoint '{endpoint_name}' does not exist")
            return False
        else:
            print(f"Error: Unexpected status code {response.status_code}")
            print(f"Response: {response.text}")
            return None
            
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to Elasticsearch: {e}")
        return None

def create_endpoint():
    """Create the OpenAI chat completions inference endpoint"""
    try:
        # OpenAI chat completion endpoint configuration
        endpoint_config = {
            "service": "openai",
            "service_settings": {
                "url": llm_chat_url,
                "api_key": llm_key
            },
            "task_settings": {
                "model": "gpt-3.5-turbo"
            }
        }
        
        print(f"Creating inference endpoint '{endpoint_name}'...")
        response = requests.put(
            f"{es_url}/_inference/{task_type}/{endpoint_name}",
            headers=headers,
            json=endpoint_config,
            timeout=60
        )
        
        if response.status_code == 200:
            print(f"✓ Successfully created inference endpoint '{endpoint_name}'")
            return True
        else:
            print(f"Error creating endpoint: {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"Error creating inference endpoint: {e}")
        return False

# Main execution
print("Checking if inference endpoint exists...")
endpoint_exists = check_endpoint_exists()

if endpoint_exists is None:
    print("Error: Could not determine endpoint status")
    sys.exit(1)
elif endpoint_exists:
    print("Inference endpoint already exists - no action needed")
    sys.exit(0)
else:
    print("Endpoint does not exist - creating it...")
    if create_endpoint():
        print("Inference endpoint creation completed successfully")
        sys.exit(0)
    else:
        print("Failed to create inference endpoint")
        sys.exit(1)
EOF

# Capture the exit code from Python
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "OpenAI chat completions inference endpoint check/creation completed successfully"
    exit 0
else
    echo "Fail - OpenAI chat completions inference endpoint does not exist and could not be created"
    fail-message "OpenAI chat completions inference endpoint does not exist and could not be created"
fi
