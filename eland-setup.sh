#!/bin/bash

# Script to clone Elastic-Python-MCP-Server and setup environment config

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
        echo "Project results content:"
        cat /tmp/project_results.json
        echo ""
        
        # Check if the response contains valid JSON and has the api_key
        if command -v jq &> /dev/null; then
            echo "Using jq to parse JSON..."
            
            # Debug: Check JSON structure
            echo "JSON structure:"
            jq '.' /tmp/project_results.json 2>/dev/null || echo "Invalid JSON structure"
            
            # Use jq to validate JSON and extract api_key, ES_URL, and KIBANA_URL
            # Get the first (and only) region key from the JSON
            API_KEY=$(jq -r 'to_entries[0].value.credentials.api_key' /tmp/project_results.json 2>/dev/null)
            ES_URL=$(jq -r 'to_entries[0].value.endpoints.elasticsearch' /tmp/project_results.json 2>/dev/null)
            KIBANA_URL=$(jq -r 'to_entries[0].value.endpoints.kibana' /tmp/project_results.json 2>/dev/null)

            echo "DEBUG - Raw extracted values:"
            echo "API_KEY: '$API_KEY'"
            echo "ES_URL: '$ES_URL'"
            echo "KIBANA_URL: '$KIBANA_URL'"

            echo "Reading LLM credentials from /tmp/project_results.json..."
            # Extract LLM credentials from the JSON file
            OPENAI_API_KEY=$(jq -r 'to_entries[0].value.credentials.llm_api_key' /tmp/project_results.json 2>/dev/null)
            LLM_HOST=$(jq -r 'to_entries[0].value.credentials.llm_host' /tmp/project_results.json 2>/dev/null)
            LLM_CHAT_URL=$(jq -r 'to_entries[0].value.credentials.llm_chat_url' /tmp/project_results.json 2>/dev/null)
            echo "OPENAI_API_KEY: $OPENAI_API_KEY"
            echo "LLM_HOST: $LLM_HOST"
            echo "LLM_CHAT_URL: $LLM_CHAT_URL"

            # Set agent variables with the retrieved LLM credentials
            agent variable set LLM_KEY "$OPENAI_API_KEY"
            agent variable set LLM_HOST "$LLM_HOST"
            agent variable set LLM_CHAT_URL "$LLM_CHAT_URL"
            
            if [ $? -eq 0 ] && [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ] && [ ! -z "$ES_URL" ] && [ "$ES_URL" != "null" ] && [ ! -z "$KIBANA_URL" ] && [ "$KIBANA_URL" != "null" ] && [ ! -z "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "null" ] && [ ! -z "$LLM_HOST" ] && [ "$LLM_HOST" != "null" ] && [ ! -z "$LLM_CHAT_URL" ] && [ "$LLM_CHAT_URL" != "null" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                echo "ES URL found: $ES_URL"
                echo "Kibana URL found: $KIBANA_URL"
                
                # Export all environment variables
                export ES_API_KEY="$API_KEY"
                export ES_URL="$ES_URL"
                export KIBANA_URL="$KIBANA_URL"
                export OPENAI_API_KEY="$OPENAI_API_KEY"
                export LLM_HOST="$LLM_HOST"
                export LLM_CHAT_URL="$LLM_CHAT_URL"
                
                echo "DEBUG - After export:"
                echo "ES_API_KEY: '$ES_API_KEY'"
                echo "ES_URL: '$ES_URL'"
                echo "KIBANA_URL: '$KIBANA_URL'"
                
                # Set agent variables
                echo "Setting agent variable ES_API_KEY..."
                agent variable set ES_API_KEY "$API_KEY"
                echo "Setting agent variable ES_URL..."
                agent variable set ES_URL "$ES_URL"
                echo "Setting agent variable KIBANA_URL..."
                agent variable set KIBANA_URL "$KIBANA_URL"
                break
            else
                echo "API key, ES URL, Kibana URL, or LLM credentials not found or invalid in response on attempt $attempt"
                echo "DEBUG - Validation failed:"
                echo "API_KEY empty: $([ -z "$API_KEY" ] && echo "YES" || echo "NO")"
                echo "API_KEY null: $([ "$API_KEY" = "null" ] && echo "YES" || echo "NO")"
                echo "ES_URL empty: $([ -z "$ES_URL" ] && echo "YES" || echo "NO")"
                echo "ES_URL null: $([ "$ES_URL" = "null" ] && echo "YES" || echo "NO")"
                [ $attempt -lt $MAX_RETRIES ] && echo "Waiting $RETRY_WAIT seconds before retry..." && sleep $RETRY_WAIT
            fi
        else
            echo "Using grep/sed fallback to parse JSON..."
            # Fallback to grep/sed if jq is not available
            API_KEY=$(grep -o '"api_key": "[^"]*"' /tmp/project_results.json | sed 's/"api_key": "\([^"]*\)"/\1/' 2>/dev/null)
            ES_URL=$(grep -o '"elasticsearch": "[^"]*"' /tmp/project_results.json | sed 's/"elasticsearch": "\([^"]*\)"/\1/' 2>/dev/null)
            KIBANA_URL=$(grep -o '"kibana": "[^"]*"' /tmp/project_results.json | sed 's/"kibana": "\([^"]*\)"/\1/' 2>/dev/null)
            
            echo "DEBUG - Raw extracted values (grep/sed):"
            echo "API_KEY: '$API_KEY'"
            echo "ES_URL: '$ES_URL'"
            echo "KIBANA_URL: '$KIBANA_URL'"
            
            # Extract LLM credentials using grep/sed fallback
            OPENAI_API_KEY=$(grep -o '"llm_api_key": "[^"]*"' /tmp/project_results.json | sed 's/"llm_api_key": "\([^"]*\)"/\1/' 2>/dev/null)
            LLM_HOST=$(grep -o '"llm_host": "[^"]*"' /tmp/project_results.json | sed 's/"llm_host": "\([^"]*\)"/\1/' 2>/dev/null)
            LLM_CHAT_URL=$(grep -o '"llm_chat_url": "[^"]*"' /tmp/project_results.json | sed 's/"llm_chat_url": "\([^"]*\)"/\1/' 2>/dev/null)
            
            echo "OPENAI_API_KEY: $OPENAI_API_KEY"
            echo "LLM_HOST: $LLM_HOST"
            echo "LLM_CHAT_URL: $LLM_CHAT_URL"
            
            if [ ! -z "$API_KEY" ] && [ ! -z "$ES_URL" ] && [ ! -z "$KIBANA_URL" ] && [ ! -z "$OPENAI_API_KEY" ] && [ ! -z "$LLM_HOST" ] && [ ! -z "$LLM_CHAT_URL" ]; then
                echo "API key found successfully: ${API_KEY:0:10}..."
                echo "ES URL found: $ES_URL"
                echo "Kibana URL found: $KIBANA_URL"
                
                # Export all environment variables
                export ES_API_KEY="$API_KEY"
                export ES_URL="$ES_URL"
                export KIBANA_URL="$KIBANA_URL"
                export OPENAI_API_KEY="$OPENAI_API_KEY"
                export LLM_HOST="$LLM_HOST"
                export LLM_CHAT_URL="$LLM_CHAT_URL"
                
                echo "DEBUG - After export (grep/sed):"
                echo "ES_API_KEY: '$ES_API_KEY'"
                echo "ES_URL: '$ES_URL'"
                echo "KIBANA_URL: '$KIBANA_URL'"
                
                # Set agent variables
                echo "Setting agent variable ES_API_KEY..."
                agent variable set ES_API_KEY "$API_KEY"
                echo "Setting agent variable ES_URL..."
                agent variable set ES_URL "$ES_URL"
                echo "Setting agent variable KIBANA_URL..."
                agent variable set KIBANA_URL "$KIBANA_URL"
                echo "Setting agent variable LLM_KEY..."
                agent variable set LLM_KEY "$OPENAI_API_KEY"
                echo "Setting agent variable LLM_HOST..."
                agent variable set LLM_HOST "$LLM_HOST"
                echo "Setting agent variable LLM_CHAT_URL..."
                agent variable set LLM_CHAT_URL "$LLM_CHAT_URL"
                break
            else
                echo "API key, ES URL, Kibana URL, or LLM credentials not found in response on attempt $attempt"
                echo "DEBUG - Validation failed (grep/sed):"
                echo "API_KEY empty: $([ -z "$API_KEY" ] && echo "YES" || echo "NO")"
                echo "ES_URL empty: $([ -z "$ES_URL" ] && echo "YES" || echo "NO")"
                echo "KIBANA_URL empty: $([ -z "$KIBANA_URL" ] && echo "YES" || echo "NO")"
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

echo "All environment variables set successfully:"
echo "ES_API_KEY: ${ES_API_KEY:0:10}..."
echo "ES_URL: $ES_URL"
echo "KIBANA_URL: $KIBANA_URL"
echo "OPENAI_API_KEY: ${OPENAI_API_KEY:0:10}..."
echo "LLM_HOST: $LLM_HOST"
echo "LLM_CHAT_URL: $LLM_CHAT_URL"

# Final verification
echo ""
echo "Final verification of environment variables:"
echo "ES_API_KEY: '$ES_API_KEY'"
echo "ES_URL: '$ES_URL'"
echo "KIBANA_URL: '$KIBANA_URL'"

# Output variables in a format that can be sourced
echo ""
echo "# Environment variables for sourcing:"
echo "export ES_API_KEY=\"$ES_API_KEY\""
echo "export ES_URL=\"$ES_URL\""
echo "export KIBANA_URL=\"$KIBANA_URL\""
echo "export OPENAI_API_KEY=\"$OPENAI_API_KEY\""
echo "export LLM_HOST=\"$LLM_HOST\""
echo "export LLM_CHAT_URL=\"$LLM_CHAT_URL\""
