#!/bin/bash
set -euxo pipefail

echo "Running track setup script on host es3-api-v1"


# Wait for the Instruqt host bootstrap to finish
until [ -f /opt/instruqt/bootstrap/host-bootstrap-completed ]
do
    sleep 1
done

echo "Project type: $PROJECT_TYPE"
echo "Regions: $REGIONS"

case "$PROJECT_TYPE" in
    "observability"|"security")
      python3 bin/es3-api.py \
        --operation create \
        --project-type $PROJECT_TYPE \
        --regions $REGIONS \
        --project-name $INSTRUQT_TRACK_SLUG-$INSTRUQT_PARTICIPANT_ID-`date '+%s'` \
        --api-key "$ESS_CLOUD_API_KEY" \
        --wait-for-ready
        ;;
    "elasticsearch")
      OPTIMIZED_FOR="${OPTIMIZED_FOR:-general_purpose}"
      echo "Optimized for: $OPTIMIZED_FOR"
      python3 bin/es3-api.py \
        --operation create \
        --project-type $PROJECT_TYPE \
        --optimized-for $OPTIMIZED_FOR \
        --regions $REGIONS \
        --project-name $INSTRUQT_TRACK_SLUG-$INSTRUQT_PARTICIPANT_ID-`date '+%s'` \
        --api-key "$ESS_CLOUD_API_KEY" \
        --wait-for-ready
        ;;
    *)
        echo "Error: Unknown project type '$PROJECT_TYPE'"
        exit 1
        ;;
esac

timeout=20
counter=0

while [ $counter -lt $timeout ]; do
    if [ -f "/tmp/project_results.json" ]; then
        echo "File found, continuing..."
        echo "Project results content:"
        cat /tmp/project_results.json
        echo ""
        break
    fi
    
    echo "Waiting for file /tmp/project_results.json... ($((counter + 1))/$timeout seconds)"
    sleep 1
    counter=$((counter + 1))
done

# Check if we timed out
if [ $counter -eq $timeout ]; then
    echo "Timeout: File /tmp/project_results.json not found after $timeout seconds"
    exit 1
fi

export KIBANA_URL=`jq -r 'to_entries[0].value.endpoints.kibana' /tmp/project_results.json`
export ELASTICSEARCH_PASSWORD=`jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json`
export ES_URL=`jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json`

# Extract values from project results JSON
ES_KIBANA_URL_VALUE=$(jq -r 'to_entries[0].value.endpoints.kibana' /tmp/project_results.json)
ES_USERNAME_VALUE=$(jq -r 'to_entries[0].value.credentials.username' /tmp/project_results.json)
ES_PASSWORD_VALUE=$(jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json)
ES_DEPLOYMENT_ID_VALUE=$(jq -r 'to_entries[0].value.id' /tmp/project_results.json)
ES_URL_VALUE=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json)

# Set agent variables
agent variable set ES_KIBANA_URL "$ES_KIBANA_URL_VALUE"
agent variable set ES_USERNAME "$ES_USERNAME_VALUE"
agent variable set ES_PASSWORD "$ES_PASSWORD_VALUE"
agent variable set ES_DEPLOYMENT_ID "$ES_DEPLOYMENT_ID_VALUE"
agent variable set ES_URL "$ES_URL_VALUE"


BASE64=$(echo -n "admin:${ELASTICSEARCH_PASSWORD}" | base64)
KIBANA_URL_WITHOUT_PROTOCOL=$(echo $KIBANA_URL | sed -e 's#http[s]\?://##g')

echo "Configure NGINX"
# Configure nginx
echo '
server { 
  listen 8080 default_server;
  server_name kibana;
  location /nginx_status {
    stub_status on;
    allow 127.0.0.1;
    deny all;
  }
  location / {
    proxy_set_header Host '${KIBANA_URL_WITHOUT_PROTOCOL}';
    proxy_pass '${KIBANA_URL}';
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    proxy_set_header Connection "";
    #proxy_hide_header Content-Security-Policy;
    proxy_set_header X-Scheme $scheme;
    proxy_set_header Authorization "Basic '${BASE64}'";
    proxy_set_header Accept-Encoding "";
    proxy_redirect off;
    proxy_http_version 1.1;
    client_max_body_size 20M;
    proxy_read_timeout 600;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains;";
    proxy_send_timeout          300;
    send_timeout                300;
    proxy_connect_timeout       300;
 }
}

