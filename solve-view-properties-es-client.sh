#!/bin/bash

# Script to download and upload Kibana properties object using Elasticsearch Python client

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

echo "Setting up properties Kibana object using Elasticsearch client..."

# Try to use jq if available to extract credentials
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    
    # Extract ES_USERNAME, ES_PASSWORD and ES_URL using jq
    ES_USERNAME=$(jq -r 'to_entries[0].value.credentials.username' /tmp/project_results.json 2>/dev/null)
    ES_PASSWORD=$(jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json 2>/dev/null)
    ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$ES_USERNAME" ] || [ "$ES_USERNAME" = "null" ] || [ -z "$ES_PASSWORD" ] || [ "$ES_PASSWORD" = "null" ] || [ -z "$ES_URL" ] || [ "$ES_URL" = "null" ]; then
        echo "Error: Could not extract username, password or ES URL from project results"
        exit 1
    fi
else
    echo "Using grep/sed fallback to parse JSON..."
    # Fallback to grep/sed if jq is not available
    ES_USERNAME=$(grep -o '"username": "[^"]*"' /tmp/project_results.json | sed 's/"username": "\([^"]*\)"/\1/' 2>/dev/null)
    ES_PASSWORD=$(grep -o '"password": "[^"]*"' /tmp/project_results.json | sed 's/"password": "\([^"]*\)"/\1/' 2>/dev/null)
    ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$ES_USERNAME" ] || [ -z "$ES_PASSWORD" ] || [ -z "$ES_URL" ]; then
        echo "Error: Could not extract username, password or ES URL from project results"
        exit 1
    fi
fi

echo "Using ES URL: $ES_URL"
echo "Username: $ES_USERNAME"
echo "Password: ${ES_PASSWORD:0:10}..."

# Embedded Python script using Elasticsearch client
python3 << EOF
import requests
import json
import sys
import tempfile
import os

# Try to import elasticsearch client
try:
    from elasticsearch import Elasticsearch
    from elasticsearch.exceptions import NotFoundError, RequestError
    ELASTICSEARCH_AVAILABLE = True
except ImportError:
    print("Warning: elasticsearch-py not available, falling back to requests")
    ELASTICSEARCH_AVAILABLE = False

# Configuration
es_url = "$ES_URL"
es_username = "$ES_USERNAME"
es_password = "$ES_PASSWORD"
properties_url = "https://sunmanapp.blob.core.windows.net/publicstuff/properties/properties.ndjson"

def create_es_client():
    """Create Elasticsearch client with proper authentication"""
    if ELASTICSEARCH_AVAILABLE:
        try:
            # Create client with basic authentication
            es = Elasticsearch(
                [es_url],
                basic_auth=(es_username, es_password),
                timeout=30,
                max_retries=3,
                retry_on_timeout=True
            )
            return es
        except Exception as e:
            print(f"Error creating Elasticsearch client: {e}")
            return None
    else:
        return None

def make_request_fallback(method, url, data=None, timeout=30):
    """Fallback to requests if elasticsearch client not available"""
    headers = {
        'Content-Type': 'application/json'
    }
    
    # Use basic authentication
    import base64
    credentials = f"{es_username}:{es_password}"
    encoded_credentials = base64.b64encode(credentials.encode()).decode()
    headers['Authorization'] = f'Basic {encoded_credentials}'
    
    try:
        print(f"Making {method} request to: {url}")
        
        if method.upper() == 'GET':
            response = requests.get(url, headers=headers, timeout=timeout)
        elif method.upper() == 'PUT':
            response = requests.put(url, headers=headers, json=data, timeout=timeout)
        elif method.upper() == 'POST':
            response = requests.post(url, headers=headers, json=data, timeout=timeout)
        elif method.upper() == 'DELETE':
            response = requests.delete(url, headers=headers, timeout=timeout)
        else:
            raise ValueError(f"Unsupported method: {method}")
        
        print(f"Response status: {response.status_code}")
        if response.status_code >= 400:
            print(f"Response text: {response.text}")
        
        return response
    except requests.exceptions.RequestException as e:
        print(f"Request error: {e}")
        return None

