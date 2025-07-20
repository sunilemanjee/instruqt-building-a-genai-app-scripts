#!/bin/bash
set -euxo pipefail

# Install dependencies
apt update && apt install -y python3-pip python3-venv
python3 -m venv /tmp/venv
source /tmp/venv/bin/activate
pip install --quiet elasticsearch==9.0.2

# Failure function for error messages
fail_message() {
  echo "$1" >&2
  exit 1
}

# Get credentials from project results
ES_USERNAME=$(jq -r 'to_entries[0].value.credentials.username' /tmp/project_results.json)
ES_PASSWORD=$(jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json)

# Create inference endpoints using Python
/tmp/venv/bin/python <<EOF
import os
import json
from elasticsearch import Elasticsearch

# Get credentials from bash variables
ES_USERNAME = "$ES_USERNAME"
ES_PASSWORD = "$ES_PASSWORD"

# Elasticsearch configuration
ES_HOST = "http://es3-api-v1:9200"

# Connect to Elasticsearch using username and password
es = Elasticsearch(ES_HOST, basic_auth=(ES_USERNAME, ES_PASSWORD), request_timeout=120)

# Function to create inference endpoint
def create_inference_endpoint(endpoint_id, task_type, model_id, config_file):
    print(f"\\n=== Creating {endpoint_id} ===")
    
    # Delete the endpoint if it already exists
    try:
        print(f"Checking if endpoint '{endpoint_id}' already exists...")
        existing_endpoint = es.inference.get(inference_id=endpoint_id)
        print(f"Endpoint exists. Deleting it first...")
        delete_response = es.inference.delete(inference_id=endpoint_id)
        print(f"Existing endpoint deleted successfully!")
        print(f"Delete response: {json.dumps(delete_response.body, indent=2)}")
    except Exception as e:
        print(f"Endpoint does not exist or could not be retrieved: {e}")
        print(f"Proceeding with endpoint creation...")

    # Define the inference endpoint configuration
    inference_endpoint_config = {
        "service": "elasticsearch",
        "service_settings": {
            "adaptive_allocations": {
                "enabled": True,
                "min_number_of_allocations": 2,
                "max_number_of_allocations": 4
            },
            "num_threads": 1,
            "model_id": model_id
        },
        "chunking_settings": {
            "strategy": "sentence",
            "max_chunk_size": 100,
            "sentence_overlap": 1
        }
    }

    # Create the inference endpoint using the correct API
    try:
        response = es.inference.put(
            inference_id=endpoint_id,
            task_type=task_type,
            body=inference_endpoint_config
        )
        print(f"Inference endpoint '{endpoint_id}' created successfully!")
        print(f"Response: {json.dumps(response.body, indent=2)}")
        
        # Save the endpoint configuration to a file for reference
        with open(config_file, "w") as f:
            json.dump(inference_endpoint_config, f, indent=2)
        print(f"Endpoint configuration saved to {config_file}")
        
    except Exception as e:
        print(f"Error creating inference endpoint: {e}")
        return False

    # Verify the endpoint was created
    try:
        # Check if the endpoint exists using the inference API
        endpoints_response = es.inference.get(inference_id=endpoint_id)
        print(f"Endpoint verification successful!")
        print(f"Endpoint status: {json.dumps(endpoints_response.body, indent=2)}")
        return True
        
    except Exception as e:
        print(f"Warning: Could not verify endpoint creation: {e}")
        print(f"The endpoint may still have been created successfully.")
        return True

# Create ELSER endpoint (sparse embedding)
elser_success = create_inference_endpoint(
    endpoint_id="my-elser-endpoint",
    task_type="sparse_embedding",
    model_id=".elser_model_2_linux-x86_64",
    config_file="/tmp/elser_inference_endpoint_config.json"
)

# Create E5 endpoint (text embedding)
e5_success = create_inference_endpoint(
    endpoint_id="my-e5-endpoint",
    task_type="text_embedding",
    model_id=".multilingual-e5-small",
    config_file="/tmp/e5_inference_endpoint_config.json"
)

# Summary
print("\\n=== SUMMARY ===")
if elser_success:
    print("✓ ELSER endpoint (my-elser-endpoint) created successfully")
else:
    print("✗ ELSER endpoint creation failed")

if e5_success:
    print("✓ E5 endpoint (my-e5-endpoint) created successfully")
else:
    print("✗ E5 endpoint creation failed")

if elser_success and e5_success:
    print("\\nAll inference endpoints created successfully!")
else:
    print("\\nSome endpoints failed to create. Check the logs above.")
    exit(1)

print("\\nInference endpoints creation process completed.")
EOF

echo "Inference endpoints creation script completed successfully." 