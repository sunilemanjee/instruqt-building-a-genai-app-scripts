#!/bin/bash


agent variable set LLM_KEY $OPENAI_API_KEY
agent variable set LLM_HOST $LLM_URL
agent variable set LLM_CHAT_URL https://$LLM_URL/v1/chat/completions


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
            API_KEY=$(jq -r --arg region "$REGIONS" '.[$region].credentials.api_key' /tmp/project_results.json 2>/dev/null)
            ES_URL=$(jq -r --arg region "$REGIONS" '.[$region].endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
            KIBANA_URL=$(jq -r --arg region "$REGIONS" '.[$region].endpoints.kibana' /tmp/project_results.json 2>/dev/null)

            echo "Reading LLM credentials from /tmp/project_results.json..."
            # Extract LLM credentials from the JSON file
            OPENAI_API_KEY=$(jq -r --arg region "$REGIONS" '.[$region].credentials.llm_api_key' /tmp/project_results.json)
            LLM_HOST=$(jq -r --arg region "$REGIONS" '.[$region].credentials.llm_host' /tmp/project_results.json)
            LLM_CHAT_URL=$(jq -r --arg region "$REGIONS" '.[$region].credentials.llm_chat_url' /tmp/project_results.json)
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


# Clean up any existing repository
if [ -d "/root/hotel-finder-query-constructor" ]; then
    echo "Removing existing hotel-finder-query-constructor directory..."
    rm -rf /root/hotel-finder-query-constructor
fi

git clone -b home-finder https://github.com/sunilemanjee/hotel-finder-query-constructor.git

cd /root/hotel-finder-query-constructor

# Copy template and update with actual values
cp variables.env.template variables.env

# Update the template with actual values
if command -v sed &> /dev/null; then
    # Update API key
    sed -i "s/ES_API_KEY=.*/ES_API_KEY=\"$API_KEY\"/" variables.env
    # Update ES URL
    sed -i "s|ES_URL=.*|ES_URL=\"$ES_URL\"|" variables.env
    # Update username to elastic (if not already set)
    sed -i "s/ES_USERNAME=.*/ES_USERNAME=elastic/" variables.env
    # Clear password since we're using API key
    sed -i "s/ES_PASSWORD=.*/ES_PASSWORD=/" variables.env
    # Ensure USE_PASSWORD is false since we're using API key
    sed -i "s/USE_PASSWORD=.*/USE_PASSWORD=false/" variables.env
    
    echo "Successfully updated variables.env with API key and endpoint"

    # Update Azure OpenAI configuration
    echo "Updating Azure OpenAI configuration in variables.env.."
    # Format LLM_URL with https:// prefix and trailing slash for Azure OpenAI endpoint
    OPENAI_ENDPOINT="https://$LLM_URL/"
    sed -i 's|OPENAI_ENDPOINT=.*|OPENAI_ENDPOINT='"$OPENAI_ENDPOINT"'|' variables.env
    echo "OPENAI_ENDPOINT updated to $OPENAI_ENDPOINT"
    
    sed -i "s|OPENAI_API_KEY=.*|OPENAI_API_KEY=\"$OPENAI_API_KEY\"|" variables.env
    echo "OPENAI_API_KEY updated in variables.env"
    
    sed -i 's|OPENAI_MODEL=.*|OPENAI_MODEL=gpt-4o-global|' variables.env
    echo "OPENAI_MODEL updated to gpt-4o-global"
    
    sed -i 's|OPENAI_API_VERSION=.*|OPENAI_API_VERSION=2025-01-01-preview|' variables.env
    echo "OPENAI_API_VERSION updated to 2025-01-01-preview"
        
else
    # Fallback if sed is not available
    echo "Warning: sed not available, manually updating variables.env"
    echo "Please update the following in variables.env:"
    echo "  ES_API_KEY=\"$API_KEY\""
    echo "  ES_URL=\"$ES_URL\""
    echo "  ES_USERNAME=elastic"
    echo "  ES_PASSWORD="
    echo "  USE_PASSWORD=false"
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
        echo "Installing Python dependencies from requirements.txt..."
        pip install -r requirements.txt
        if [ $? -eq 0 ]; then
            echo "Dependencies installed successfully!"
        else
            echo "Error: Failed to install dependencies from requirements.txt"
            exit 1
        fi
    else
        echo "Warning: requirements.txt not found in the repository"
    fi
else
    echo "Error: Failed to create virtual environment"
    exit 1
fi


# Kill any existing process on port 5001
echo "Checking for existing processes on port 5001..."
EXISTING_PID=$(lsof -ti:5001 2>/dev/null)
if [ ! -z "$EXISTING_PID" ]; then
    echo "Found existing process(es) on port 5001: $EXISTING_PID"
    echo "Killing existing process(es)..."
    kill -9 $EXISTING_PID
    sleep 2
    echo "Existing processes killed"
else
    echo "No existing processes found on port 5001"
fi

# Create logs directory
mkdir -p /root/hotel-finder-query-constructor/logs

# Source environment and run in background with logging
echo "Starting search UI in background..."
source setup_env.sh

# Run the application in background and redirect output to logs
nohup python search_ui.py > /root/hotel-finder-query-constructor/logs/search_ui.log 2>&1 &

# Get the background process ID
SEARCH_UI_PID=$!

# Save PID to file for later reference
echo $SEARCH_UI_PID > /root/hotel-finder-query-constructor/logs/search_ui.pid

echo "Search UI started in background with PID: $SEARCH_UI_PID"
echo "Logs are being written to: /root/hotel-finder-query-constructor/logs/search_ui.log"
echo "PID file saved to: /root/hotel-finder-query-constructor/logs/search_ui.pid"