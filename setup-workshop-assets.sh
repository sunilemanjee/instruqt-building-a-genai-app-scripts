#!/bin/bash



# Check for existing project results file
echo "Checking for existing project results file at /tmp/project_results.json..."

if [ -f "/tmp/project_results.json" ]; then
    echo "Found existing project results file at /tmp/project_results.json"
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

        if [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ] && [ ! -z "$ES_URL" ] && [ "$ES_URL" != "null" ] && [ ! -z "$KIBANA_URL" ] && [ "$KIBANA_URL" != "null" ] && [ ! -z "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "null" ] && [ ! -z "$LLM_HOST" ] && [ "$LLM_HOST" != "null" ] && [ ! -z "$LLM_CHAT_URL" ] && [ "$LLM_CHAT_URL" != "null" ]; then
            echo "API key found successfully: ${API_KEY:0:10}..."
            echo "ES URL found: $ES_URL"
            echo "Kibana URL found: $KIBANA_URL"
        else
            echo "Error: API key, ES URL, Kibana URL, or LLM credentials not found or invalid in response"
            exit 1
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
        else
            echo "Error: API key, ES URL, or Kibana URL not found in response"
            exit 1
        fi
    fi
else
    echo "Error: /tmp/project_results.json file not found"
    echo "Please ensure the project results file exists before running this script"
    exit 1
fi

# Check if we successfully got the API key and URLs
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ] || [ -z "$ES_URL" ] || [ "$ES_URL" = "null" ] || [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" = "null" ] || [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "null" ] || [ -z "$LLM_HOST" ] || [ "$LLM_HOST" = "null" ] || [ -z "$LLM_CHAT_URL" ] || [ "$LLM_CHAT_URL" = "null" ]; then
    echo "Error: Failed to retrieve valid API key, ES URL, Kibana URL, or LLM credentials from /tmp/project_results.json"
    echo "File content:"
    cat /tmp/project_results.json
    exit 1
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
    request_timeout=TIMEOUT,
    verify_certs=False
)

# Inference model IDs from environment variables
ELSER_INFERENCE_ID = os.environ.get('ELSER_INFERENCE_ID', '.elser-2-elastic')
E5_INFERENCE_ID = os.environ.get('E5_INFERENCE_ID', '.multilingual-e5-small-elasticsearch')
RERANKER_INFERENCE_ID = os.environ.get('RERANK_INFERENCE_ID', '.rerank-elasticsearch')

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
                input=['vector are so much fun'],
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
        # Wake up ELSER model
        wake_up_elser()
        
        # Wake up E5 model
        wake_up_e5()
        
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
        echo "Error: Failed to wake up inference models - cannot proceed with indexing"
        echo "The models need to be fully deployed before indexing can begin"
        exit 1
    fi
    
# Data ingestion section
echo "Starting data ingestion process..."

# Download the properties data from Azure blob storage
echo "Downloading properties data from Azure blob storage..."
curl -s "https://sunmanapp.blob.core.windows.net/publicstuff/properties/properties-filtered-500-lines_cleaned_redacted.json" -o /tmp/properties_data.json

if [ $? -eq 0 ]; then
    echo "Properties data downloaded successfully to /tmp/properties_data.json"
else
    echo "Error: Failed to download properties data from Azure blob storage"
    exit 1
fi

# Create properties index using the mapping
echo "Creating properties index with mapping..."

python3 << 'EOF'
import json
import logging
import os
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
    """Ingest the properties data into the index"""
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
        
        # Prepare bulk request
        bulk_data = ""
        for i, property_doc in enumerate(properties_data):
            # Add document ID based on index
            bulk_data += json.dumps({"index": {"_index": index_name, "_id": str(i)}}) + "\n"
            bulk_data += json.dumps(property_doc) + "\n"
        
        # Send bulk request
        response = es.bulk(body=bulk_data)
        
        if response.get("errors"):
            logger.error("Some documents failed to index:")
            for item in response["items"]:
                if "index" in item and "error" in item["index"]:
                    logger.error(f"Error indexing document {item['index']['_id']}: {item['index']['error']}")
        else:
            logger.info(f"Successfully ingested {len(properties_data)} properties into {index_name} index")
        
        return response
        
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

# Create specialized indices and perform reindexing
echo "Creating specialized indices and performing reindexing..."

python3 << 'EOF'
import json
import time
import logging
from elasticsearch import Elasticsearch

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

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
    request_timeout=120,
    verify_certs=False
)

# Embedded index mappings
logger.info("Using embedded index mappings...")

