#!/bin/bash

###################
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
    
    # Virtual environment is created by setup-workshop-assets.sh script
    
    # Inference models are woken up by setup-workshop-assets.sh script
    
    # Data ingestion is handled by setup-workshop-assets.sh script
    
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

# Start Elastic MCP Server
echo "Starting Elastic MCP Server..."
cd /root/Elastic-Python-MCP-Server/

# Create and activate the virtual environment for MCP Server
echo "Creating virtual environment with python3.11 for MCP Server..."
python3.11 -m venv venv

if [ -d "venv" ]; then
    echo "Activating virtual environment for MCP Server..."
    source venv/bin/activate
    echo "Virtual environment activated successfully!"
else
    echo "Error: Failed to create virtual environment for MCP Server."
    exit 1
fi

source env_config.sh

./run_server.sh --background

deactivate

# Start Chainlit Application in background
echo "Starting Chainlit Application..."
cd /root/Elastic-AI-Infused-Property-Search/

# Kill any existing Chainlit process using PID file
echo "Checking for existing Chainlit process..."
if [ -f "/root/Elastic-AI-Infused-Property-Search/logs/chainlit.pid" ]; then
    echo "Found existing Chainlit PID file. Killing process..."
    kill $(cat /root/Elastic-AI-Infused-Property-Search/logs/chainlit.pid) 2>/dev/null || true
    rm -f /root/Elastic-AI-Infused-Property-Search/logs/chainlit.pid
    echo "Existing Chainlit process killed"
    sleep 2
else
    echo "No existing Chainlit PID file found"
fi

# Kill any processes running on port 8000
echo "Checking for processes running on port 8000..."
if lsof -ti:8000 > /dev/null 2>&1; then
    echo "Found processes running on port 8000. Killing them..."
    lsof -ti:8000 | xargs kill -9
    echo "Processes on port 8000 killed successfully"
    sleep 2
else
    echo "No processes found running on port 8000"
fi

# Create logs directory for Chainlit if it doesn't exist
echo "Creating logs directory for Chainlit..."
mkdir -p /root/Elastic-AI-Infused-Property-Search/logs
if [ ! -d "/root/Elastic-AI-Infused-Property-Search/logs" ]; then
    echo "Error: Failed to create logs directory"
    exit 1
fi
echo "Logs directory created/verified successfully"

source venv/bin/activate
source setenv.sh

# Run chainlit in background and redirect output to logs
echo "Starting chainlit in background..."
nohup chainlit run src/app.py --host 0.0.0.0 > /root/Elastic-AI-Infused-Property-Search/logs/chainlit.log 2>&1 &

# Save the background process ID
echo $! > /root/Elastic-AI-Infused-Property-Search/logs/chainlit.pid

echo "Chainlit application started in background with PID: $(cat /root/Elastic-AI-Infused-Property-Search/logs/chainlit.pid)"
echo "Logs are being written to: /root/Elastic-AI-Infused-Property-Search/logs/chainlit.log"
echo "To stop the application, run: kill \$(cat /root/Elastic-AI-Infused-Property-Search/logs/chainlit.pid)"

echo "Setting /root/Elastic-Python-MCP-Server/elastic_mcp_server.py to read only permissions..."
chmod 444 /root/Elastic-Python-MCP-Server/elastic_mcp_server.py

echo "Setting /root/Elastic-AI-Infused-Property-Search/src/app.py to read only permissions..."
chmod 444 /root/Elastic-AI-Infused-Property-Search/src/app.py

echo "Setup and startup complete! Both MCP Server and Chainlit application are now running." 