server {
  listen 9200;
  server_name elasticsearch;
  
  location / {
    proxy_pass '${ES_URL}';
    proxy_connect_timeout       300;
    proxy_send_timeout          300;
    proxy_read_timeout          300;
    send_timeout                300;
  }
}
' > /etc/nginx/conf.d/default.conf

echo "Restart NGINX"
systemctl restart nginx


##create api key
echo "Creating ES API Key"


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

ES_USERNAME=$(jq -r 'to_entries[0].value.credentials.username' /tmp/project_results.json)
ES_PASSWORD=$(jq -r 'to_entries[0].value.credentials.password' /tmp/project_results.json)

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
    # Get the first (and only) region key from the JSON
    first_region = list(project_data.keys())[0]
    existing_encoded_api_key = project_data.get(first_region, {}).get("credentials", {}).get("api_key")
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
        project_data[first_region]["credentials"]["api_key"] = encoded_api_key
        
        # Write back to file
        with open("/tmp/project_results.json", "w") as f:
            json.dump(project_data, f, indent=2)
        print(f"Encoded API key added to project results JSON under credentials")
        
        
    except Exception as e:
        print(f"Error creating API key: {e}")
        exit(1)
else:
    print(f"API key ID already exists in project results JSON")
    print(f"Existing encoded API key will be read from project results JSON")
EOF

echo "API key creation completed successfully."

# Set ES_API_KEY agent variable from project results JSON (consistent with other variables)
ES_API_KEY_VALUE=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json)
agent variable set ES_API_KEY "$ES_API_KEY_VALUE"


###################
# Request API key from LLM Proxy

MAX_RETRIES=5
RETRY_WAIT=5

if [ -z "${SA_LLM_PROXY_BEARER_TOKEN}" ]; then
    LLM_PROXY_BEARER_TOKEN=$LLM_PROXY_PROD
else
    LLM_PROXY_BEARER_TOKEN=$SA_LLM_PROXY_BEARER_TOKEN
fi



for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $attempt of $MAX_RETRIES at $(date)"

    # Set default values for INSTRUQT variables if not set
    INSTRUQT_TRACK_INVITE_ID="${INSTRUQT_TRACK_INVITE_ID:-Testing-no-invite-link}"
    INSTRUQT_USER_ID="${INSTRUQT_USER_ID:-NOT_SET}"
    INSTRUQT_USER_EMAIL="${INSTRUQT_USER_EMAIL:-NOT_SET}"


    
    output=$(curl -X POST -s "https://$LLM_URL/key/generate" \
    -H "Authorization: Bearer $LLM_PROXY_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"models\": $LLM_MODELS,
      \"duration\": \"$LLM_KEY_DURATION\",
      \"key_alias\": \"instruqt-$_SANDBOX_ID\",
      \"max_budget\": $LLM_KEY_MAX_BUDGET,
      \"metadata\": {
        \"workshopId\": \"$WORKSHOP_KEY\",
        \"inviteId\": \"$INSTRUQT_TRACK_INVITE_ID\"
      }
    }")

    echo "=== LLM PROXY API RESPONSE ==="
    echo "$output"
    echo "=== END LLM PROXY RESPONSE ==="

    OPENAI_API_KEY=$(echo $output | jq -r '.key')
    
    if [ -z "${OPENAI_API_KEY}" ]; then
        echo "Failed to extract API key from response on attempt $attempt"
        [ $attempt -lt $MAX_RETRIES ] && sleep $RETRY_WAIT
    else
        echo "Request successful and API key extracted on attempt $attempt"
        echo "OPENAI_API_KEY: $OPENAI_API_KEY"
        break
    fi
done

[ -z "$OPENAI_API_KEY" ] && echo "Failed to retrieve API key after $MAX_RETRIES attempts" && exit 1

agent variable set LLM_KEY $OPENAI_API_KEY
agent variable set LLM_HOST $LLM_URL
agent variable set LLM_CHAT_URL https://$LLM_URL/v1/chat/completions

# Add LLM API key results to project results JSON
echo "Adding LLM API key results to project results JSON..."
python3 <<EOF
import json
import os

# Read existing project results
with open("/tmp/project_results.json", "r") as f:
    project_data = json.load(f)

# Add LLM credentials to the JSON structure
# Get the first (and only) region key from the JSON
first_region = list(project_data.keys())[0]

if "credentials" not in project_data[first_region]:
    project_data[first_region]["credentials"] = {}

