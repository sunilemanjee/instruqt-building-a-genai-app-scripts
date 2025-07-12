#!/bin/bash
set -euxo pipefail

# Install dependencies
apt update && apt install -y python3-pip python3-venv jq
python3 -m venv /tmp/venv
source /tmp/venv/bin/activate
pip install --quiet elasticsearch==8.17.1 requests==2.31.0

# Failure function for error messages
fail_message() {
  echo "$1" >&2
  exit 1
}

# Extract API key from project results JSON
if [ ! -f "/tmp/project_results.json" ]; then
    fail_message "Project results JSON file not found at /tmp/project_results.json"
fi

# Extract API key from the JSON file
ES_API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json)

if [ "$ES_API_KEY" = "null" ] || [ -z "$ES_API_KEY" ]; then
    fail_message "Failed to extract API key from project results JSON"
fi

echo "Using API key from project results"

# Create inferencing endpoints and ingest data
/tmp/venv/bin/python <<EOF
import os
import json
import requests
from elasticsearch import Elasticsearch, helpers, NotFoundError

# Elasticsearch configuration
ES_HOST = "http://es3-api-v1:9200"
ES_INDEX = "hotels"

# Use API key from bash variable
API_KEY = "$ES_API_KEY"
if not API_KEY:
    raise ValueError("API key is required")

# JSON dataset URL
DATASET_URL = "https://ela.st/hotels-dataset"

# Connect to Elasticsearch using API key
es = Elasticsearch(ES_HOST, api_key=API_KEY, request_timeout=120)

# Define the index mapping
INDEX_MAPPING = {
    "mappings": {
        "properties": {
            "Address": {"type": "text"},
            "Attractions": {"type": "text"},
            "Description": {"type": "text"},
            "FaxNumber": {"type": "text"},
            "HotelCode": {"type": "long"},
            "HotelFacilities": {"type": "text"},
            "HotelName": {"type": "text"},
            "HotelRating": {"type": "long"},
            "HotelWebsiteUrl": {"type": "keyword"},
            "Map": {"type": "keyword"},
            "PhoneNumber": {"type": "text"},
            "PinCode": {"type": "keyword"},
            "cityCode": {"type": "long"},
            "cityName": {"type": "text"},
            "combined_fields": {"type": "text"},
            "countryCode": {"type": "keyword"},
            "countryName": {"type": "keyword"},
            "latitude": {"type": "double"},
            "location": {"type": "geo_point"},
            "longitude": {"type": "double"}
        }
    }
}

# Step 1: Create the index with mapping
def create_index():
    try:
        if es.indices.exists(index=ES_INDEX):
            print(f"Index '{ES_INDEX}' already exists. Deleting and recreating...")
            es.indices.delete(index=ES_INDEX)
        
        es.indices.create(index=ES_INDEX, body=INDEX_MAPPING)
        print(f"Index '{ES_INDEX}' created successfully.")
    except Exception as e:
        print(f"Error creating index: {e}")
        exit(1)

# Step 2: Download the JSON file
def download_json():
    print("Downloading dataset...")
    response = requests.get(DATASET_URL, stream=True)
    response.raise_for_status()
    return response.iter_lines()

# Step 3: Ingest JSON records into Elasticsearch
def ingest_data():
    print("Ingesting data into Elasticsearch...")
    actions = []

    for line in download_json():
        if line:
            record = json.loads(line)
            # Convert latitude/longitude to geo_point format
            if "latitude" in record and "longitude" in record:
                record["location"] = {"lat": record["latitude"], "lon": record["longitude"]}
            
            actions.append({"_index": ES_INDEX, "_source": record})

            # Bulk index in batches of 50
            if len(actions) >= 50:
                helpers.bulk(es, actions)
                print(f"Ingested {len(actions)} records...")
                actions = []

    # Ingest any remaining records
    if actions:
        helpers.bulk(es, actions)
        print(f"Ingested {len(actions)} remaining records.")

    print("Data ingestion complete.")

# Run the steps
create_index()
ingest_data()
EOF

echo "Elasticsearch ingestion completed successfully."
