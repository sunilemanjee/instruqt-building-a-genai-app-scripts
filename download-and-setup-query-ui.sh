#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#
# Download and run setup-query-tuning-ui.sh script
echo "Downloading setup-query-tuning-ui.sh from GitHub..."

# Download the script to /root/
curl -s -o /root/setup-query-tuning-ui.sh https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/setup-query-tuning-ui.sh

# Check if download was successful
if [ $? -eq 0 ]; then
    echo "Download successful!"
else
    echo "Error: Failed to download setup-query-tuning-ui.sh"
    exit 1
fi

# Set executable permissions
echo "Setting executable permissions..."
chmod 755 /root/setup-query-tuning-ui.sh

if [ $? -eq 0 ]; then
    echo "Permissions set successfully!"
else
    echo "Error: Failed to set permissions"
    exit 1
fi

# Verify the file exists and is executable
if [ -x "/root/setup-query-tuning-ui.sh" ]; then
    echo "Script is ready to execute!"
    echo "Starting setup-query-tuning-ui.sh..."
    echo "=================================="
    
    # Run the setup script
    /root/setup-query-tuning-ui.sh
    
    echo "=================================="
    echo "Setup script execution completed!"
else
    echo "Error: Script file is not executable or does not exist"
    exit 1
fi 