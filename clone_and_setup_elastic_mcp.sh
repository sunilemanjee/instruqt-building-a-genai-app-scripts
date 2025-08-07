#!/bin/bash

###################
# Parse command line arguments
SKIP_INGESTION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-ingestion|--no-ingestion)
            SKIP_INGESTION=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --skip-ingestion, --no-ingestion    Skip the data ingestion step"
            echo "  -h, --help                          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done





# Script to clone Elastic-Python-MCP-Server and setup environment config

# Fetch project results and store in /tmp/project_results.json
echo "Fetching project results from $PROXY_ES_KEY_BROKER..."

MAX_RETRIES=10
RETRY_WAIT=30

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $attempt of $MAX_RETRIES at $(date)"
    
    # Fetch the response
    curl -s $PROXY_ES_KEY_BROKER > /tmp/project_results.json
    
    if [ $? -eq 0 ]; then
        echo "Project results saved to /tmp/project_results.json"
        echo "Project results content:"
        cat /tmp/project_results.json
        echo ""
        
        # Check if the response contains valid JSON and has the api_key
        if command -v jq &> /dev/null; then
            # Use jq to validate JSON and extract api_key, ES_URL, and KIBANA_URL
            # Get the first (and only) region key from the JSON
            API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json 2>/dev/null)
            ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
            KIBANA_URL=$(jq -r 'to_entries[0].value.endpoints.kibana' /tmp/project_results.json 2>/dev/null)

            echo "Reading LLM credentials from /tmp/project_results.json..."
            # Extract LLM credentials from the JSON file
            OPENAI_API_KEY=$(jq -r 'to_entries[0].value.credentials.llm_api_key' /tmp/project_results.json)
            LLM_HOST=$(jq -r 'to_entries[0].value.credentials.llm_host' /tmp/project_results.json)
            LLM_CHAT_URL=$(jq -r 'to_entries[0].value.credentials.llm_chat_url' /tmp/project_results.json)
            echo "OPENAI_API_KEY: $OPENAI_API_KEY"
            echo "LLM_HOST: $LLM_HOST"
            echo "LLM_CHAT_URL: $LLM_CHAT_URL"

            # Set agent variables with the retrieved LLM credentials
            agent variable set LLM_KEY $OPENAI_API_KEY
            agent variable set LLM_HOST $LLM_HOST
            agent variable set LLM_CHAT_URL $LLM_CHAT_URL
            
            if [ $? -eq 0 ] && [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ] && [ ! -z "$ES_URL" ] && [ "$ES_URL" != "null" ] && [ ! -z "$KIBANA_URL" ] && [ "$KIBANA_URL" != "null" ] && [ ! -z "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "null" ] && [ ! -z "$LLM_HOST" ] && [ "$LLM_HOST" != "null" ] && [ ! -z "$LLM_CHAT_URL" ] && [ "$LLM_CHAT_URL" != "null" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                echo "ES URL found: $ES_URL"
                echo "Kibana URL found: $KIBANA_URL"
                # Set agent variables
                echo "Setting agent variable ES_API_KEY..."
                agent variable set ES_API_KEY "$API_KEY"
                echo "Setting agent variable ES_URL..."
                agent variable set ES_URL "$ES_URL"
                echo "Setting agent variable KIBANA_URL..."
                agent variable set KIBANA_URL "$KIBANA_URL"
                break
            else
                echo "API key, ES URL, or Kibana URL not found or invalid in response on attempt $attempt"
                [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
            fi
        else
            # Fallback to grep/sed if jq is not available
            API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
            ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
            KIBANA_URL=$(grep -o '"kibana": "[^"]*"' /tmp/project_results.json | sed 's/"kibana": "\([^"]*\)"/\1/' 2>/dev/null)
            
            if [ ! -z "$API_KEY" ] && [ ! -z "$ES_URL" ] && [ ! -z "$KIBANA_URL" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                echo "ES URL found: $ES_URL"
                echo "Kibana URL found: $KIBANA_URL"
                # Set agent variables
                echo "Setting agent variable ES_API_KEY..."
                agent variable set ES_API_KEY "$API_KEY"
                echo "Setting agent variable ES_URL..."
                agent variable set ES_URL "$ES_URL"
                echo "Setting agent variable KIBANA_URL..."
                agent variable set KIBANA_URL "$KIBANA_URL"
                break
            else
                echo "API key, ES URL, or Kibana URL not found in response on attempt $attempt"
                [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
            fi
        fi
    else
        echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
        [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
    fi
done

# Check if we successfully got the API key and URLs after all attempts
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ] || [ -z "$ES_URL" ] || [ "$ES_URL" = "null" ] || [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" = "null" ] || [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "null" ] || [ -z "$LLM_HOST" ] || [ "$LLM_HOST" = "null" ] || [ -z "$LLM_CHAT_URL" ] || [ "$LLM_CHAT_URL" = "null" ]; then
    echo "Error: Failed to retrieve valid API key, ES URL, Kibana URL, or LLM credentials after $MAX_RETRIES attempts"
    echo "Last response content:"
    cat /tmp/project_results.json
    exit 1
fi

echo "Cloning Elastic-Python-MCP-Server repository..."

# Ensure we're in /root before cloning
cd /root

# Remove repository if it already exists
if [ -d "Elastic-Python-MCP-Server" ]; then
    echo "Removing existing Elastic-Python-MCP-Server directory..."
    rm -rf Elastic-Python-MCP-Server
fi

# Clone the repository
git clone https://github.com/sunilemanjee/Elastic-Python-MCP-Server.git

# Check if clone was successful
if [ $? -eq 0 ]; then
    echo "Repository cloned successfully!"
    
    # Change to the cloned directory
    cd /root/Elastic-Python-MCP-Server
    echo "Changed to directory: $(pwd)"
    
    # Check for environment config files and update them
    if [ -f "env_config.sh" ]; then
        CONFIG_FILE="env_config.sh"
    elif [ -f "env_config.template.sh" ]; then
        CONFIG_FILE="env_config.template.sh"
        # Rename template to actual config file
        mv env_config.template.sh env_config.sh
        CONFIG_FILE="env_config.sh"
        echo "Renamed env_config.template.sh to env_config.sh"
    else
        echo "Warning: No environment config file found in the repository."
        echo "Available files:"
        ls -la
        exit 1
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        echo "Updating ES_URL in $CONFIG_FILE..."
        sed -i 's|export ES_URL="[^"]*"|export ES_URL="'"$ES_URL"'"|' "$CONFIG_FILE"
        echo "ES_URL updated to $ES_URL"
        
        # Use the API key that was already extracted in the retry loop above
        if [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ]; then
            echo "Using API key retrieved from retry loop"
            # Update the ES_API_KEY in config file
            sed -i 's|export ES_API_KEY="[^"]*"|export ES_API_KEY="'"$API_KEY"'"|' "$CONFIG_FILE"
            echo "ES_API_KEY updated in $CONFIG_FILE"
        else
            echo "Error: No valid API key available for config file"
            exit 1
        fi
        
        # Update KIBANA_URL
        echo "Updating KIBANA_URL in $CONFIG_FILE..."
        sed -i 's|export KIBANA_URL="[^"]*"|export KIBANA_URL="'"$KIBANA_URL"'"|' "$CONFIG_FILE"
        echo "KIBANA_URL updated to $KIBANA_URL"
        
        # Update Google Maps API key
        echo "Updating GOOGLE_MAPS_API_KEY in $CONFIG_FILE..."
        sed -i 's|export GOOGLE_MAPS_API_KEY="[^"]*"|export GOOGLE_MAPS_API_KEY="'"$GOOGLE_MAPS_API_KEY"'"|' "$CONFIG_FILE"
        echo "GOOGLE_MAPS_API_KEY updated in $CONFIG_FILE"
    fi
    
    # Create and activate the virtual environment
    echo "Creating virtual environment with python3.11..."
    python3.11 -m venv venv
    
    if [ -d "venv" ]; then
        echo "Activating virtual environment..."
        source venv/bin/activate
        echo "Virtual environment activated successfully!"
    else
        echo "Error: Failed to create virtual environment."
        exit 1
    fi
    
    # Wake up Elasticsearch inference models
    echo "Waking up Elasticsearch inference models..."
    
    # Install elasticsearch package if not already installed
    pip install elasticsearch
    
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
E5_INFERENCE_ID = os.environ.get('E5_INFERENCE_ID', '.e5-elasticsearch')
RERANKER_INFERENCE_ID = os.environ.get('RERANK_INFERENCE_ID', '.rerank-elasticsearch')

def wake_up_elser():
    """Wake up ELSER model"""
    logger.info(f"Waking up ELSER model: {ELSER_INFERENCE_ID}")
    elser_response = es.inference.inference(
        inference_id=ELSER_INFERENCE_ID,
        input=['vector are so much fun']
    )
    logger.info("ELSER model woken up successfully")
    return elser_response

def wake_up_e5():
    """Wake up E5 model"""
    logger.info(f"Waking up E5 model: {E5_INFERENCE_ID}")
    e5_response = es.inference.inference(
        inference_id=E5_INFERENCE_ID,
        input=['vector are so much fun']
    )
    logger.info("E5 model woken up successfully")
    return e5_response

def delete_rerank_test_index():
    """Delete rerank-test index if it exists"""
    logger.info("Deleting rerank-test index if it exists...")
    try:
        es.indices.delete(index="rerank-test")
        logger.info("rerank-test index deleted successfully")
    except:
        logger.info("rerank-test index does not exist or already deleted")

def create_rerank_test_index():
    """Create rerank-test index with content field"""
    logger.info("Creating rerank-test index...")
    mapping = {
        "mappings": {
            "properties": {
                "content": {
                    "type": "text"
                }
            }
        }
    }
    es.indices.create(index="rerank-test", body=mapping)
    logger.info("rerank-test index created successfully")

def ingest_rerank_test_documents():
    """Ingest sample documents into rerank-test index"""
    logger.info("Ingesting documents into rerank-test index...")
    
    documents = [
        {"_index": "rerank-test", "_id": "5", "content": "Charlotte Amalie is the capital and largest city of the United States Virgin Islands. It has about 20,000 people. The city is on the island of Saint Thomas."},
        {"_index": "rerank-test", "_id": "3", "content": "The Commonwealth of the Northern Mariana Islands is a group of islands in the Pacific Ocean that are a political division controlled by the United States. Its capital is Saipan."},
        {"_index": "rerank-test", "_id": "1", "content": "Carson City is the capital city of the American state of Nevada. At the 2010 United States Census, Carson City had a population of 55,274."},
        {"_index": "rerank-test", "_id": "4", "content": "Washington, D.C. (also known as simply Washington or D.C., and officially as the District of Columbia) is the capital of the United States. It is a federal district."},
        {"_index": "rerank-test", "_id": "2", "content": "Capital punishment (the death penalty) has existed in the United States since before the United States was a country. As of 2017, capital punishment is legal in 30 of the 50 states."},
        {"_index": "rerank-test", "_id": "6", "content": "North Dakota is a state in the United States. 672,591 people lived in North Dakota in the year 2010. The capital and seat of government is Bismarck."}
    ]
    
    # Prepare bulk request
    bulk_data = ""
    for doc in documents:
        bulk_data += json.dumps({"index": {"_index": doc["_index"], "_id": doc["_id"]}}) + "\n"
        bulk_data += json.dumps({"content": doc["content"]}) + "\n"
    
    # Send bulk request
    response = es.bulk(body=bulk_data)
    logger.info("Documents ingested successfully")
    return response

def wake_up_reranker():
    """Wake up reranker model using the new test index and query"""
    logger.info("Waking up reranker model...")
    
    reranker_query = {
        "retriever": {
            "text_similarity_reranker": {
                "retriever": {
                    "standard": {
                        "query": {
                            "match": {
                                "content": "What is the capital of the USA?"
                            }
                        }
                    }
                },
                "field": "content",
                "inference_id": RERANKER_INFERENCE_ID,
                "inference_text": "What is the capital of the USA?",
                "rank_window_size": 10
            }
        }
    }
    
    response = es.search(index="rerank-test", body=reranker_query)
    logger.info("Reranker model woken up successfully")
    return response

def main():
    """Main function to wake up all inference models"""
    logger.info("Starting to wake up inference models...")
    
    try:
        # Wake up ELSER model
        wake_up_elser()
        
        # Wake up E5 model
        wake_up_e5()
        
        # Set up reranker test
        delete_rerank_test_index()
        create_rerank_test_index()
        ingest_rerank_test_documents()
        
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
        echo "Warning: Failed to wake up inference models"
    fi
    
    # Run the data ingestion setup script (unless skipped)
    if [ "$SKIP_INGESTION" = true ]; then
        echo "Skipping data ingestion (--skip-ingestion flag provided)"
    elif [ -d "data-ingestion" ]; then
        echo "Changing to data-ingestion directory..."
        cd data-ingestion
        echo "Current directory: $(pwd)"
        
        if [ -f "setup.sh" ]; then
            echo "Running setup.sh to configure data ingestion..."
            chmod +x setup.sh
            ./setup.sh
            if [ $? -eq 0 ]; then
                echo "Data ingestion setup completed successfully!"
            else
                echo "Warning: Data ingestion setup failed"
            fi
        else
            echo "Warning: setup.sh not found in data-ingestion directory."
        fi
        
        # Run the ingestion script with Instruqt flag
        if [ -f "run-ingestion.sh" ]; then
            echo "Running ingestion script with Instruqt flag..."
            chmod +x run-ingestion.sh
            source ../env_config.sh && ./run-ingestion.sh --ingest-raw-500-dataset
            if [ $? -eq 0 ]; then
                echo "Data ingestion completed successfully!"
            else
                echo "Warning: Data ingestion failed"
            fi
        else
            echo "Warning: run-ingestion.sh not found in data-ingestion directory."
        fi
        
        # Return to the main directory
        cd ..
        echo "Returned to main directory: $(pwd)"
    else
        echo "Warning: data-ingestion directory not found in the repository."
    fi
    
    echo "Setup complete! The repository is ready for configuration."
    
    
else
    echo "Error: Failed to clone the repository."
    exit 1
fi

# Clone Elastic-AI-Infused-Property-Search repository
echo "Setting up Elastic-AI-Infused-Property-Search repository..."

# Deactivate the current virtual environment if active
if [[ "$VIRTUAL_ENV" != "" ]]; then
    echo "Deactivating current virtual environment..."
    deactivate
fi

# Ensure we're in /root
cd /root

# Remove repository if it already exists
if [ -d "Elastic-AI-Infused-Property-Search" ]; then
    echo "Removing existing Elastic-AI-Infused-Property-Search directory..."
    rm -rf Elastic-AI-Infused-Property-Search
fi

# Clone the property search repository
echo "Cloning Elastic-AI-Infused-Property-Search repository..."
git clone https://github.com/sunilemanjee/Elastic-AI-Infused-Property-Search.git

if [ $? -eq 0 ]; then
    echo "Elastic-AI-Infused-Property-Search repository cloned successfully!"
    
    # Change to the cloned directory
    cd /root/Elastic-AI-Infused-Property-Search
    echo "Changed to directory: $(pwd)"
    
    # Move setenv.sh.template to setenv.sh
    if [ -f "setenv.sh.template" ]; then
        echo "Moving setenv.sh.template to setenv.sh..."
        mv setenv.sh.template setenv.sh
        echo "setenv.sh.template moved to setenv.sh"
        
        # Update setenv.sh with API key and endpoint
        echo "Updating setenv.sh with API configuration..."
        
        # Use the API key that was already extracted in the retry loop above
        if [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ]; then
            echo "Using API key retrieved from retry loop"
            # Update the ES_API_KEY in setenv.sh
            sed -i 's|export ES_API_KEY="[^"]*"|export ES_API_KEY="'"$API_KEY"'"|' setenv.sh
            echo "ES_API_KEY updated in setenv.sh"
        else
            echo "Error: No valid API key available for setenv.sh"
            exit 1
        fi
        
        # Update ELSER_INFERENCE_ID
        sed -i 's|export ELSER_INFERENCE_ID="[^"]*"|export ELSER_INFERENCE_ID=".elser-2-elasticsearch"|' setenv.sh
        echo "ELSER_INFERENCE_ID updated in setenv.sh"
        
        # Update ES_URL
        echo "Updating ES_URL in setenv.sh..."
        sed -i 's|export ES_URL="[^"]*"|export ES_URL="'"$ES_URL"'"|' setenv.sh
        echo "ES_URL updated to $ES_URL"
        
        # Update Azure OpenAI configuration
        echo "Updating Azure OpenAI configuration in setenv.sh..."
        # Format LLM_HOST with https:// prefix and trailing slash for Azure OpenAI endpoint
        AZURE_OPENAI_ENDPOINT="https://$LLM_HOST/"
        sed -i 's|export AZURE_OPENAI_ENDPOINT=.*|export AZURE_OPENAI_ENDPOINT="'"$AZURE_OPENAI_ENDPOINT"'"|' setenv.sh
        echo "AZURE_OPENAI_ENDPOINT updated to $AZURE_OPENAI_ENDPOINT"
        
        sed -i 's|export AZURE_OPENAI_API_KEY=.*|export AZURE_OPENAI_API_KEY="'"$OPENAI_API_KEY"'"|' setenv.sh
        echo "AZURE_OPENAI_API_KEY updated in setenv.sh"
        
        sed -i 's|export AZURE_OPENAI_MODEL=.*|export AZURE_OPENAI_MODEL="gpt-4o"|' setenv.sh
        echo "AZURE_OPENAI_MODEL updated to gpt-4o"
        
        # Update KIBANA_URL
        echo "Updating KIBANA_URL in setenv.sh..."
        sed -i 's|export KIBANA_URL="[^"]*"|export KIBANA_URL="'"$KIBANA_URL"'"|' setenv.sh
        echo "KIBANA_URL updated to $KIBANA_URL"
        
    else
        echo "Warning: setenv.sh.template not found in the repository."
    fi
    
    # Create and activate the virtual environment
    echo "Creating virtual environment with python3.11..."
    python3.11 -m venv venv
    
    if [ -d "venv" ]; then
        echo "Activating virtual environment..."
        source venv/bin/activate
        echo "Virtual environment activated successfully!"
        
        # Install requirements
        if [ -f "requirements.txt" ]; then
            echo "Installing requirements from requirements.txt..."
            pip install -r requirements.txt
            if [ $? -eq 0 ]; then
                echo "Requirements installed successfully!"
            else
                echo "Warning: Failed to install some requirements."
            fi
        else
            echo "Warning: requirements.txt not found in the repository."
        fi
    else
        echo "Error: Failed to create virtual environment for Elastic-AI-Infused-Property-Search."
    fi
    
    
else
    echo "Warning: Failed to clone Elastic-AI-Infused-Property-Search repository."
fi 