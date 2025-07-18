#!/bin/bash

# Wake up Elasticsearch inference models using Python with URL and API key authentication
# Set timeout to 300 seconds and create rerank-test index with sample documents

echo "Waking endpoints..."
cd /root/Elastic-Python-MCP-Server/

deactivate

source venv/bin/activate


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
ELSER_INFERENCE_ID = os.environ.get('ELSER_INFERENCE_ID')
E5_INFERENCE_ID = os.environ.get('E5_INFERENCE_ID')
RERANKER_INFERENCE_ID = os.environ.get('RERANK_INFERENCE_ID')

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