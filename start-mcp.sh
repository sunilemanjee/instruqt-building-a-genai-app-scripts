#!/bin/bash

# Create logs directory if it doesn't exist
mkdir -p logs

# Start Elastic MCP Server
echo "Starting Elastic MCP Server..."
cd /root/Elastic-Python-MCP-Server/

source venv/bin/activate

source env_config.sh

./run_server.sh --background

# Start Chainlit Application in background
echo "Starting Chainlit Application..."
cd /root/Elastic-AI-Infused-Property-Search/

source setenv.sh

# Run chainlit in background and redirect output to logs
nohup chainlit run src/app.py > logs/chainlit.log 2>&1 &

# Save the background process ID
echo $! > logs/chainlit.pid

echo "Chainlit application started in background with PID: $(cat logs/chainlit.pid)"
echo "Logs are being written to: logs/chainlit.log"
echo "To stop the application, run: kill \$(cat logs/chainlit.pid)"