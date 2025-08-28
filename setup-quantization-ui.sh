#!/bin/bash

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
            
            if [ $? -eq 0 ] && [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ] && [ ! -z "$ES_URL" ] && [ "$ES_URL" != "null" ] && [ ! -z "$KIBANA_URL" ] && [ "$KIBANA_URL" != "null" ]; then
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
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ] || [ -z "$ES_URL" ] || [ "$ES_URL" = "null" ] || [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" = "null" ]; then
    echo "Error: Failed to retrieve valid API key, ES URL, or Kibana URL after $MAX_RETRIES attempts"
    echo "Last response content:"
    cat /tmp/project_results.json
    exit 1
fi


# Clean up any existing repository
if [ -d "/root/quantization-test-ui" ]; then
    echo "Removing existing quantization-test-ui directory..."
    rm -rf /root/quantization-test-ui
fi

git clone https://github.com/sunilemanjee/quantization-test-ui.git

cd /root/quantization-test-ui

# Create variables.env with the simplified structure
echo "Creating variables.env with simplified structure..."
cat > variables.env << EOF
ES_URL=$ES_URL
ES_API_KEY=$API_KEY
ES_INDEX=properties
EOF

echo "Successfully created variables.env with:"
echo "  ES_URL=$ES_URL"
echo "  ES_API_KEY=${API_KEY:0:10}..."
echo "  ES_INDEX=properties"

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
mkdir -p /root/quantization-test-ui/logs

# Source environment and run in background with logging
echo "Starting quantization test UI in background..."

# Run the application in background and redirect output to logs
nohup python app.py > /root/quantization-test-ui/logs/quantization_ui.log 2>&1 &

# Get the background process ID
QUANTIZATION_UI_PID=$!

# Save PID to file for later reference
echo $QUANTIZATION_UI_PID > /root/quantization-test-ui/logs/quantization_ui.pid

echo "Quantization test UI started in background with PID: $QUANTIZATION_UI_PID"
echo "Logs are being written to: /root/quantization-test-ui/logs/quantization_ui.log"
echo "PID file saved to: /root/quantization-test-ui/logs/quantization_ui.pid"