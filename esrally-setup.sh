#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#

# Initialize success tracking
PROJECT_RESULTS_SUCCESS=false
ELAND_DOWNLOAD_SUCCESS=false

# Check if required environment variable is set
if [ -z "$PROXY_ES_KEY_BROKER" ]; then
    echo "Error: PROXY_ES_KEY_BROKER environment variable is not set"
    exit 1
fi

# Function 1: Fetch project results and store in /tmp/project_results.json
fetch_project_results() {
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
            PROJECT_RESULTS_SUCCESS=true
            return 0
        else
            echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
            [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
        fi
    done
    
    echo "Error: Failed to download project results after $MAX_RETRIES attempts"
    return 1
}

# Function 2: Download set-eland-env-variables.sh to /root/
download_eland_script() {
    echo ""
    echo "Downloading set-eland-env-variables.sh to /root/..."
    
    # Define the workshop directory and target file
    WORKSHOP_DIR="/root"
    ENV_VARS_FILE="$WORKSHOP_DIR/set-eland-env-variables.sh"
    ENV_VARS_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/set-eland-env-variables.sh"
    
    # Create workshop directory if it doesn't exist
    if [ ! -d "$WORKSHOP_DIR" ]; then
        echo "Creating workshop directory: $WORKSHOP_DIR"
        mkdir -p "$WORKSHOP_DIR"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create workshop directory"
            return 1
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
            return 1
        fi
        
        if ! head -n 1 "$ENV_VARS_FILE" | grep -q "^#!"; then
            echo "Error: Downloaded file does not appear to be a valid script (missing shebang)"
            return 1
        fi
        
        # Make the script executable
        chmod 755 "$ENV_VARS_FILE"
        
        if [ $? -eq 0 ]; then
            echo "Successfully set executable permissions (755) on $ENV_VARS_FILE"
            echo "set-eland-env-variables.sh installation complete!"
            ELAND_DOWNLOAD_SUCCESS=true
            return 0
        else
            echo "Error: Failed to set executable permissions on $ENV_VARS_FILE"
            return 1
        fi
    else
        echo "Error: Failed to download set-eland-env-variables.sh from GitHub"
        echo "Please check your internet connection and try again"
        echo "URL: $ENV_VARS_URL"
        return 1
    fi
}

# Main execution
echo "Starting ES Rally setup script..."
echo "=================================="

# Execute both operations
fetch_project_results
PROJECT_RESULTS_EXIT_CODE=$?

download_eland_script
ELAND_DOWNLOAD_EXIT_CODE=$?

# Summary and final exit
echo ""
echo "=================================="
echo "Script execution summary:"
echo "Project results fetch: $([ "$PROJECT_RESULTS_SUCCESS" = true ] && echo "SUCCESS" || echo "FAILED")"
echo "Eland script download: $([ "$ELAND_DOWNLOAD_SUCCESS" = true ] && echo "SUCCESS" || echo "FAILED")"

if [ "$PROJECT_RESULTS_SUCCESS" = true ] && [ "$ELAND_DOWNLOAD_SUCCESS" = true ]; then
    echo "All operations completed successfully!"
    exit 0
elif [ "$PROJECT_RESULTS_SUCCESS" = true ]; then
    echo "Project results fetched successfully, but eland script download failed."
    exit 1
elif [ "$ELAND_DOWNLOAD_SUCCESS" = true ]; then
    echo "Eland script downloaded successfully, but project results fetch failed."
    exit 1
else
    echo "All operations failed."
    exit 1
fi