#!/bin/bash

# Script to check if a Kibana properties map view exists using embedded Python

# Check if the project results file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Error: /tmp/project_results.json file not found"
    exit 1
fi

MAP_NAME="Properties"
echo "Checking if map view '$MAP_NAME' exists in Kibana..."

# Try to use jq if available to extract credentials
if command -v jq &> /dev/null; then
    echo "Using jq to parse JSON..."
    
    # Extract KIBANA_URL, USERNAME, and PASSWORD using jq
    KIBANA_URL=$(jq -r 'to_entries[0].value.endpoints.kibana' /tmp/project_results.json 2>/dev/null)
    USERNAME=$(jq -r 'to_entries[0].value.credentials.username' /tmp/project_results.json 2>/dev/null)
    PASSWORD=$(jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" = "null" ] || [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ] || [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then
        echo "Error: Could not extract Kibana URL, username, or password from project results"
        exit 1
    fi
else
    echo "Using grep/sed fallback to parse JSON..."
    # Fallback to grep/sed if jq is not available
    KIBANA_URL=$(grep -o '"kibana": "[^"]*"' /tmp/project_results.json | sed 's/"kibana": "\([^"]*\)"/\1/' 2>/dev/null)
    USERNAME=$(grep -o '"username": "[^"]*"' /tmp/project_results.json | sed 's/"username": "\([^"]*\)"/\1/' 2>/dev/null)
    PASSWORD=$(grep -o '"password": "[^"]*"' /tmp/project_results.json | sed 's/"password": "\([^"]*\)"/\1/' 2>/dev/null)
    
    # Validate the extracted values
    if [ -z "$KIBANA_URL" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        echo "Error: Could not extract Kibana URL, username, or password from project results"
        exit 1
    fi
fi

echo "Using Kibana URL: $KIBANA_URL"
echo "Username: $USERNAME"
echo "Password: ${PASSWORD:0:5}..."

# Embedded Python script to check if map view exists
python3 << EOF
import requests
import json
import sys

# Configuration
kibana_url = "$KIBANA_URL"
username = "$USERNAME"
password = "$PASSWORD"
map_name = "$MAP_NAME"

# Headers for Kibana API
headers = {
    'kbn-xsrf': 'true',
    'Content-Type': 'application/json'
}

try:
    # Try multiple Kibana APIs to find the map
    apis_to_try = [
        f"{kibana_url}/api/data_views",
        f"{kibana_url}/api/dashboards",
        f"{kibana_url}/api/visualizations",
        f"{kibana_url}/api/maps",
        f"{kibana_url}/api/maps/embeddable",
        f"{kibana_url}/api/content_management/objects",
        f"{kibana_url}/api/content_management/objects/_find"
    ]
    
    map_exists = False
    
    for api_url in apis_to_try:
        print(f"🔍 Debug: Trying API: {api_url}")
        try:
            response = requests.get(api_url, headers=headers, 
                                  auth=(username, password), timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                print(f"🔍 Debug: Raw API Response from {api_url}: {json.dumps(data, indent=2)}")
                
                # Check different response structures
                items = []
                if 'data_view' in data:
                    items = data.get('data_view', [])
                elif 'dashboards' in data:
                    items = data.get('dashboards', [])
                elif 'visualizations' in data:
                    items = data.get('visualizations', [])
                elif 'saved_objects' in data:
                    items = data.get('saved_objects', [])
                
                print(f"🔍 Debug: Found {len(items)} items in {api_url}")
                
                for i, item in enumerate(items):
                    print(f"🔍 Debug: Item {i} from {api_url}: {json.dumps(item, indent=2)}")
                    # Check if this item has the correct name
                    title = item.get('title') or item.get('name') or item.get('id', '')
                    # Check for exact match or if the title contains the map name (case insensitive)
                    if (title == map_name or 
                        title.lower() == map_name.lower() or
                        map_name.lower() in title.lower() or
                        title.lower().replace('*', '') == map_name.lower()):
                        map_exists = True
                        print(f"🔍 Debug: Found matching item: {title}")
                        break
                
                if map_exists:
                    break
            else:
                print(f"🔍 Debug: API {api_url} returned status {response.status_code}")
                
        except Exception as e:
            print(f"🔍 Debug: Error with API {api_url}: {e}")
            continue
    
    if map_exists:
        print(f"✓ Map view '{map_name}' exists in Kibana")
        sys.exit(0)
    else:
        print(f"✗ Map view '{map_name}' does not exist in Kibana")
        sys.exit(1)
        
except requests.exceptions.RequestException as e:
    print(f"Error connecting to Kibana: {e}")
    sys.exit(1)
except Exception as e:
    print(f"Unexpected error: {e}")
    sys.exit(1)
EOF

# Capture the exit code from Python
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Map view check completed successfully - map view exists"
    exit 0
else
    echo "Fail - Map view '$MAP_NAME' does not exist in Kibana"
    fail-message "Map view '$MAP_NAME' does not exist in Kibana"
fi 