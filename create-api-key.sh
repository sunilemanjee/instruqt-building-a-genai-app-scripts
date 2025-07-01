#!/bin/bash
set -euxo pipefail

# Install dependencies
apt update && apt install -y python3-pip python3-venv
python3 -m venv /tmp/venv
source /tmp/venv/bin/activate
pip install --quiet elasticsearch==8.17.1

# Failure function for error messages
fail_message() {
  echo "$1" >&2
  exit 1
}

ES_USERNAME=$(jq -r --arg region "$REGIONS" '.[$region].credentials.username' /tmp/project_results.json)
ES_PASSWORD=$(jq -r --arg region "$REGIONS" '.[$region].credentials.password' /tmp/project_results.json)

# Create API key with specified privileges
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

# Define the role with specified privileges
role_definition = {
    "write-only-role": {
        "cluster": [
            "manage",
            "all"
        ],
        "indices": [
            {
                "names": [
                    "*"
                ],
                "privileges": [
                    "write",
                    "read",
                    "view_index_metadata",
                    "manage",
                    "all"
                ],
                "allow_restricted_indices": False
            }
        ],
        "applications": [],
        "run_as": [],
        "metadata": {},
        "transient_metadata": {
            "enabled": True
        }
    }
}

# Try to create the role (optional - may not be supported in all Elasticsearch instances)
try:
    es.security.put_role(name="write-only-role", body=role_definition["write-only-role"])
    print("Role 'write-only-role' created successfully.")
    use_custom_role = True
except Exception as e:
    print(f"Note: Could not create custom role: {e}")
    print("Will create API key without custom role descriptor.")
    use_custom_role = False

# Check if encoded API key already exists in project results
existing_encoded_api_key = None
try:
    with open("/tmp/project_results.json", "r") as f:
        project_data = json.load(f)
    existing_encoded_api_key = project_data.get("$REGIONS", {}).get("credentials", {}).get("api_key")
except:
    pass

# If encoded API key exists, check if it's still valid
if existing_encoded_api_key:
    try:
        # Decode the API key to get the ID for validation
        import base64
        decoded_key = base64.b64decode(existing_encoded_api_key).decode('utf-8')
        api_key_id = decoded_key.split(':')[0]
        
        es.security.get_api_key(id=api_key_id)
        print(f"Using existing API key: {api_key_id}")
        encoded_api_key = existing_encoded_api_key
        print(f"Existing API key is valid and will be reused.")
    except:
        print(f"Existing encoded API key not found or invalid. Creating new one...")
        existing_encoded_api_key = None

# Create new API key if needed
if not existing_encoded_api_key:
    try:
        api_key_body = {
            "name": "lab-api-key"
        }
        
        # Add role descriptor only if custom role was created successfully
        if use_custom_role:
            api_key_body["role_descriptors"] = {
                "write-only-role": role_definition["write-only-role"]
            }

        response = es.security.create_api_key(body=api_key_body)
        api_key_id = response["id"]
        api_key_value = response["api_key"]
        encoded_api_key = response["encoded"]
        
        print(f"New API Key created successfully!")
        print(f"API Key ID: {api_key_id}")
        print(f"API Key Value: {api_key_value}")
        print(f"Encoded API Key: {encoded_api_key}")
        
        # Save the encoded API key to a file for later use
        with open("/tmp/api_key.txt", "w") as f:
            f.write(encoded_api_key)
        print("API key saved to /tmp/api_key.txt")
        
        # Add encoded API key to project results JSON
        with open("/tmp/project_results.json", "r") as f:
            project_data = json.load(f)
        
        # Add encoded_api_key to credentials
        project_data["$REGIONS"]["credentials"]["api_key"] = encoded_api_key
        
        # Write back to file
        with open("/tmp/project_results.json", "w") as f:
            json.dump(project_data, f, indent=2)
        print(f"Encoded API key added to project results JSON under credentials")
        
        
    except Exception as e:
        print(f"Error creating API key: {e}")
        exit(1)
else:
    print(f"API key ID already exists in project results JSON")
    # Store existing encoded API key in agent variable
    import subprocess
    subprocess.run(["agent", "variable", "set", "ES_API_KEY", encoded_api_key], check=True)
    print(f"Existing encoded API key stored in agent variable ES_API_KEY")
EOF

echo "API key creation completed successfully."