try:
    # Step 0: Create Elasticsearch client and test connectivity
    print("Step 0: Testing connectivity to Elasticsearch...")
    es_client = create_es_client()
    
    if es_client and ELASTICSEARCH_AVAILABLE:
        print("Using Elasticsearch Python client")
        try:
            # Test connectivity
            cluster_info = es_client.cluster.health()
            print("✓ Successfully connected to Elasticsearch")
            print(f"Cluster name: {cluster_info.get('cluster_name', 'Unknown')}")
            print(f"Status: {cluster_info.get('status', 'Unknown')}")
        except Exception as e:
            print(f"Error connecting with Elasticsearch client: {e}")
            es_client = None
    else:
        print("Using requests fallback")
        es_client = None
    
    # Step 1: Check what Kibana indices exist
    print("\\nStep 1: Checking available Kibana indices...")
    kibana_indices = []
    
    if es_client:
        try:
            # Get all indices that start with .kibana
            indices = es_client.cat.indices(index=".kibana*", format="json")
            kibana_indices = [index['index'] for index in indices if index['index'].startswith('.kibana')]
            print(f"Found Kibana indices: {kibana_indices}")
        except Exception as e:
            print(f"Error getting indices: {e}")
            kibana_indices = []
    else:
        # Fallback to requests
        response = make_request_fallback('GET', f"{es_url}/_cat/indices/.kibana*?format=json")
        if response and response.status_code == 200:
            indices = response.json()
            kibana_indices = [index['index'] for index in indices if index['index'].startswith('.kibana')]
            print(f"Found Kibana indices: {kibana_indices}")
    
    if kibana_indices:
        primary_kibana_index = kibana_indices[0]
        print(f"Using primary Kibana index: {primary_kibana_index}")
    else:
        print("No Kibana indices found, will try default .kibana")
        primary_kibana_index = ".kibana"
    
    # Step 2: Download the properties.ndjson file
    print("\\nStep 2: Downloading properties.ndjson from Azure blob storage...")
    response = requests.get(properties_url, timeout=30)
    if response.status_code != 200:
        print(f"Error: Failed to download properties.ndjson: {response.status_code}")
        print(f"Response: {response.text}")
        sys.exit(1)
    
    # Save to temporary file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.ndjson', delete=False) as temp_file:
        temp_file.write(response.text)
        temp_file_path = temp_file.name
    
    print(f"✓ Downloaded properties.ndjson to temporary file: {temp_file_path}")
    
    # Step 3: Parse the NDJSON file to extract object information
    print("\\nStep 3: Parsing properties.ndjson file...")
    objects = []
    with open(temp_file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    obj = json.loads(line)
                    objects.append(obj)
                except json.JSONDecodeError as e:
                    print(f"Warning: Failed to parse line: {e}")
                    continue
    
    if not objects:
        print("Error: No valid objects found in properties.ndjson")
        sys.exit(1)
    
    print(f"✓ Found {len(objects)} objects in properties.ndjson")
    
    # Step 4: Delete existing properties objects if they exist
    print("\\nStep 4: Checking and deleting existing properties objects...")
    for obj in objects:
        if 'type' in obj and 'id' in obj:
            obj_type = obj['type']
            obj_id = obj['id']
            
            # Check if object exists
            object_exists = False
            existing_index = None
            
            if es_client:
                # Try with Elasticsearch client
                for index in [primary_kibana_index, ".kibana", ".kibana_1", ".kibana_8.8.0_001"]:
                    try:
                        doc = es_client.get(index=index, id=obj_id)
                        object_exists = True
                        existing_index = index
                        break
                    except NotFoundError:
                        continue
                    except Exception as e:
                        print(f"Warning: Could not check {obj_type} with ID {obj_id} at {index}: {e}")
            else:
                # Fallback to requests
                for index in [primary_kibana_index, ".kibana", ".kibana_1", ".kibana_8.8.0_001"]:
                    check_url = f"{es_url}/{index}/_doc/{obj_id}"
                    response = make_request_fallback('GET', check_url)
                    if response and response.status_code == 200:
                        object_exists = True
                        existing_index = index
                        break
            
            if object_exists and existing_index:
                print(f"Found existing {obj_type} with ID {obj_id} in {existing_index}, deleting...")
                if es_client:
                    try:
                        es_client.delete(index=existing_index, id=obj_id)
                        print(f"✓ Deleted {obj_type} with ID {obj_id}")
                    except Exception as e:
                        print(f"Warning: Failed to delete {obj_type} with ID {obj_id}: {e}")
                else:
                    delete_url = f"{es_url}/{existing_index}/_doc/{obj_id}"
                    response = make_request_fallback('DELETE', delete_url)
                    if response and response.status_code in [200, 404]:
                        print(f"✓ Deleted {obj_type} with ID {obj_id}")
                    else:
                        print(f"Warning: Failed to delete {obj_type} with ID {obj_id}")
            else:
                print(f"✓ {obj_type} with ID {obj_id} does not exist, skipping deletion")
    
    # Step 5: Upload the properties objects
    print("\\nStep 5: Uploading properties objects...")
    for obj in objects:
        if 'type' in obj and 'id' in obj:
            obj_type = obj['type']
            obj_id = obj['id']
            
            # Prepare the document for upload
            doc_data = {
                "type": obj_type,
                "updated_at": obj.get('updated_at', ''),
                "version": obj.get('version', ''),
                "attributes": obj.get('attributes', {}),
                "references": obj.get('references', []),
                "migrationVersion": obj.get('migrationVersion', {}),
                "coreMigrationVersion": obj.get('coreMigrationVersion', ''),
                "typeMigrationVersion": obj.get('typeMigrationVersion', ''),
                "managed": obj.get('managed', False)
            }
            
            print(f"Uploading document data: {json.dumps(doc_data, indent=2)}")
            
            # Try to upload to different index formats
            upload_success = False
            
            if es_client:
                # Try with Elasticsearch client
                for index in [primary_kibana_index, ".kibana", ".kibana_1", ".kibana_8.8.0_001"]:
                    try:
                        result = es_client.index(index=index, id=obj_id, body=doc_data)
                        if result.get('result') in ['created', 'updated']:
                            print(f"✓ Uploaded {obj_type} with ID {obj_id} to {index}")
                            upload_success = True
                            break
                    except Exception as e:
                        print(f"Failed to upload to {index}: {e}")
            else:
                # Fallback to requests
                for index in [primary_kibana_index, ".kibana", ".kibana_1", ".kibana_8.8.0_001"]:
                    upload_url = f"{es_url}/{index}/_doc/{obj_id}"
                    response = make_request_fallback('PUT', upload_url, doc_data)
                    if response and response.status_code in [200, 201]:
                        print(f"✓ Uploaded {obj_type} with ID {obj_id} to {index}")
                        upload_success = True
                        break
                    else:
                        print(f"Failed to upload to {index}: {response.status_code if response else 'No response'}")
            
            if not upload_success:
                print(f"Error: Failed to upload {obj_type} with ID {obj_id} to any index")
                sys.exit(1)
    
    # Step 6: Verify the upload
    print("\\nStep 6: Verifying the upload...")
    for obj in objects:
        if 'type' in obj and 'id' in obj:
            obj_type = obj['type']
            obj_id = obj['id']
            
            verification_success = False
            
            if es_client:
                # Try with Elasticsearch client
                for index in [primary_kibana_index, ".kibana", ".kibana_1", ".kibana_8.8.0_001"]:
                    try:
                        doc = es_client.get(index=index, id=obj_id)
                        print(f"✓ Verified {obj_type} with ID {obj_id} at {index}")
                        verification_success = True
                        break
                    except NotFoundError:
                        continue
                    except Exception as e:
                        print(f"Warning: Could not verify {obj_type} with ID {obj_id} at {index}: {e}")
            else:
                # Fallback to requests
                for index in [primary_kibana_index, ".kibana", ".kibana_1", ".kibana_8.8.0_001"]:
                    verify_url = f"{es_url}/{index}/_doc/{obj_id}"
                    response = make_request_fallback('GET', verify_url)
                    if response and response.status_code == 200:
                        print(f"✓ Verified {obj_type} with ID {obj_id} at {index}")
                        verification_success = True
                        break
            
            if not verification_success:
                print(f"Warning: Verification failed for {obj_type} with ID {obj_id}")
    
    # Clean up temporary file
    try:
        os.unlink(temp_file_path)
        print(f"\\n✓ Cleaned up temporary file: {temp_file_path}")
    except Exception as e:
        print(f"Warning: Failed to clean up temporary file: {e}")
    
    print("\\n✓ Properties object setup completed successfully!")
    sys.exit(0)
        
except Exception as e:
    print(f"Unexpected error: {e}")
    # Clean up temporary file on error
    try:
        if 'temp_file_path' in locals():
            os.unlink(temp_file_path)
    except:
        pass
    sys.exit(1)
EOF

# Capture the exit code from Python
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Properties object setup completed successfully"
    exit 0
else
    echo "Fail - Properties object setup failed"
    fail-message "Properties object setup failed"
fi 