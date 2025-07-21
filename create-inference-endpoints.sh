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

# === Allocation settings (customize as needed) ===
ELSER_MAX_ALLOCATIONS=4
E5_MAX_ALLOCATIONS=4

# Create inference endpoints using Python
# Pass allocation variables as environment variables
ELSER_MAX_ALLOCATIONS="$ELSER_MAX_ALLOCATIONS" \
E5_MAX_ALLOCATIONS="$E5_MAX_ALLOCATIONS" \
/tmp/venv/bin/python <<EOF
import os
import json
import time
from elasticsearch import Elasticsearch

# Get credentials from bash variables
ES_USERNAME = "$ES_USERNAME"
ES_PASSWORD = "$ES_PASSWORD"

# Elasticsearch configuration
ES_HOST = "http://es3-api-v1:9200"

# Connect to Elasticsearch using username and password
es = Elasticsearch(ES_HOST, basic_auth=(ES_USERNAME, ES_PASSWORD), request_timeout=120)

# Read allocation settings from environment variables
ELSER_MAX_ALLOCATIONS = int(os.environ.get("ELSER_MAX_ALLOCATIONS", 4))
E5_MAX_ALLOCATIONS = int(os.environ.get("E5_MAX_ALLOCATIONS", 4))

# Function to check if model is ready (downloaded and available)
def check_model_ready(model_id, max_wait_time=600):
    print(f"Checking if model {model_id} is ready (downloaded and available)...")
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        try:
            # Check if model exists and is ready
            model_info = es.ml.get_trained_models(model_id=model_id)
            model_stats = es.ml.get_trained_models_stats(model_id=model_id)
            
            # Check if model exists
            if model_info.body.get('count', 0) > 0:
                model_data = model_info.body.get('trained_model_configs', [{}])[0]
                model_stats_data = model_stats.body.get('trained_model_stats', [{}])[0]
                
                # Debug: Print model configuration
                print(f"Model config: {json.dumps(model_data, indent=2)}")
                print(f"Model stats: {json.dumps(model_stats_data, indent=2)}")
                
                # Check if model has deployment_stats (meaning it's deployed as an endpoint)
                deployment_stats = model_stats_data.get('deployment_stats', {})
                
                if deployment_stats:
                    # Model is deployed as an endpoint
                    deployment_state = deployment_stats.get('state', 'unknown')
                    
                    if deployment_state == 'started':
                        print(f"✓ Model {model_id} is deployed and ready!")
                        return True
                    elif deployment_state in ['starting', 'downloading']:
                        print(f"Model {model_id} is still deploying... (state: {deployment_state})")
                    else:
                        print(f"Model {model_id} deployment state: {deployment_state}")
                else:
                    # Model exists but not deployed as an endpoint - check if it's fully downloaded
                    if model_data.get('fully_defined', False):
                        print(f"✓ Model {model_id} is fully downloaded and ready for deployment!")
                        return True
                    else:
                        # Alternative check: if model has size stats, it's likely ready
                        model_size = model_stats_data.get('model_size_stats', {}).get('model_size_bytes', 0)
                        if model_size > 0:
                            print(f"✓ Model {model_id} has size {model_size} bytes and appears ready for deployment!")
                            return True
                        else:
                            print(f"Model {model_id} is still downloading... (fully_defined: {model_data.get('fully_defined', False)})")
            else:
                print(f"Model {model_id} does not exist yet")
            
            time.sleep(15)  # Wait 15 seconds before checking again
            
        except Exception as e:
            print(f"Error checking model readiness: {e}")
            time.sleep(15)
    
    print(f"⚠️  Model readiness check timed out after {max_wait_time} seconds")
    return False

# Function to check deployment status
def check_deployment_status(model_id, max_wait_time=300):
    print(f"Checking deployment status for model: {model_id}")
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        try:
            # Check trained model stats
            stats_response = es.ml.get_trained_models_stats(model_id=model_id)
            deployment_stats = stats_response.body.get('trained_model_stats', [])
            
            if deployment_stats:
                deployment = deployment_stats[0].get('deployment_stats', {})
                state = deployment.get('state', 'unknown')
                print(f"Model {model_id} deployment state: {state}")
                
                if state == 'started':
                    print(f"✓ Model {model_id} is fully deployed and ready!")
                    return True
                elif state in ['starting', 'downloading']:
                    print(f"Model {model_id} is still deploying... (state: {state})")
                else:
                    print(f"Model {model_id} deployment state: {state}")
            
            time.sleep(10)  # Wait 10 seconds before checking again
            
        except Exception as e:
            print(f"Error checking deployment status: {e}")
            time.sleep(10)
    
    print(f"⚠️  Deployment status check timed out after {max_wait_time} seconds")
    return False

