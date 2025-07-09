#!/bin/bash
echo "Restart NGINX"
systemctl restart nginx

echo "Setting up JSON server on port 8081..."

# Check if the JSON file exists
if [ ! -f "/tmp/project_results.json" ]; then
    echo "Warning: /tmp/project_results.json not found!"
    echo "The server will return an error when accessed."
fi

# Assume nothing is running on port 8081
echo "Starting JSON server on port 8081..."

# Start the server in background
echo "Starting JSON server in background..."
python3 bin/serve_json.py > /tmp/server-serve-json.log 2>&1 &

# Get the process ID
SERVER_PID=$!

# Wait a moment for the server to start
sleep 2

# Check if server started successfully
sleep 2
if kill -0 $SERVER_PID 2>/dev/null; then
    echo ":white_check_mark: Server started successfully!"
    echo ":bar_chart: Server PID: $SERVER_PID"
    echo ":memo: Logs: /tmp/server-serve-json.log"
    echo ":globe_with_meridians: Access URL: http://localhost:8081"
    echo ""
    echo ":clipboard: Useful commands:"
    echo "  View logs: tail -f /tmp/server-serve-json.log"
    echo "  Test server: curl http://localhost:8081"
    echo "  Stop server: kill $SERVER_PID"
    echo "  Check status: ps aux | grep serve_json"
else
    echo ":x: Failed to start server"
    echo "Check /tmp/server-serve-json.log for details:"
    if [ -f "/tmp/server-serve-json.log" ]; then
        tail -5 /tmp/server-serve-json.log
    else
        echo "No log file found"
    fi
    exit 1
fi 