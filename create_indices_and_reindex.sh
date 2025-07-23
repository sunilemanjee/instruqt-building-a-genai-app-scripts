#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#
set -euxo pipefail

# Install dependencies
apt update && apt install -y python3-pip python3-venv jq
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

# Create indices and perform reindexing using Python
/tmp/venv/bin/python <<EOF
import json
import time
from elasticsearch import Elasticsearch
from elasticsearch.exceptions import NotFoundError, RequestError

# Get credentials from bash variables
ES_USERNAME = "$ES_USERNAME"
ES_PASSWORD = "$ES_PASSWORD"

# Elasticsearch configuration
ES_HOST = "http://es3-api-v1:9200"

# Connect to Elasticsearch using username and password
es = Elasticsearch(ES_HOST, basic_auth=(ES_USERNAME, ES_PASSWORD), request_timeout=120)

def load_mapping_from_file(filename):
    """Load index mapping from JSON file"""
    try:
        with open(filename, 'r') as f:
            content = f.read()
            # Remove the PUT line and extract just the JSON body
            if content.startswith('PUT'):
                # Find the first { and extract from there
                json_start = content.find('{')
                if json_start != -1:
                    json_content = content[json_start:]
                    return json.loads(json_content)
            else:
                return json.loads(content)
    except Exception as e:
        print(f"Error loading mapping from {filename}: {e}")
        return None

# Load mappings from JSON files
print("Loading index mappings from JSON files...")
int4_mapping = load_mapping_from_file('index-mapping-int4flat.json')
int8_mapping = load_mapping_from_file('index-mapping-int8flat.json')
bbq_mapping = load_mapping_from_file('index-mapping-bbqflat.json')

if not int4_mapping or not int8_mapping or not bbq_mapping:
    print("Error: Could not load one or more mapping files!")
    exit(1)

print("Successfully loaded all index mappings from JSON files.")

def create_index(index_name, mapping):
    """Create an index with the specified mapping"""
    try:
        # Check if index exists and delete it if it does
        if es.indices.exists(index=index_name):
            print(f"Index {index_name} already exists. Deleting it first...")
            delete_response = es.indices.delete(index=index_name)
            print(f"Successfully deleted existing index: {index_name}")
            # Wait a moment for the deletion to complete
            time.sleep(2)
        else:
            print(f"Index {index_name} does not exist. Creating new index...")
        
        # Create the new index
        response = es.indices.create(index=index_name, body=mapping)
        print(f"Successfully created index: {index_name}")
        return True
    except Exception as e:
        print(f"Error creating index {index_name}: {e}")
        return False

def start_reindex(source_index, dest_index):
    """Start an async reindex operation"""
    try:
        reindex_body = {
            "source": {
                "size": 20,
                "index": source_index
            },
            "dest": {
                "index": dest_index
            }
        }
        
        response = es.reindex(body=reindex_body, wait_for_completion=False)
        task_id = response['task']
        print(f"Started reindex from {source_index} to {dest_index}. Task ID: {task_id}")
        return task_id
    except Exception as e:
        print(f"Error starting reindex from {source_index} to {dest_index}: {e}")
        return None

def check_task_status(task_id):
    """Check if a task is complete"""
    try:
        response = es.tasks.get(task_id=task_id)
        return response['completed']
    except Exception as e:
        print(f"Error checking task status for {task_id}: {e}")
        return False

def wait_for_reindex_completion(task_id, dest_index):
    """Wait for reindex completion, checking every 10 seconds"""
    print(f"Waiting for reindex to {dest_index} to complete...")
    while True:
        if check_task_status(task_id):
            print(f"Reindex to {dest_index} completed successfully!")
            break
        else:
            print(f"Reindex to {dest_index} still in progress... checking again in 10 seconds")
            time.sleep(10)

def cleanup_existing_indices():
    """Clean up existing indices if they exist"""
    indices_to_cleanup = ["properties_int4", "properties_int8", "properties_bbq"]
    
    print("Checking for existing indices to clean up...")
    for index_name in indices_to_cleanup:
        try:
            if es.indices.exists(index=index_name):
                print(f"Found existing index: {index_name}. Deleting it...")
                delete_response = es.indices.delete(index=index_name)
                print(f"Successfully deleted index: {index_name}")
            else:
                print(f"Index {index_name} does not exist. No cleanup needed.")
        except Exception as e:
            print(f"Warning: Could not delete index {index_name}: {e}")
    
    print("Index cleanup completed.")

def main():
    print("Starting index creation and reindexing process...")
    
    # Clean up any existing indices first
    cleanup_existing_indices()
    
    # Check if source index exists
    if not es.indices.exists(index="properties"):
        print("Error: Source index 'properties' does not exist!")
        return
    
    # Create the three indices
    indices_to_create = [
        ("properties_int4", int4_mapping),
        ("properties_int8", int8_mapping),
        ("properties_bbq", bbq_mapping)
    ]
    
    created_indices = []
    for index_name, mapping in indices_to_create:
        if create_index(index_name, mapping):
            created_indices.append(index_name)
    
    if not created_indices:
        print("No indices were created successfully. Exiting.")
        return
    
    print(f"Created {len(created_indices)} indices: {', '.join(created_indices)}")
    
    # Start async reindex operations
    task_ids = {}
    for index_name in created_indices:
        task_id = start_reindex("properties", index_name)
        if task_id:
            task_ids[index_name] = task_id
    
    if not task_ids:
        print("No reindex operations were started successfully. Exiting.")
        return
    
    print(f"Started {len(task_ids)} reindex operations")
    
    # Wait for all reindex operations to complete
    for index_name, task_id in task_ids.items():
        wait_for_reindex_completion(task_id, index_name)
    
    print("All reindex operations completed successfully!")

if __name__ == "__main__":
    main()
EOF

echo "Indices creation and reindexing script completed successfully." 