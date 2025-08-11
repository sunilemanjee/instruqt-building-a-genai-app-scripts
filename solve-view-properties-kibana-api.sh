#!/bin/bash

# Script to download and upload Kibana properties object using Kibana Saved Objects API

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

echo "Setting up properties Kibana object using Kibana API..."

# Try to use jq if available to extract credentials
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    
    # Extract ES_USERNAME, ES_PASSWORD and KIBANA_URL using jq
    ES_USERNAME=$(jq -r 'to_entries[0].value.credentials.username' /tmp/project_results.json 2>/dev/null)
    ES_PASSWORD=$(jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json 2>/dev/null)
    KIBANA_URL=$(jq -r 'to_entries[0].value.endpoints.kibana' /tmp/project_results.json 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$ES_USERNAME" ] || [ "$ES_USERNAME" = "null" ] || [ -z "$ES_PASSWORD" ] || [ "$ES_PASSWORD" = "null" ] || [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" = "null" ]; then
        echo "Error: Could not extract username, password or Kibana URL from project results"
        exit 1
    fi
else
    echo "Using grep/sed fallback to parse JSON..."
    # Fallback to grep/sed if jq is not available
    ES_USERNAME=$(grep -o '"username": "[^"]*"' /tmp/project_results.json | sed 's/"username": "\([^"]*\)"/\1/' 2>/dev/null)
    ES_PASSWORD=$(grep -o '"password": "[^"]*"' /tmp/project_results.json | sed 's/"password": "\([^"]*\)"/\1/' 2>/dev/null)
    KIBANA_URL=$(grep -o '"kibana": "[^"]*"' /tmp/project_results.json | sed 's/"kibana": "\([^"]*\)"/\1/' 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$ES_USERNAME" ] || [ -z "$ES_PASSWORD" ] || [ -z "$KIBANA_URL" ]; then
        echo "Error: Could not extract username, password or Kibana URL from project results"
        exit 1
    fi
fi

echo "Using Kibana URL: $KIBANA_URL"
echo "Username: $ES_USERNAME"
echo "Password: ${ES_PASSWORD:0:10}..."

# Embedded Python script using Kibana Saved Objects API
python3 << EOF
import requests
import json
import sys
import tempfile
import os

# Configuration
kibana_url = "$KIBANA_URL"
es_username = "$ES_USERNAME"
es_password = "$ES_PASSWORD"
properties_url = "https://sunmanapp.blob.core.windows.net/publicstuff/properties/properties.ndjson"

def make_kibana_request(method, endpoint, data=None, timeout=30):
    """Make HTTP request to Kibana API with proper authentication"""
    try:
        # Use basic authentication
        import base64
        credentials = f"{es_username}:{es_password}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode()
        
        headers = {
            'Authorization': f'Basic {encoded_credentials}',
            'Content-Type': 'application/json',
            'kbn-xsrf': 'true'  # Required for Kibana API calls
        }
        
        url = f"{kibana_url}/api{endpoint}"
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
        print(f"Error type: {type(e).__name__}")
        return None

try:
    # Step 0: Test connectivity to Kibana
    print("Step 0: Testing connectivity to Kibana...")
    test_response = make_kibana_request('GET', '/status')
    if test_response and test_response.status_code == 200:
        print("✓ Successfully connected to Kibana")
        status_info = test_response.json()
        print(f"Kibana version: {status_info.get('version', {}).get('number', 'Unknown')}")
        print(f"Status: {status_info.get('status', {}).get('overall', {}).get('level', 'Unknown')}")
    else:
        print("Warning: Could not connect to Kibana")
        if test_response:
            print(f"Status code: {test_response.status_code}")
            print(f"Response: {test_response.text}")
    
    # Step 1: Download the properties.ndjson file
    print("\\nStep 1: Downloading properties.ndjson from Azure blob storage...")
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
    
    # Step 2: Parse the NDJSON file to extract object information
    print("\\nStep 2: Parsing properties.ndjson file...")
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
    
    # Step 3: Delete existing properties objects if they exist
    print("\\nStep 3: Checking and deleting existing properties objects...")
    for obj in objects:
        if 'type' in obj and 'id' in obj:
            obj_type = obj['type']
            obj_id = obj['id']
            
            # Check if object exists using Kibana API
            check_response = make_kibana_request('GET', f'/saved_objects/{obj_type}/{obj_id}')
            
            if check_response and check_response.status_code == 200:
                print(f"Found existing {obj_type} with ID {obj_id}, deleting...")
                delete_response = make_kibana_request('DELETE', f'/saved_objects/{obj_type}/{obj_id}')
                if delete_response and delete_response.status_code in [200, 404]:
                    print(f"✓ Deleted {obj_type} with ID {obj_id}")
                else:
                    print(f"Warning: Failed to delete {obj_type} with ID {obj_id}")
            elif check_response and check_response.status_code == 404:
                print(f"✓ {obj_type} with ID {obj_id} does not exist, skipping deletion")
            else:
                print(f"Warning: Could not check {obj_type} with ID {obj_id}")
    
    # Step 4: Upload the properties objects using Kibana API
    print("\\nStep 4: Uploading properties objects using Kibana API...")
    for obj in objects:
        if 'type' in obj and 'id' in obj:
            obj_type = obj['type']
            obj_id = obj['id']
            
            # Prepare the document for upload using Kibana Saved Objects format
            saved_object_data = {
                "attributes": obj.get('attributes', {}),
                "version": obj.get('version', ''),
                "migrationVersion": obj.get('migrationVersion', {}),
                "coreMigrationVersion": obj.get('coreMigrationVersion', ''),
                "typeMigrationVersion": obj.get('typeMigrationVersion', ''),
                "managed": obj.get('managed', False),
                "references": obj.get('references', [])
            }
            
            print(f"Uploading {obj_type} with ID {obj_id}")
            print(f"Document data: {json.dumps(saved_object_data, indent=2)}")
            
            # Upload using Kibana Saved Objects API
            upload_response = make_kibana_request('POST', f'/saved_objects/{obj_type}/{obj_id}', saved_object_data)
            
            if upload_response and upload_response.status_code in [200, 201]:
                result = upload_response.json()
                print(f"✓ Uploaded {obj_type} with ID {obj_id}")
                print(f"Result: {result.get('result', 'N/A')}")
            else:
                print(f"Error: Failed to upload {obj_type} with ID {obj_id}")
                if upload_response:
                    print(f"Response: {upload_response.text}")
                sys.exit(1)
    
    # Step 5: Verify the upload using Kibana API
    print("\\nStep 5: Verifying the upload...")
    for obj in objects:
        if 'type' in obj and 'id' in obj:
            obj_type = obj['type']
            obj_id = obj['id']
            
            verify_response = make_kibana_request('GET', f'/saved_objects/{obj_type}/{obj_id}')
            
            if verify_response and verify_response.status_code == 200:
                print(f"✓ Verified {obj_type} with ID {obj_id}")
                saved_obj = verify_response.json()
                print(f"  - Title: {saved_obj.get('attributes', {}).get('title', 'N/A')}")
                print(f"  - Version: {saved_obj.get('version', 'N/A')}")
            else:
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