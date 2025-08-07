#!/bin/bash

# Script to check if Elasticsearch trained models exist using embedded Python

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

# Define the models to check
MODELS=(
    "distilbert-base-cased-finetuned-conll03-english"
    "bhadresh-savani/distilbert-base-uncased-emotion"
    "typeform/distilbert-base-uncased-mnli"
)

echo "Checking if trained models exist..."

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

# Embedded Python script to check if trained models exist
python3 << EOF
import requests
import json
import sys

# Configuration
es_url = "$ES_URL"
api_key = "$API_KEY"
models = [
    "elastic__distilbert-base-cased-finetuned-conll03-english",
    "bhadresh-savani__distilbert-base-uncased-emotion",
    "typeform__distilbert-base-uncased-mnli"
]

# Headers for authentication
headers = {
    'Authorization': f'ApiKey {api_key}',
    'Content-Type': 'application/json'
}

missing_models = []
existing_models = []

try:
    # Get all trained models
    response = requests.get(f"{es_url}/_ml/trained_models", headers=headers, timeout=30)
    
    if response.status_code == 200:
        models_data = response.json()
        available_models = [model['model_id'] for model in models_data.get('trained_model_configs', [])]
        
        # Check each required model
        for model in models:
            if model in available_models:
                print(f"✓ Model '{model}' exists")
                existing_models.append(model)
            else:
                print(f"✗ Model '{model}' does not exist")
                missing_models.append(model)
        
        # Show summary of results
        print(f"\\nFound {len(existing_models)} out of {len(models)} required models")
        if existing_models:
            print(f"Existing models: {', '.join(existing_models)}")
        if missing_models:
            print(f"Missing models: {', '.join(missing_models)}")
        
        # Show all available models for debugging
        print(f"\\nAll available trained models ({len(available_models)} total):")
        for model in sorted(available_models):
            print(f"  - {model}")
        
        # Determine overall result
        if missing_models:
            sys.exit(1)
        else:
            print(f"\\n✓ All {len(models)} models exist")
            sys.exit(0)
            
    elif response.status_code == 404:
        print("Error: Trained models API not available")
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
    echo "Trained models check completed successfully - all models exist"
    exit 0
else
    echo "Fail - Some trained models do not exist"
    fail-message "Some trained models do not exist"
fi 