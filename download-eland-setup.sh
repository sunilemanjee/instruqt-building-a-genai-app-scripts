#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#
# Script to download eland-setup.sh from GitHub and install it

# Define the target file path
TARGET_FILE="/root/eland-setup.sh"
GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/eland-setup.sh"

echo "Downloading eland-setup.sh from GitHub..."

# Check if file already exists and inform user it will be overwritten
if [ -f "$TARGET_FILE" ]; then
    echo "File $TARGET_FILE already exists - it will be overwritten"
fi

# Download the script using curl with fail-on-error flag
curl -f -o "$TARGET_FILE" "$GITHUB_URL"

# Check if download was successful
if [ $? -eq 0 ]; then
    echo "Successfully downloaded eland-setup.sh to /root/"
    
    # Validate that the downloaded file is not empty and contains script content
    if [ ! -s "$TARGET_FILE" ]; then
        echo "Error: Downloaded file is empty"
        exit 1
    fi
    
    if ! head -n 1 "$TARGET_FILE" | grep -q "^#!"; then
        echo "Error: Downloaded file does not appear to be a valid script (missing shebang)"
        exit 1
    fi
    
    # Make the script executable
    chmod 755 "$TARGET_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Successfully set executable permissions (755) on $TARGET_FILE"
        echo "Installation complete!"
        echo ""
        echo "Now fetching project results to set environment variables..."
        echo "----------------------------------------"
        
        # Check if required environment variable is set
        if [ -z "$PROXY_ES_KEY_BROKER" ]; then
            echo "Error: PROXY_ES_KEY_BROKER environment variable is not set"
            exit 1
        fi

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
                echo "Download completed successfully!"
                break
            else
                echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
                if [ $attempt -lt $MAX_RETRIES ]; then
                    echo "Waiting $RETRY_WAIT seconds before retry..."
                    sleep $RETRY_WAIT
                else
                    echo "Error: Failed to download project results after $MAX_RETRIES attempts"
                    exit 1
                fi
            fi
        done
        
        # Parse project results and set environment variables
        echo ""
        echo "Parsing /tmp/project_results.json and setting environment variables..."
        
        # Check if the project results file exists
        if [ ! -f "/tmp/project_results.json" ]; then
            echo "Error: /tmp/project_results.json file not found"
            exit 1
        fi

        # Try to use jq if available
        if command -v jq &> /dev/null; then
            echo "Using jq to parse JSON..."
            
            # Extract ES_API_KEY and ES_URL using jq
            API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json 2>/dev/null)
            ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
            
            echo "DEBUG - Raw extracted values:"
            echo "API_KEY: '$API_KEY'"
            echo "ES_URL: '$ES_URL'"
            
            # Validate the extracted values
            if [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ] && [ ! -z "$ES_URL" ] && [ "$ES_URL" != "null" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                echo "ES URL found: $ES_URL"
                
                # Export environment variables
                export ES_API_KEY="$API_KEY"
                export ES_URL="$ES_URL"
                
                echo "Environment variables set successfully:"
                echo "ES_API_KEY: ${ES_API_KEY:0:10}..."
                echo "ES_URL: $ES_URL"
            else
                echo "API key or ES URL not found or invalid in response"
                echo "DEBUG - Validation failed:"
                echo "API_KEY empty: $([ -z "$API_KEY" ] && echo "YES" || echo "NO")"
                echo "API_KEY null: $([ "$API_KEY" = "null" ] && echo "YES" || echo "NO")"
                echo "ES_URL empty: $([ -z "$ES_URL" ] && echo "YES" || echo "NO")"
                echo "ES_URL null: $([ "$ES_URL" = "null" ] && echo "YES" || echo "NO")"
                exit 1
            fi
        else
            echo "Using grep/sed fallback to parse JSON..."
            # Fallback to grep/sed if jq is not available
            API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
            ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
            
            echo "DEBUG - Raw extracted values (grep/sed):"
            echo "API_KEY: '$API_KEY'"
            echo "ES_URL: '$ES_URL'"
            
            # Validate the extracted values
            if [ ! -z "$API_KEY" ] && [ ! -z "$ES_URL" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                echo "ES URL found: $ES_URL"
                
                # Export environment variables
                export ES_API_KEY="$API_KEY"
                export ES_URL="$ES_URL"
                
                echo "Environment variables set successfully:"
                echo "ES_API_KEY: ${ES_API_KEY:0:10}..."
                echo "ES_URL: $ES_URL"
            else
                echo "API key or ES URL not found in response"
                echo "DEBUG - Validation failed (grep/sed):"
                echo "API_KEY empty: $([ -z "$API_KEY" ] && echo "YES" || echo "NO")"
                echo "ES_URL empty: $([ -z "$ES_URL" ] && echo "YES" || echo "NO")"
                exit 1
            fi
        fi
    else
        echo "Error: Failed to set executable permissions on $TARGET_FILE"
        exit 1
    fi
else
    echo "Error: Failed to download eland-setup.sh from GitHub"
    echo "Please check your internet connection and try again"
    echo "URL: $GITHUB_URL"
    exit 1
fi

# Download set-eland-env-variables.sh to /root/workshop
echo ""
echo "Downloading set-eland-env-variables.sh to /root/workshop..."

# Define the workshop directory and target file
WORKSHOP_DIR="/root/workshop"
ENV_VARS_FILE="$WORKSHOP_DIR/set-eland-env-variables.sh"
ENV_VARS_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/set-eland-env-variables.sh"

# Create workshop directory if it doesn't exist
if [ ! -d "$WORKSHOP_DIR" ]; then
    echo "Creating workshop directory: $WORKSHOP_DIR"
    mkdir -p "$WORKSHOP_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create workshop directory"
        exit 1
    fi
fi

# Check if file already exists and inform user it will be overwritten
if [ -f "$ENV_VARS_FILE" ]; then
    echo "File $ENV_VARS_FILE already exists - it will be overwritten"
fi

# Download the script using curl with fail-on-error flag
curl -f -o "$ENV_VARS_FILE" "$ENV_VARS_URL"

# Check if download was successful
if [ $? -eq 0 ]; then
    echo "Successfully downloaded set-eland-env-variables.sh to $WORKSHOP_DIR/"
    
    # Validate that the downloaded file is not empty and contains script content
    if [ ! -s "$ENV_VARS_FILE" ]; then
        echo "Error: Downloaded file is empty"
        exit 1
    fi
    
    if ! head -n 1 "$ENV_VARS_FILE" | grep -q "^#!"; then
        echo "Error: Downloaded file does not appear to be a valid script (missing shebang)"
        exit 1
    fi
    
    # Make the script executable
    chmod 755 "$ENV_VARS_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Successfully set executable permissions (755) on $ENV_VARS_FILE"
        echo "set-eland-env-variables.sh installation complete!"
    else
        echo "Error: Failed to set executable permissions on $ENV_VARS_FILE"
        exit 1
    fi
else
    echo "Error: Failed to download set-eland-env-variables.sh from GitHub"
    echo "Please check your internet connection and try again"
    echo "URL: $ENV_VARS_URL"
    exit 1
fi

# Run eland import for the NER model
echo ""
echo "Running eland import for elastic/distilbert-base-cased-finetuned-conll03-english NER model..."
echo "----------------------------------------"

# Debug: Check if environment variables are set
echo "DEBUG: Checking environment variables..."
echo "ES_URL: '$ES_URL'"
echo "ES_API_KEY: '${ES_API_KEY:0:10}...'"

# Check if ES_URL is set and not empty
if [ -z "$ES_URL" ]; then
    echo "Error: ES_URL environment variable is not set or is empty"
    echo "Please ensure the environment variables are properly configured"
    exit 1
fi

if [ -z "$ES_API_KEY" ]; then
    echo "Error: ES_API_KEY environment variable is not set or is empty"
    echo "Please ensure the environment variables are properly configured"
    exit 1
fi

docker run --rm --network host \
    docker.elastic.co/eland/eland \
    eland_import_hub_model \
      --url $ES_URL \
      --es-api-key $ES_API_KEY \
      --hub-model-id elastic/distilbert-base-cased-finetuned-conll03-english \
      --task-type ner \
      --start

if [ $? -eq 0 ]; then
    echo "Successfully imported NER model to Elasticsearch"
else
    echo "Error: Failed to import NER model to Elasticsearch"
    exit 1
fi

# Run eland import for the zero-shot classification model
echo ""
echo "Running eland import for typeform/distilbert-base-uncased-mnli zero-shot classification model..."
echo "----------------------------------------"

# Debug: Check if environment variables are still set
echo "DEBUG: Checking environment variables for second model..."
echo "ES_URL: '$ES_URL'"
echo "ES_API_KEY: '${ES_API_KEY:0:10}...'"

# Check if ES_URL is set and not empty
if [ -z "$ES_URL" ]; then
    echo "Error: ES_URL environment variable is not set or is empty"
    echo "Please ensure the environment variables are properly configured"
    exit 1
fi

if [ -z "$ES_API_KEY" ]; then
    echo "Error: ES_API_KEY environment variable is not set or is empty"
    echo "Please ensure the environment variables are properly configured"
    exit 1
fi

docker run --rm --network host \
    docker.elastic.co/eland/eland \
    eland_import_hub_model \
      --url $ES_URL \
      --es-api-key $ES_API_KEY \
      --hub-model-id typeform/distilbert-base-uncased-mnli \
      --task-type zero_shot_classification \
      --start

if [ $? -eq 0 ]; then
    echo "Successfully imported zero-shot classification model to Elasticsearch"
else
    echo "Error: Failed to import zero-shot classification model to Elasticsearch"
    exit 1
fi