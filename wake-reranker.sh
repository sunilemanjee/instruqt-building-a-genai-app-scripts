#!/bin/bash

# Script to check if an Elasticsearch index exists using embedded Python

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

INDEX_NAME="rerank-demo"
echo "Checking if index '$INDEX_NAME' exists..."

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
    ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$API_KEY" ] || [ -z "$ES_URL" ]; then
        echo "Error: Could not extract API key or ES URL from project results"
        exit 1
    fi
fi

echo "Using ES URL: $ES_URL"
echo "API key: ${API_KEY:0:10}..."

# Create and activate virtual environment
echo "Setting up Python virtual environment..."
VENV_DIR="./venv_rerank"

# Remove existing venv if it exists
if [ -d "$VENV_DIR" ]; then
    echo "Removing existing virtual environment..."
    rm -rf "$VENV_DIR"
fi

# Create new virtual environment
echo "Creating virtual environment..."
python3 -m venv "$VENV_DIR"

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install required packages
echo "Installing required packages..."
pip install elasticsearch

# Verify installation
echo "Verifying installation..."
python -c "import elasticsearch; print(f'Elasticsearch client version: {elasticsearch.__version__}')"

# Embedded Python script to call rerank inference endpoint using Elasticsearch Python client
python3 << EOF
import json
import sys
import time
from elasticsearch import Elasticsearch

# Configuration
es_url = "$ES_URL"
api_key = "$API_KEY"

# Create Elasticsearch client
try:
    es = Elasticsearch(
        [es_url],
        api_key=api_key,
        request_timeout=30
    )
    
    # Test connection
    if not es.ping():
        print("Error: Could not connect to Elasticsearch")
        sys.exit(1)
    
    print("✓ Connected to Elasticsearch successfully")
    
except Exception as e:
    print(f"Error creating Elasticsearch client: {e}")
    sys.exit(1)

# Rerank request payload
rerank_payload = {
    "input": ["blue", "green", "red", "brown", "white"],
    "query": "colors of a duck"
}

max_retries = 30
retry_delay = 2

print("Attempting to call rerank inference endpoint...")
print(f"Payload: {json.dumps(rerank_payload, indent=2)}")

for attempt in range(max_retries):
    try:
        print(f"Attempt {attempt + 1}/{max_retries}...")
        
        # Call the rerank inference endpoint using the Elasticsearch Python client
        # In Elasticsearch client 9.x, we need to use the inference client differently
        response = es.inference.inference(
            inference_id=".rerank-v1-elasticsearch",
            input=rerank_payload["input"],
            query=rerank_payload["query"],
            task_type="rerank",
            timeout="600s"
        )
        
        print("✓ Rerank inference successful!")
        print(f"Response: {json.dumps(response.body, indent=2)}")
        sys.exit(0)
                
    except Exception as e:
        error_msg = str(e)
        print(f"Attempt {attempt + 1} failed: {error_msg}")
        
        # Check if it's a model not ready error or connection timeout
        if ("503" in error_msg or "500" in error_msg or "model" in error_msg.lower() or 
            "not ready" in error_msg.lower() or "timeout" in error_msg.lower() or 
            "connection" in error_msg.lower()):
            if attempt < max_retries - 1:
                print(f"Model not ready or connection issue, retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                print("Max retries reached")
                sys.exit(1)
        else:
            print(f"Unexpected error: {e}")
            sys.exit(1)

print("Failed to get successful response after all retries")
sys.exit(1)
EOF

# Capture the exit code from Python
EXIT_CODE=$?

# Deactivate virtual environment
echo "Deactivating virtual environment..."
deactivate

if [ $EXIT_CODE -eq 0 ]; then
    echo "Rerank inference completed successfully"
    exit 0
else
    echo "Failed to complete rerank inference"
    exit 1
fi