#!/bin/bash

# Exit on any error
set -e

# Start Elastic MCP Server
echo "Starting Elastic MCP Server..."
cd /root/Elastic-Python-MCP-Server/


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