# Add the three LLM-related values
project_data[first_region]["credentials"]["llm_api_key"] = "$OPENAI_API_KEY"
project_data[first_region]["credentials"]["llm_host"] = "$LLM_URL"
project_data[first_region]["credentials"]["llm_chat_url"] = "https://$LLM_URL/v1/chat/completions"

# Write back to file
with open("/tmp/project_results.json", "w") as f:
    json.dump(project_data, f, indent=2)

print("LLM API key results added to project results JSON")
EOF

#!/bin/bash
echo "Restart NGINX"
systemctl restart nginx

echo "Setting up JSON server on port 8081..."

# Check if the JSON file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Warning: /tmp/project_results.json not found!"
    echo "The server will return an error when accessed."
fi

# Assume nothing is running on port 8081
echo "Starting JSON server on port 8081..."

# Start the server in background
echo "Starting JSON server in background..."
python3 bin/serve_json.py > /tmp/server-serve-json.log 2>&1 &

# Get the process ID
SERVER_PID=$!

# Wait a moment for the server to start
sleep 2

# Check if server started successfully
sleep 2
if kill -0 $SERVER_PID 2>/dev/null; then
    echo ":white_check_mark: Server started successfully!"
    echo ":bar_chart: Server PID: $SERVER_PID"
    echo ":memo: Logs: /tmp/server-serve-json.log"
    echo ":globe_with_meridians: Access URL: http://localhost:8081"
    echo ""
    echo ":clipboard: Useful commands:"
    echo "  View logs: tail -f /tmp/server-serve-json.log"
    echo "  Test server: curl http://localhost:8081"
    echo "  Stop server: kill $SERVER_PID"
    echo "  Check status: ps aux | grep serve_json"
else
    echo ":x: Failed to start server"
    echo "Check /tmp/server-serve-json.log for details:"
    if [ -f "/tmp/server-serve-json.log" ]; then
        tail -5 /tmp/server-serve-json.log
    else
        echo "No log file found"
    fi
    exit 1
fi 

# Wake up Elasticsearch inference models
echo "Waking up Elasticsearch inference models..."

# Ensure elasticsearch package is installed in venv
source /tmp/venv/bin/activate
pip install --quiet elasticsearch==9.1.1

python3 << 'EOF'
import json
import logging
import time
import os
from elasticsearch import Elasticsearch

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration
TIMEOUT = 300  # 300 seconds timeout

# Read API key and Elasticsearch URL from project results JSON file
def get_elasticsearch_config():
    """Read API key and Elasticsearch URL from project results JSON file"""
    try:
        with open("/tmp/project_results.json", "r") as f:
            project_data = json.load(f)
        
        # Get the first region's data
        first_region = list(project_data.keys())[0]
        region_data = project_data[first_region]
        
        # Get API key from credentials
        api_key = region_data["credentials"]["api_key"]
        
        # Get Elasticsearch URL from endpoints
        elasticsearch_url = region_data["endpoints"]["elasticsearch"]
        
        logger.info("API key and Elasticsearch URL loaded successfully from project results")
        return api_key, elasticsearch_url
    except Exception as e:
        logger.error(f"Failed to read configuration from /tmp/project_results.json: {e}")
        raise

# Get API key and Elasticsearch URL
API_KEY, ELASTICSEARCH_URL = get_elasticsearch_config()

# Initialize Elasticsearch client
es = Elasticsearch(
    [ELASTICSEARCH_URL],
    api_key=API_KEY,
    request_timeout=TIMEOUT,
    verify_certs=False
)

# Inference model IDs from environment variables
ELSER_INFERENCE_ID = os.environ.get('ELSER_INFERENCE_ID', '.elser-2-elasticsearch')
E5_INFERENCE_ID = os.environ.get('E5_INFERENCE_ID', '.multilingual-e5-small-elasticsearch')
RERANKER_INFERENCE_ID = os.environ.get('RERANK_INFERENCE_ID', '.rerank-elasticsearch')

