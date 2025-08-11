#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#

# Initialize success tracking
PROJECT_RESULTS_SUCCESS=false

# Function to check if required environment variables are set
check_environment() {
    local missing_vars=()
    
    # Check required variables
    if [ -z "$PROXY_ES_KEY_BROKER" ]; then
        missing_vars+=("PROXY_ES_KEY_BROKER")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "Error: The following required environment variables are not set:"
        printf '  %s\n' "${missing_vars[@]}"
        exit 1
    fi
    
    # Display environment information
    echo "Environment variables:"
    echo "  PROXY_ES_KEY_BROKER: $PROXY_ES_KEY_BROKER"
    echo ""
}

# Function: Fetch project results and store in /tmp/project_results.json
fetch_project_results() {
    echo "=== Fetching Project Results ==="
    echo "Fetching project results from $PROXY_ES_KEY_BROKER..."
    
    MAX_RETRIES=10
    RETRY_WAIT=30
    
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "Attempt $attempt of $MAX_RETRIES at $(date)"
        
        # Fetch the response
        if curl -s "$PROXY_ES_KEY_BROKER" > /tmp/project_results.json; then
            echo "Project results saved to /tmp/project_results.json"
            echo "Download completed successfully!"
            PROJECT_RESULTS_SUCCESS=true
            return 0
        else
            echo "Failed to fetch project results from $PROXY_ES_KEY_BROKER on attempt $attempt"
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "Waiting $RETRY_WAIT seconds before retry..."
                sleep $RETRY_WAIT
            fi
        fi
    done
    
    echo "Error: Failed to download project results after $MAX_RETRIES attempts"
    return 1
}

# Main execution
main() {
    echo "Starting VSCode setup script..."
    echo ""
    
    # Check environment variables
    check_environment
    
    # Fetch project results
    if fetch_project_results; then
        echo "✓ Project results fetched successfully"
    else
        echo "✗ Failed to fetch project results"
    fi
    
    echo ""
    
    # Summary
    echo "=== Setup Summary ==="
    echo "Project Results: $([ "$PROJECT_RESULTS_SUCCESS" = true ] && echo "✓ Success" || echo "✗ Failed")"
    
    # Exit with appropriate code
    if [ "$PROJECT_RESULTS_SUCCESS" = true ]; then
        echo "All operations completed successfully!"
        exit 0
    else
        echo "Project results fetch failed. Check the output above for details."
        exit 1
    fi
}

# Run main function
main "$@"


