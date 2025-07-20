#!/bin/bash

echo "Starting reingestion with endpoints..."

# Deactivate the current virtual environment if active
if [[ "$VIRTUAL_ENV" != "" ]]; then
    echo "Deactivating current virtual environment..."
    deactivate
fi

# Navigate to the Elastic-Python-MCP-Server directory
echo "Navigating to Elastic-Python-MCP-Server directory..."
cd /root/Elastic-Python-MCP-Server

if [ ! -d "/root/Elastic-Python-MCP-Server" ]; then
    echo "Error: Elastic-Python-MCP-Server directory not found at /root/Elastic-Python-MCP-Server"
    exit 1
fi

echo "Current directory: $(pwd)"

# Activate the virtual environment
if [ -d "venv" ]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
    echo "Virtual environment activated successfully!"
else
    echo "Error: Virtual environment not found in /root/Elastic-Python-MCP-Server/venv"
    exit 1
fi

# Navigate to data-ingestion directory
if [ -d "data-ingestion" ]; then
    echo "Changing to data-ingestion directory..."
    cd data-ingestion
    echo "Current directory: $(pwd)"
else
    echo "Error: data-ingestion directory not found"
    exit 1
fi

# Run the reingestion script with endpoints flag
if [ -f "run-ingestion.sh" ]; then
    echo "Running reingestion script with --reingest-instruqt-with-endpoints flag..."
    chmod +x run-ingestion.sh
    source ../env_config.sh && ./run-ingestion.sh --reingest-instruqt-with-endpoints
    if [ $? -eq 0 ]; then
        echo "Reingestion with endpoints completed successfully!"
    else
        echo "Error: Reingestion with endpoints failed"
        exit 1
    fi
else
    echo "Error: run-ingestion.sh not found in data-ingestion directory"
    exit 1
fi

echo "Reingestion with endpoints process completed!" 