def wake_up_e5():
    """Wake up E5 model with retry logic"""
    logger.info(f"Waking up E5 model: {E5_INFERENCE_ID}")
    
    max_retries = 30
    retry_delay = 10
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempt {attempt + 1}/{max_retries} to wake up E5 model...")
            e5_response = es.inference.inference(
                inference_id=E5_INFERENCE_ID,
                input=['vector are so much fun'],
                timeout="60s"
            )
            logger.info("E5 model woken up successfully")
            return e5_response
                    
        except Exception as e:
            error_msg = str(e)
            logger.info(f"Attempt {attempt + 1} failed: {error_msg}")
            
            # Check if it's a model deployment timeout or not ready error
            if ("408" in error_msg or "model_deployment_timeout_exception" in error_msg or 
                "503" in error_msg or "500" in error_msg or "model" in error_msg.lower() or 
                "not ready" in error_msg.lower() or "timeout" in error_msg.lower() or 
                "deployment" in error_msg.lower()):
                if attempt < max_retries - 1:
                    logger.info(f"Model still deploying, retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)
                else:
                    logger.error("Max retries reached for E5 wake-up - model deployment failed")
                    raise Exception(f"E5 model failed to deploy after {max_retries} attempts: {error_msg}")
            else:
                logger.error(f"Unexpected error during E5 wake-up: {e}")
                raise Exception(f"Unexpected error during E5 wake-up: {error_msg}")


def wake_up_elser():
    """Wake up ELSER model with retry logic"""
    logger.info(f"Waking up ELSER model: {ELSER_INFERENCE_ID}")
    
    max_retries = 30
    retry_delay = 10
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempt {attempt + 1}/{max_retries} to wake up ELSER model...")
            elser_response = es.inference.inference(
                inference_id=ELSER_INFERENCE_ID,
                input=['sparse vectors are so much fun'],
                timeout="60s"
            )
            logger.info("ELSER model woken up successfully")
            return elser_response
                    
        except Exception as e:
            error_msg = str(e)
            logger.info(f"Attempt {attempt + 1} failed: {error_msg}")
            
            # Check if it's a model deployment timeout or not ready error
            if ("408" in error_msg or "model_deployment_timeout_exception" in error_msg or 
                "503" in error_msg or "500" in error_msg or "model" in error_msg.lower() or 
                "not ready" in error_msg.lower() or "timeout" in error_msg.lower() or 
                "deployment" in error_msg.lower()):
                if attempt < max_retries - 1:
                    logger.info(f"Model still deploying, retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)
                else:
                    logger.error("Max retries reached for ELSER wake-up - model deployment failed")
                    raise Exception(f"ELSER model failed to deploy after {max_retries} attempts: {error_msg}")
            else:
                logger.error(f"Unexpected error during ELSER wake-up: {e}")
                raise Exception(f"Unexpected error during ELSER wake-up: {error_msg}")


def wake_up_reranker():
    """Wake up reranker model using direct inference endpoint"""
    logger.info("Waking up reranker model...")
    
    max_retries = 30
    retry_delay = 2
    
    # Prepare rerank payload
    rerank_payload = {
        "input": [
            "Charlotte Amalie is the capital and largest city of the United States Virgin Islands.",
            "The Commonwealth of the Northern Mariana Islands is a group of islands in the Pacific Ocean.",
            "Carson City is the capital city of the American state of Nevada.",
            "Washington, D.C. is the capital of the United States.",
            "Capital punishment has existed in the United States since before the United States was a country.",
            "North Dakota is a state in the United States with Bismarck as its capital."
        ],
        "query": "What is the capital of the USA?"
    }
    
    logger.info("Attempting to call rerank inference endpoint...")
    logger.info(f"Payload: {json.dumps(rerank_payload, indent=2)}")
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempt {attempt + 1}/{max_retries}...")
            
            # Call the rerank inference endpoint using the Elasticsearch Python client
            response = es.inference.inference(
                inference_id=".rerank-v1-elasticsearch",
                input=rerank_payload["input"],
                query=rerank_payload["query"],
                task_type="rerank",
                timeout="600s"
            )
            
            logger.info("✓ Rerank inference successful!")
            logger.info(f"Response: {json.dumps(response.body, indent=2)}")
            return response
                    
        except Exception as e:
            error_msg = str(e)
            logger.info(f"Attempt {attempt + 1} failed: {error_msg}")
            
            # Check if it's a model not ready error or connection timeout
            if ("503" in error_msg or "500" in error_msg or "model" in error_msg.lower() or 
                "not ready" in error_msg.lower() or "timeout" in error_msg.lower() or 
                "connection" in error_msg.lower()):
                if attempt < max_retries - 1:
                    logger.info(f"Model not ready or connection issue, retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)
                else:
                    logger.warning("Max retries reached for reranker wake-up - reranker model never loaded")
                    return None
            else:
                logger.warning(f"Unexpected error during reranker wake-up: {e} - reranker model never loaded")
                return None

def main():
    """Main function to wake up all inference models"""
    logger.info("Starting to wake up inference models...")
    
    try:
        # Wake up E5 model
        wake_up_e5()
        
        # Wake up ELSER model
        wake_up_elser()
        
        # Wake up reranker model
        wake_up_reranker()
        
        logger.info("All inference models woken up successfully!")
        print(json.dumps({"success": True}))
        
    except Exception as e:
        logger.error(f"Error waking up inference models: {str(e)}")
        print(json.dumps({"success": False, "error": str(e)}))

if __name__ == "__main__":
    main()
EOF

if [ $? -eq 0 ]; then
    echo "Inference models woken up successfully!"
else
    echo "Error: Failed to wake up inference models"
    exit 1
fi

echo "done"

# Data ingestion section
echo "Starting data ingestion process..."

# Download the properties data from Azure blob storage
echo "Downloading properties data from Azure blob storage..."
curl -s "https://sunmanapp.blob.core.windows.net/publicstuff/properties/properties-filtered-500-lines_cleaned_redacted.json" -o /tmp/properties_data.json

# Create properties index using the mapping
echo "Creating properties index with mapping..."

python3 << 'EOF'
import json
import logging
import os
import time
from elasticsearch import Elasticsearch

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Properties index mapping
PROPERTIES_MAPPING = {
    "settings": {
        "analysis": {
            "analyzer": {
                "my_analyzer": {
                    "tokenizer": "whitespace",
                    "filter": [
                        "synonyms_filter"
                    ]
                }
            },
            "filter": {
                "synonyms_filter": {
                    "type": "synonym",
                    "synonyms_set": "property-details",
                    "updateable": True
                }
            }
        }
    },
    "mappings": {
        "dynamic": "false",
        "properties": {
            "additional_urls": {
                "type": "keyword"
            },
            "annual-tax": {
                "type": "integer"
            },
            "body_content": {
                "type": "text",
                "search_analyzer": "my_analyzer",
                "copy_to": [
                    "body_content_elser",
                    "body_content_e5"
                ]
            },
            "body_content_phrase": {
                "type": "text"
            },
            "body_content_elser": {
                "type": "semantic_text",
                "inference_id": ".elser-2-elastic",
                "model_settings": {
                    "task_type": "sparse_embedding"
                }
            },
            "body_content_e5": {
                "type": "semantic_text",
                "inference_id": ".multilingual-e5-small-elasticsearch",
                "model_settings": {
                    "task_type": "text_embedding",
                    "dimensions": 384,
                    "similarity": "cosine",
                    "element_type": "float"
                },
                "index_options": {
                    "dense_vector": {
                        "type": "flat"
                    }
                }
            },
            "domains": {
                "type": "keyword"
            },
            "full_html": {
                "type": "text",
                "index": False
            },
            "geo_point": {
                "properties": {
                    "lat": {
                        "type": "float"
                    },
                    "lon": {
                        "type": "float"
                    }
                }
            },
            "headings": {
                "type": "text"
            },
            "home-price": {
                "type": "integer"
            },
            "id": {
                "type": "keyword"
            },
            "last_crawled_at": {
                "type": "date"
            },
            "latitude": {
                "type": "float"
            },
            "links": {
                "type": "keyword"
            },
            "listing-agent-info": {
                "type": "text"
            },
            "location": {
                "type": "geo_point"
            },
            "longitude": {
                "type": "float"
            },
            "maintenance-fee": {
                "type": "integer"
            },
            "meta_description": {
                "type": "text"
            },
            "meta_keywords": {
                "type": "keyword"
            },
            "number-of-bathrooms": {
                "type": "float"
            },
            "number-of-bedrooms": {
                "type": "float"
            },
            "property-description": {
                "type": "text",
                "search_analyzer": "my_analyzer"
            },
            "property-features": {
                "type": "text",
                "search_analyzer": "my_analyzer"
            },
            "property-status": {
                "type": "keyword"
            },
            "square-footage": {
                "type": "float"
            },
            "title": {
                "type": "text"
            },
            "url": {
                "type": "keyword"
            },
            "url_host": {
                "type": "keyword"
            },
            "url_path": {
                "type": "keyword"
            },
            "url_path_dir1": {
                "type": "keyword"
            },
            "url_path_dir2": {
                "type": "keyword"
            },
            "url_path_dir3": {
                "type": "keyword"
            },
            "url_port": {
                "type": "keyword"
            },
            "url_scheme": {
                "type": "keyword"
            }
        }
    }
}

# Read API key and Elasticsearch URL from project results JSON file
def get_elasticsearch_config():
    """Read API key and Elasticsearch URL from project results JSON file"""
    try:
        with open("/tmp/project_results.json", "r") as f:
            project_data = json.load(f)
        
        # Get the first region's data
        first_region = list(project_data.keys())[0]
        region_data = project_data[first_region]
        
        # Get API key from credentials
        api_key = region_data["credentials"]["api_key"]
        
        # Get Elasticsearch URL from endpoints
        elasticsearch_url = region_data["endpoints"]["elasticsearch"]
        
        logger.info("API key and Elasticsearch URL loaded successfully from project results")
        return api_key, elasticsearch_url
    except Exception as e:
        logger.error(f"Failed to read configuration from /tmp/project_results.json: {e}")
        raise

# Get API key and Elasticsearch URL
API_KEY, ELASTICSEARCH_URL = get_elasticsearch_config()

# Initialize Elasticsearch client
es = Elasticsearch(
    [ELASTICSEARCH_URL],
    api_key=API_KEY,
    request_timeout=300,
    verify_certs=False
)


# Create the properties index
def create_properties_index():
    """Create the properties index with the specified mapping"""
    index_name = "properties"
    
    try:
        # Check if index already exists
        if es.indices.exists(index=index_name):
            logger.info(f"Index {index_name} already exists. Deleting it first...")
            es.indices.delete(index=index_name)
        
        # Use the embedded mapping
        mapping = PROPERTIES_MAPPING
        
        # Create the index with mapping
        es.indices.create(index=index_name, body=mapping)
        logger.info(f"Index {index_name} created successfully with mapping")
        
    except Exception as e:
        logger.error(f"Failed to create index {index_name}: {e}")
        raise

# Ingest the properties data
def ingest_properties_data():
    """Ingest the properties data into the index using individual indexing with retry logic"""
    index_name = "properties"
    
    try:
        # Read the properties data (handling both JSON array and JSONL formats)
        properties_data = []
        with open("/tmp/properties_data.json", "r") as f:
            content = f.read().strip()
            
            # Try to parse as single JSON array first
            try:
                properties_data = json.loads(content)
                logger.info(f"Loaded {len(properties_data)} properties from JSON array format")
            except json.JSONDecodeError:
                # If that fails, try parsing as JSONL (one JSON object per line)
                logger.info("JSON array format failed, trying JSONL format...")
                for line_num, line in enumerate(content.split('\n'), 1):
                    line = line.strip()
                    if line:  # Skip empty lines
                        try:
                            property_doc = json.loads(line)
                            properties_data.append(property_doc)
                        except json.JSONDecodeError as e:
                            logger.warning(f"Skipping invalid JSON on line {line_num}: {e}")
                
                logger.info(f"Loaded {len(properties_data)} properties from JSONL format")
        
        if not properties_data:
            raise ValueError("No valid property data found in the file")
        
        # Index documents in small batches to avoid ELSER connection issues
        successful_count = 0
        failed_count = 0
        batch_size = 100
        max_retries = 3
        retry_delay = 2
        
        logger.info(f"Starting batch indexing of {len(properties_data)} documents in batches of {batch_size}...")
        
        # Process documents in batches
        for batch_start in range(0, len(properties_data), batch_size):
            batch_end = min(batch_start + batch_size, len(properties_data))
            batch_docs = properties_data[batch_start:batch_end]
            
            logger.info(f"Processing batch {batch_start//batch_size + 1}: documents {batch_start + 1}-{batch_end}")
            
            # Retry logic for each batch
            for attempt in range(max_retries):
                try:
                    # Prepare bulk request for this batch
                    bulk_data = ""
                    for i, property_doc in enumerate(batch_docs):
                        doc_id = str(batch_start + i)
                        bulk_data += json.dumps({"index": {"_index": index_name, "_id": doc_id}}) + "\n"
                        bulk_data += json.dumps(property_doc) + "\n"
                    
                    # Send bulk request for this batch
                    response = es.bulk(body=bulk_data, timeout="60s")
                    
                    # Count successful and failed documents in this batch
                    batch_successful = 0
                    batch_failed = 0
                    
                    if response.get("errors"):
                        for item in response["items"]:
                            if "index" in item:
                                if "error" in item["index"]:
                                    batch_failed += 1
                                    error_msg = str(item["index"]["error"])
                                    
                                    # Check if it's an ELSER connection error
                                    if ("inference_exception" in error_msg and "Connection is closed" in error_msg) or \
                                       ("503" in error_msg or "500" in error_msg):
                                        logger.warning(f"Document {item['index']['_id']} failed with ELSER error: {error_msg}")
                                    else:
                                        logger.error(f"Document {item['index']['_id']} failed with non-ELSER error: {error_msg}")
                                else:
                                    batch_successful += 1
                    else:
                        batch_successful = len(batch_docs)
                    
                    successful_count += batch_successful
                    failed_count += batch_failed
                    
                    logger.info(f"Batch completed: {batch_successful} successful, {batch_failed} failed")
                    break  # Success, move to next batch
                    
                except Exception as e:
                    error_msg = str(e)
                    
                    # Check if it's an ELSER connection error
                    if ("inference_exception" in error_msg and "Connection is closed" in error_msg) or \
                       ("503" in error_msg or "500" in error_msg):
                        
                        if attempt < max_retries - 1:
                            logger.warning(f"Batch {batch_start//batch_size + 1} attempt {attempt + 1} failed with ELSER error, retrying in {retry_delay}s: {error_msg}")
                            time.sleep(retry_delay)
                        else:
                            logger.error(f"Batch {batch_start//batch_size + 1} failed after {max_retries} attempts: {error_msg}")
                            failed_count += len(batch_docs)
                    else:
                        # Non-ELSER error, don't retry
                        logger.error(f"Batch {batch_start//batch_size + 1} failed with non-ELSER error: {error_msg}")
                        failed_count += len(batch_docs)
                        break
            
            # Small delay between batches to be gentle on the ELSER service
            if batch_end < len(properties_data):
                time.sleep(0.5)
        
        logger.info(f"Indexing completed: {successful_count} successful, {failed_count} failed")
        
        if failed_count > 0:
            logger.warning(f"{failed_count} documents failed to index, but continuing...")
        
        return {"successful": successful_count, "failed": failed_count}
        
    except Exception as e:
        logger.error(f"Failed to ingest properties data: {e}")
        raise

def main():
    """Main function to create index and ingest data"""
    logger.info("Starting properties data ingestion...")
    
    try:
        # Create the properties index
        create_properties_index()
        
        # Ingest the data
        ingest_properties_data()
        
        logger.info("Properties data ingestion completed successfully!")
        print(json.dumps({"success": True, "message": "Properties data ingested successfully"}))
        
    except Exception as e:
        logger.error(f"Error during properties data ingestion: {str(e)}")
        print(json.dumps({"success": False, "error": str(e)}))

if __name__ == "__main__":
    main()
EOF

if [ $? -eq 0 ]; then
    echo "Properties data ingestion completed successfully!"
else
    echo "Warning: Properties data ingestion failed"
fi

# Rerank demo index creation and data ingestion section
echo "Starting rerank-demo index creation and data ingestion process..."

python3 << 'EOF'
import json
import logging
import os
import time
from elasticsearch import Elasticsearch

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Rerank demo index mapping
RERANK_DEMO_MAPPING = {
    "mappings": {
        "properties": {
            "content": {
                "type": "text"
            }
        }
    }
}

# Rerank demo documents
RERANK_DEMO_DOCUMENTS = [
    {"content": "Charlotte Amalie is the capital and largest city of the United States Virgin Islands. It has about 20,000 people. The city is on the island of Saint Thomas."},
    {"content": "The Commonwealth of the Northern Mariana Islands is a group of islands in the Pacific Ocean that are a political division controlled by the United States. Its capital is Saipan."},
    {"content": "Carson City is the capital city of the American state of Nevada. At the 2010 United States Census, Carson City had a population of 55,274."},
    {"content": "Washington, D.C. (also known as simply Washington or D.C., and officially as the District of Columbia) is the capital of the United States. It is a federal district."},
    {"content": "Capital punishment (the death penalty) has existed in the United States since before the United States was a country. As of 2017, capital punishment is legal in 30 of the 50 states."},
    {"content": "North Dakota is a state in the United States. 672,591 people lived in North Dakota in the year 2010. The capital and seat of government is Bismarck."},
    {"content": "Capital Markets LLC is a major financial institution based in New York. The company manages over $50 billion in assets and has offices throughout the USA."},
    {"content": "The capital requirements for banks in the United States are regulated by the Federal Reserve. These capital ratios ensure financial stability."},
    {"content": "Silicon Valley is often called the tech capital of the world. Many USA-based technology companies are headquartered in this region of California."},
    {"content": "Human capital is considered one of the most important resources for USA businesses. Companies invest billions in training and development programs."},
    {"content": "The capital gains tax in the United States varies depending on how long you hold an investment. Short-term capital gains are taxed as ordinary income."}
]

# Read API key and Elasticsearch URL from project results JSON file
def get_elasticsearch_config():
    """Read API key and Elasticsearch URL from project results JSON file"""
    try:
        with open("/tmp/project_results.json", "r") as f:
            project_data = json.load(f)
        
        # Get the first region's data
        first_region = list(project_data.keys())[0]
        region_data = project_data[first_region]
        
        # Get API key from credentials
        api_key = region_data["credentials"]["api_key"]
        
        # Get Elasticsearch URL from endpoints
        elasticsearch_url = region_data["endpoints"]["elasticsearch"]
        
        logger.info("API key and Elasticsearch URL loaded successfully from project results")
        return api_key, elasticsearch_url
    except Exception as e:
        logger.error(f"Failed to read configuration from /tmp/project_results.json: {e}")
        raise

# Get API key and Elasticsearch URL
API_KEY, ELASTICSEARCH_URL = get_elasticsearch_config()

# Initialize Elasticsearch client
es = Elasticsearch(
    [ELASTICSEARCH_URL],
    api_key=API_KEY,
    request_timeout=300,
    verify_certs=False
)

# Create the rerank-demo index
def create_rerank_demo_index():
    """Create the rerank-demo index with the specified mapping"""
    index_name = "rerank-demo"
    
    try:
        # Check if index already exists
        if es.indices.exists(index=index_name):
            logger.info(f"Index {index_name} already exists. Deleting it first...")
            es.indices.delete(index=index_name)
        
        # Create the index with mapping
        es.indices.create(index=index_name, body=RERANK_DEMO_MAPPING)
        logger.info(f"Index {index_name} created successfully with mapping")
        
    except Exception as e:
        logger.error(f"Failed to create index {index_name}: {e}")
        raise

# Ingest the rerank-demo documents
def ingest_rerank_demo_data():
    """Ingest the rerank-demo documents into the index using bulk indexing"""
    index_name = "rerank-demo"
    
    try:
        logger.info(f"Starting bulk indexing of {len(RERANK_DEMO_DOCUMENTS)} documents...")
        
        # Prepare bulk request
        bulk_data = ""
        for i, doc in enumerate(RERANK_DEMO_DOCUMENTS):
            bulk_data += json.dumps({"index": {"_index": index_name}}) + "\n"
            bulk_data += json.dumps(doc) + "\n"
        
        # Send bulk request
        response = es.bulk(body=bulk_data, timeout="60s")
        
        # Check for errors
        successful_count = 0
        failed_count = 0
        
        if response.get("errors"):
            for item in response["items"]:
                if "index" in item:
                    if "error" in item["index"]:
                        failed_count += 1
                        error_msg = str(item["index"]["error"])
                        logger.error(f"Document {item['index'].get('_id', 'unknown')} failed: {error_msg}")
                    else:
                        successful_count += 1
        else:
            successful_count = len(RERANK_DEMO_DOCUMENTS)
        
        logger.info(f"Bulk indexing completed: {successful_count} successful, {failed_count} failed")
        
        if failed_count > 0:
            logger.warning(f"{failed_count} documents failed to index")
            raise Exception(f"{failed_count} documents failed to index")
        
        return {"successful": successful_count, "failed": failed_count}
        
    except Exception as e:
        logger.error(f"Failed to ingest rerank-demo data: {e}")
        raise

def main():
    """Main function to create index and ingest data"""
    logger.info("Starting rerank-demo index creation and data ingestion...")
    
    try:
        # Create the rerank-demo index
        create_rerank_demo_index()
        
        # Ingest the data
        ingest_rerank_demo_data()
        
        logger.info("Rerank-demo index creation and data ingestion completed successfully!")
        print(json.dumps({"success": True, "message": "Rerank-demo index created and data ingested successfully"}))
        
    except Exception as e:
        logger.error(f"Error during rerank-demo index creation and data ingestion: {str(e)}")
        print(json.dumps({"success": False, "error": str(e)}))
        raise

if __name__ == "__main__":
    main()
EOF

if [ $? -eq 0 ]; then
    echo "Rerank-demo index creation and data ingestion completed successfully!"
else
    echo "Warning: Rerank-demo index creation and data ingestion failed"
fi