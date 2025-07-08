#!/bin/bash



# Function to setup environment and fetch API key
setup_environment() {
    # Fetch project results and store in /tmp/project_results.json
    echo "Fetching project results from http://es3-api-v1:8081..."
    curl -s http://es3-api-v1:8081 > /tmp/project_results.json

    if [ $? -eq 0 ]; then
        echo "Project results saved to /tmp/project_results.json"
    else
        echo "Warning: Failed to fetch project results from http://es3-api-v1:8081"
    fi

    # Change to the relevance-studio directory
    cd /root/relevance-studio

    # Create .env file from reference if it doesn't exist
    if [ ! -f .env ]; then
        if [ -f .env-reference ]; then
            cp .env-reference .env
            echo "Created .env file from .env-reference"
        else
            echo "Warning: .env-reference not found, creating empty .env file"
            touch .env
        fi
    fi

    # Fetch API key from the endpoint
    echo "Fetching API key from http://es3-api-v1:8081..."
    API_RESPONSE=$(curl -s http://es3-api-v1:8081)
    
    if [ $? -eq 0 ] && [ ! -z "$API_RESPONSE" ]; then
        # Extract API key using jq (if available) or grep/sed
        if command -v jq &> /dev/null; then
            API_KEY=$(echo "$API_RESPONSE" | jq -r '.["aws-us-east-1"].credentials.api_key')
        else
            # Fallback to grep/sed if jq is not available
            API_KEY=$(echo "$API_RESPONSE" | grep -o '"api_key": "[^"]*"' | sed 's/"api_key": "\([^"]*\)"/\1/')
        fi
        
        if [ ! -z "$API_KEY" ] && [ "$API_KEY" != "null" ]; then
            echo "API key retrieved successfully"
            
            # Update .env file with the API key
            if grep -q "CONTENT_ELASTICSEARCH_API_KEY" .env; then
                # Update existing line
                sed -i "s|CONTENT_ELASTICSEARCH_API_KEY=.*|CONTENT_ELASTICSEARCH_API_KEY=$API_KEY|" .env
            else
                # Add new line
                echo "CONTENT_ELASTICSEARCH_API_KEY=$API_KEY" >> .env
            fi
            echo "CONTENT_ELASTICSEARCH_API_KEY updated in .env"
        else
            echo "Warning: Could not extract API key from response"
        fi
    else
        echo "Warning: Failed to fetch API key from http://es3-api-v1:8081"
    fi

    # Set the Elasticsearch URL in .env
    if grep -q "CONTENT_ELASTICSEARCH_URL" .env; then
        # Update existing line
        sed -i "s|CONTENT_ELASTICSEARCH_URL=.*|CONTENT_ELASTICSEARCH_URL=http://es3-api-v1:8081|" .env
    else
        # Add new line
        echo "CONTENT_ELASTICSEARCH_URL=http://es3-api-v1:8081" >> .env
    fi
    echo "CONTENT_ELASTICSEARCH_URL set to http://es3-api-v1:8081 in .env"

    # Add environment variables to disable host checking for development servers
    if grep -q "WDS_SOCKET_HOST" .env; then
        # Update existing line
        sed -i "s|WDS_SOCKET_HOST=.*|WDS_SOCKET_HOST=0.0.0.0|" .env
    else
        # Add new line
        echo "WDS_SOCKET_HOST=0.0.0.0" >> .env
    fi
    
    if grep -q "WDS_SOCKET_PORT" .env; then
        # Update existing line
        sed -i "s|WDS_SOCKET_PORT=.*|WDS_SOCKET_PORT=0|" .env
    else
        # Add new line
        echo "WDS_SOCKET_PORT=0" >> .env
    fi
    
    if grep -q "DANGEROUSLY_DISABLE_HOST_CHECK" .env; then
        # Update existing line
        sed -i "s|DANGEROUSLY_DISABLE_HOST_CHECK=.*|DANGEROUSLY_DISABLE_HOST_CHECK=true|" .env
    else
        # Add new line
        echo "DANGEROUSLY_DISABLE_HOST_CHECK=true" >> .env
    fi
    
    echo "Development server host checking disabled in .env"
    
    # Comment out cloud Elasticsearch variables to prevent conflicts
    echo "Ensuring cloud Elasticsearch variables are commented out..."
    
    # Comment out ELASTIC_CLOUD_ID if it exists
    if grep -q "^ELASTIC_CLOUD_ID=" .env; then
        sed -i "s|^ELASTIC_CLOUD_ID=|#ELASTIC_CLOUD_ID=|" .env
        echo "Commented out ELASTIC_CLOUD_ID in .env"
    fi
    
    # Comment out ELASTICSEARCH_USERNAME if it exists
    if grep -q "^ELASTICSEARCH_USERNAME=" .env; then
        sed -i "s|^ELASTICSEARCH_USERNAME=|#ELASTICSEARCH_USERNAME=|" .env
        echo "Commented out ELASTICSEARCH_USERNAME in .env"
    fi
    
    # Comment out ELASTICSEARCH_PASSWORD if it exists
    if grep -q "^ELASTICSEARCH_PASSWORD=" .env; then
        sed -i "s|^ELASTICSEARCH_PASSWORD=|#ELASTICSEARCH_PASSWORD=|" .env
        echo "Commented out ELASTICSEARCH_PASSWORD in .env"
    fi
    
    echo "Cloud Elasticsearch variables check completed"
}

# Function to kill any process running on a specified port
kill_port() {
    local PORT=$1
    echo "Checking for processes running on port $PORT..."
    
    # Find processes using the specified port
    PIDS=$(lsof -ti:$PORT 2>/dev/null)
    
    if [ ! -z "$PIDS" ]; then
        echo "Found processes running on port $PORT: $PIDS"
        for PID in $PIDS; do
            echo "Killing process $PID on port $PORT..."
            kill -9 $PID 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "Successfully killed process $PID"
            else
                echo "Failed to kill process $PID (may have already exited)"
            fi
        done
        sleep 2
        
        # Verify port is free
        NEW_PIDS=$(lsof -ti:$PORT 2>/dev/null)
        if [ -z "$NEW_PIDS" ]; then
            echo "Port $PORT is now free"
        else
            echo "Warning: Port $PORT still has processes running: $NEW_PIDS"
        fi
    else
        echo "No processes found running on port $PORT"
    fi
}

# Function to kill any process running on port 8080
kill_port_8080() {
    kill_port 8080
}

# Function to kill any process running on port 4096
kill_port_4096() {
    kill_port 4096
}

# Function to kill servers
kill_servers() {
    echo "Stopping Flask server..."
    pkill -f "python -m src.server.flask"
    
    echo "Stopping Yarn dev server..."
    pkill -f "yarn run dev"
    
    echo "Killing processes on ports 8080 and 4096..."
    kill_port_8080
    kill_port_4096
    
    echo "Checking if processes are still running..."
    sleep 2
    
    # Check if Flask is still running
    if pgrep -f "python -m src.server.flask" > /dev/null; then
        echo "Flask server is still running"
    else
        echo "Flask server stopped successfully"
    fi
    
    # Check if Yarn is still running
    if pgrep -f "yarn run dev" > /dev/null; then
        echo "Yarn dev server is still running"
    else
        echo "Yarn dev server stopped successfully"
    fi
}

# Function to start servers
start_servers() {
    # Kill any processes running on ports 8080 and 4096 first
    kill_port_8080
    kill_port_4096
    
    # Setup environment and fetch API key
    setup_environment
    
    # Initialize conda environment
    echo 'eval "$(/root/miniconda3/bin/conda shell.bash hook)"' >> ~/.bashrc
    source ~/.bashrc

    # Activate the esrs conda environment
    conda activate esrs

    # Change to the relevance-studio directory (already done in setup_environment)
    cd /root/relevance-studio

    # Create logs directory if it doesn't exist
    mkdir -p logs

    # Run the Flask server in the background with logging
    python -m src.server.flask > logs/flask_server.log 2>&1 &

    # Print the process ID for reference
    echo "Flask server started in background with PID: $!"
    echo "Flask logs will be written to: logs/flask_server.log"

    # Optional: Wait a moment and check if the process is running
    sleep 2
    if ps -p $! > /dev/null; then
        echo "Flask server is running successfully"
        
        # Run yarn dev in the background with logging
        # Use --host 0.0.0.0 to allow connections from any hostname
        yarn run dev --host 0.0.0.0 > logs/yarn_dev.log 2>&1 &
        echo "Yarn dev started in background with PID: $!"
        echo "Yarn logs will be written to: logs/yarn_dev.log"
        
        # Wait a moment and check if yarn dev is running
        sleep 2
        if ps -p $! > /dev/null; then
            echo "Yarn dev is running successfully"
            echo ""
            echo "Both servers are running in the background!"
            echo "To view logs:"
            echo "  Flask logs: tail -f logs/flask_server.log"
            echo "  Yarn logs: tail -f logs/yarn_dev.log"
            echo "To stop servers: ./start-flask-and-yarn.sh --kill"
        else
            echo "Failed to start yarn dev"
            exit 1
        fi
    else
        echo "Failed to start Flask server"
        exit 1
    fi
}

# Function to restart servers
restart_servers() {
    echo "Restarting servers..."
    kill_servers
    kill_port_8080
    kill_port_4096
    sleep 3
    start_servers
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --start, -s     Start Flask and Yarn servers (default)"
    echo "  --kill, -k      Kill Flask and Yarn servers"
    echo "  --restart, -r   Restart Flask and Yarn servers"
    echo "  --setup, -e     Setup environment only (fetch API key, update .env)"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Start servers (default)"
    echo "  $0 --start      # Start servers"
    echo "  $0 --kill       # Kill servers"
    echo "  $0 --restart    # Restart servers"
    echo "  $0 --setup      # Setup environment only"
}

# Parse command line arguments
case "${1:-start}" in
    --start|-s|start)
        start_servers
        ;;
    --kill|-k)
        kill_servers
        ;;
    --restart|-r)
        restart_servers
        ;;
    --setup|-e)
        setup_environment
        ;;
    --help|-h)
        show_usage
        ;;
    *)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac 