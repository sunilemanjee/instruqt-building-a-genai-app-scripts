#!/bin/bash
set -euxo pipefail  # Ensure script exits on errors

# Define Kibana variables
KIBANA_URL="http://es3-api-v1:8080"
DATA_VIEW_NAME="hotels"

# Get the region from environment or use a default
REGIONS=${REGIONS:-"us-east-1"}

# Extract API key from project results JSON
if [ ! -f "/tmp/project_results.json" ]; then
    echo "❌ Project results JSON file not found at /tmp/project_results.json" >&2
    exit 1
fi

ES_API_KEY=$(jq -r --arg region "$REGIONS" '.[$region].credentials.api_key' /tmp/project_results.json)

if [ "$ES_API_KEY" = "null" ] || [ -z "$ES_API_KEY" ]; then
    echo "❌ Failed to extract API key from project results JSON for region: $REGIONS" >&2
    exit 1
fi

echo "🔑 Using API key for region: $REGIONS"

# ✅ Run Python script and capture its return value
PYTHON_EXIT_CODE=$(python3 <<EOF
import os
import requests

# Kibana API Configuration
DATA_VIEW_NAME = "hotels"
KIBANA_URL = "http://es3-api-v1:8080"

# Get API key from bash variable
API_KEY = "$ES_API_KEY"
if not API_KEY:
    print("❌ API key is required")
    print(40)  # ❌ Return error code for missing API key
    exit(0)

# Define API URL to check data views - using a different endpoint
API_URL = f"{KIBANA_URL}/api/data_views"

try:
    response = requests.get(
        API_URL,
        headers={
            "kbn-xsrf": "true", 
            "Content-Type": "application/json",
            "Authorization": f"ApiKey {API_KEY}"
        }
    )

    print(f"🔍 Raw API Response: {response.text}")  # ✅ Debugging: Print response

    if response.status_code == 200:
        data = response.json()
        # Check if the data view exists in the response
        # The response structure is {"data_view": [...]}
        data_views = data.get("data_view", [])
        found = any(
            DATA_VIEW_NAME.lower() in (
                item.get("title", "").lower(),
                item.get("name", "").lower(),
                item.get("id", "").lower()
            )
            for item in data_views
        )

        if found:
            print(f"✅ Data view '{DATA_VIEW_NAME}' exists in Kibana.")
            print(0)  # ✅ Return success code
        else:
            print(f"❌ Data view '{DATA_VIEW_NAME}' does not exist in Kibana.")
            print(10)  # ❌ Return error code for missing data view

    else:
        print(f"❌ Failed to connect to Kibana. Status: {response.status_code}")
        print(20)  # ❌ Return error code for connection failure

except requests.RequestException as e:
    print(f"❌ Error connecting to Kibana: {e}")
    print(30)  # ❌ Return error code for request failure
EOF
)

# ✅ Extract the last line as the Python return code
PYTHON_EXIT_CODE=$(echo "$PYTHON_EXIT_CODE" | tail -n 1)

# ✅ Debugging: Print the captured exit code
echo "🐍 Python returned exit code: $PYTHON_EXIT_CODE"

# ✅ Handle errors in Bash
if [[ "$PYTHON_EXIT_CODE" -eq 10 ]]; then
    fail-message "Data view '${DATA_VIEW_NAME}' does not exist. It must be created as '${DATA_VIEW_NAME}' (case-sensitive) in Kibana."
    exit 1
elif [[ "$PYTHON_EXIT_CODE" -eq 20 ]]; then
    fail-message "Failed to connect to Kibana. Please check the URL and credentials."
    exit 1
elif [[ "$PYTHON_EXIT_CODE" -eq 30 ]]; then
    fail-message "Error occurred while connecting to Kibana."
    exit 1
elif [[ "$PYTHON_EXIT_CODE" -eq 40 ]]; then
    echo "❌ API key is required but not provided." >&2
    exit 1
else
    echo "✅ No errors detected."
fi