# Base mapping structure
BASE_MAPPING = {
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
                "copy_to": [
                    "body_content_e5"
                ]
            },
            "body_content_phrase": {
                "type": "text"
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
                        "type": "flat"  # This will be overridden for each index
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
                "type": "text"
            },
            "property-features": {
                "type": "text"
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

# Create specific mappings for each index type
import copy

int4_mapping = copy.deepcopy(BASE_MAPPING)
int4_mapping["mappings"]["properties"]["body_content_e5"]["index_options"]["dense_vector"]["type"] = "int4_flat"

int8_mapping = copy.deepcopy(BASE_MAPPING)
int8_mapping["mappings"]["properties"]["body_content_e5"]["index_options"]["dense_vector"]["type"] = "int8_flat"

bbq_mapping = copy.deepcopy(BASE_MAPPING)
bbq_mapping["mappings"]["properties"]["body_content_e5"]["index_options"]["dense_vector"]["type"] = "bbq_flat"

logger.info("Successfully created all index mappings with embedded configurations.")

def create_index(index_name, mapping):
    """Create an index with the specified mapping"""
    try:
        # Check if index exists and delete it if it does
        if es.indices.exists(index=index_name):
            logger.info(f"Index {index_name} already exists. Deleting it first...")
            delete_response = es.indices.delete(index=index_name)
            logger.info(f"Successfully deleted existing index: {index_name}")
            # Wait a moment for the deletion to complete
            time.sleep(2)
        else:
            logger.info(f"Index {index_name} does not exist. Creating new index...")
        
        # Create the new index
        response = es.indices.create(index=index_name, body=mapping)
        logger.info(f"Successfully created index: {index_name}")
        return True
    except Exception as e:
        logger.error(f"Error creating index {index_name}: {e}")
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
        logger.info(f"Started reindex from {source_index} to {dest_index}. Task ID: {task_id}")
        return task_id
    except Exception as e:
        logger.error(f"Error starting reindex from {source_index} to {dest_index}: {e}")
        return None

def check_task_status(task_id):
    """Check if a task is complete"""
    try:
        response = es.tasks.get(task_id=task_id)
        return response['completed']
    except Exception as e:
        logger.error(f"Error checking task status for {task_id}: {e}")
        return False

def wait_for_reindex_completion(task_id, dest_index):
    """Wait for reindex completion, checking every 10 seconds"""
    logger.info(f"Waiting for reindex to {dest_index} to complete...")
    while True:
        if check_task_status(task_id):
            logger.info(f"Reindex to {dest_index} completed successfully!")
            break
        else:
            logger.info(f"Reindex to {dest_index} still in progress... checking again in 10 seconds")
            time.sleep(10)

def cleanup_existing_indices():
    """Clean up existing indices if they exist"""
    indices_to_cleanup = ["properties_int4", "properties_int8", "properties_bbq"]
    
    logger.info("Checking for existing indices to clean up...")
    for index_name in indices_to_cleanup:
        try:
            if es.indices.exists(index=index_name):
                logger.info(f"Found existing index: {index_name}. Deleting it...")
                delete_response = es.indices.delete(index=index_name)
                logger.info(f"Successfully deleted index: {index_name}")
            else:
                logger.info(f"Index {index_name} does not exist. No cleanup needed.")
        except Exception as e:
            logger.warning(f"Could not delete index {index_name}: {e}")
    
    logger.info("Index cleanup completed.")

def main():
    """Main function to create indices and perform reindexing"""
    logger.info("Starting index creation and reindexing process...")
    
    # Clean up any existing indices first
    cleanup_existing_indices()
    
    # Check if source index exists
    if not es.indices.exists(index="properties"):
        logger.error("Error: Source index 'properties' does not exist!")
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
        logger.error("No indices were created successfully. Exiting.")
        return
    
    logger.info(f"Created {len(created_indices)} indices: {', '.join(created_indices)}")
    
    # Start async reindex operations
    task_ids = {}
    for index_name in created_indices:
        task_id = start_reindex("properties", index_name)
        if task_id:
            task_ids[index_name] = task_id
    
    if not task_ids:
        logger.error("No reindex operations were started successfully. Exiting.")
        return
    
    logger.info(f"Started {len(task_ids)} reindex operations")
    
    # Wait for all reindex operations to complete
    for index_name, task_id in task_ids.items():
        wait_for_reindex_completion(task_id, index_name)
    
    logger.info("All reindex operations completed successfully!")
    print(json.dumps({"success": True, "message": "Specialized indices created and reindexing completed successfully"}))

if __name__ == "__main__":
    main()
EOF

if [ $? -eq 0 ]; then
    echo "Specialized indices creation and reindexing completed successfully!"
else
    echo "Warning: Specialized indices creation and reindexing failed"
fi

echo "Setup complete! Inference models have been woken up, properties data has been ingested, and specialized indices have been created successfully."