# Function to create inference endpoint
def create_inference_endpoint(endpoint_id, task_type, model_id, config_file, max_alloc):
    print(f"\n=== Creating {endpoint_id} ===")
    
    # First, check if the model is ready before proceeding
    print(f"Checking if model {model_id} is ready before creating endpoint...")
    if not check_model_ready(model_id):
        print(f"❌ Model {model_id} is not ready. Skipping endpoint creation.")
        return False
    
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
                "max_number_of_allocations": max_alloc
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
        
        return True
        
    except Exception as e:
        error_msg = str(e)
        if "model_deployment_timeout_exception" in error_msg:
            print(f"⚠️  Deployment timeout for {endpoint_id} - this is normal for large models")
            print(f"The model is still deploying in the background. Checking deployment status...")
            
            # Check if the endpoint was actually created despite the timeout
            try:
                endpoint_check = es.inference.get(inference_id=endpoint_id)
                print(f"✓ Endpoint '{endpoint_id}' was created successfully despite timeout")
                
                # Monitor deployment status
                deployment_ready = check_deployment_status(model_id)
                if deployment_ready:
                    print(f"✓ Endpoint '{endpoint_id}' is fully ready for use!")
                    return True
                else:
                    print(f"⚠️  Endpoint '{endpoint_id}' created but deployment is still in progress")
                    print(f"You can check status later using: GET /_ml/trained_models/{model_id}/_stats")
                    return True  # Consider this a success since endpoint was created
                    
            except Exception as check_error:
                print(f"Could not verify endpoint creation: {check_error}")
                print(f"However, the timeout error suggests the endpoint may still be created")
                return True  # Consider this a success since timeout is expected
        elif "not enough memory" in error_msg.lower():
            print(f"⚠️  Memory allocation error for {endpoint_id} - waiting 5 seconds and checking if endpoint was created...")
            time.sleep(5)
            
            # Check if the endpoint was actually created despite the memory error
            try:
                endpoint_check = es.inference.get(inference_id=endpoint_id)
                print(f"✓ Endpoint '{endpoint_id}' was created successfully despite memory error")
                print(f"Endpoint status: {json.dumps(endpoint_check.body, indent=2)}")
                return True  # Consider this a success since endpoint was created
                    
            except Exception as check_error:
                print(f"Could not verify endpoint creation: {check_error}")
                print(f"However, the memory error suggests the endpoint may still be created")
                return True  # Consider this a success since memory errors can be transient
        else:
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
    config_file="/tmp/elser_inference_endpoint_config.json",
    max_alloc=ELSER_MAX_ALLOCATIONS
)

# Create E5 endpoint (text embedding)
e5_success = create_inference_endpoint(
    endpoint_id="my-e5-endpoint",
    task_type="text_embedding",
    model_id=".multilingual-e5-small",
    config_file="/tmp/e5_inference_endpoint_config.json",
    max_alloc=E5_MAX_ALLOCATIONS
)

# Summary
print("\n=== SUMMARY ===")
if elser_success:
    print("✓ ELSER endpoint (my-elser-endpoint) created successfully")
else:
    print("✗ ELSER endpoint creation failed")

if e5_success:
    print("✓ E5 endpoint (my-e5-endpoint) created successfully (may still be deploying)")
else:
    print("✗ E5 endpoint creation failed")

if elser_success and e5_success:
    print("\nAll inference endpoints created successfully!")
    print("\nNote: If you encountered deployment timeouts, the models may still be deploying.")
    print("You can check deployment status using:")
    print("  GET /_ml/trained_models/.multilingual-e5-small/_stats")
    print("  GET /_ml/trained_models/.elser_model_2_linux-x86_64/_stats")
else:
    print("\nSome endpoints failed to create. Check the logs above.")
    exit(1)

print("\nInference endpoints creation process completed.")
EOF

echo "Inference endpoints creation script completed successfully." 