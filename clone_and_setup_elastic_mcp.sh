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
        \"inviteId\": \"$INSTRUQT_TRACK_INVITE_ID\",
        \"userId\": \"$INSTRUQT_USER_ID\",
        \"userEmail\": \"$INSTRUQT_USER_EMAIL\"
      }
    }")

    OPENAI_API_KEY=$(echo $output | jq -r '.key')
    
    if [ -z "${OPENAI_API_KEY}" ]; then
        echo "Failed to extract API key from response on attempt $attempt"
        [ $attempt -lt $MAX_RETRIES ] && sleep $RETRY_WAIT
    else
        echo "Request successful and API key extracted on attempt $attempt"
        break
    fi
done

[ -z "$OPENAI_API_KEY" ] && echo "Failed to retrieve API key after $MAX_RETRIES attempts" && exit 1

agent variable set LLM_KEY $OPENAI_API_KEY
agent variable set LLM_HOST $LLM_URL
agent variable set LLM_CHAT_URL https://$LLM_URL/v1/chat/completions


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
        
        # Check if the response contains valid JSON and has the api_key
        if command -v jq &> /dev/null; then
            # Use jq to validate JSON and extract api_key
            API_KEY=$(jq -r '.["aws-us-east-1"].credentials.api_key' /tmp/project_results.json 2>/dev/null)
            
            if [ $? -eq 0 ] && [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                break
            else
                echo "API key not found or invalid in response on attempt $attempt"
                [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
            fi
        else
            # Fallback to grep/sed if jq is not available
            API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
            
            if [ ! -z "$API_KEY" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                break
            else
                echo "API key not found in response on attempt $attempt"
                [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
            fi
        fi
    else
        echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
        [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
    fi
done

# Check if we successfully got the API key after all attempts
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "Error: Failed to retrieve valid API key after $MAX_RETRIES attempts"
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
        sed -i 's|export ES_URL="[^"]*"|export ES_URL="'"$ES_ENDPOINT"'"|' "$CONFIG_FILE"
        echo "ES_URL updated to $ES_ENDPOINT"
        
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
            source ../env_config.sh && ./run-ingestion.sh --instruqt
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
        sed -i 's|export ES_URL="[^"]*"|export ES_URL="'"$ES_ENDPOINT"'"|' setenv.sh
        echo "ES_URL updated to $ES_ENDPOINT"
        
        # Update Azure OpenAI configuration
        echo "Updating Azure OpenAI configuration in setenv.sh..."
        # Format LLM_URL with https:// prefix and trailing slash for Azure OpenAI endpoint
        AZURE_OPENAI_ENDPOINT="https://$LLM_URL/"
        sed -i 's|export AZURE_OPENAI_ENDPOINT=.*|export AZURE_OPENAI_ENDPOINT="'"$AZURE_OPENAI_ENDPOINT"'"|' setenv.sh
        echo "AZURE_OPENAI_ENDPOINT updated to $AZURE_OPENAI_ENDPOINT"
        
        sed -i 's|export AZURE_OPENAI_API_KEY=.*|export AZURE_OPENAI_API_KEY="'"$OPENAI_API_KEY"'"|' setenv.sh
        echo "AZURE_OPENAI_API_KEY updated in setenv.sh"
        
        sed -i 's|export AZURE_OPENAI_MODEL=.*|export AZURE_OPENAI_MODEL="gpt-4o"|' setenv.sh
        echo "AZURE_OPENAI_MODEL updated to gpt-4o"
        
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