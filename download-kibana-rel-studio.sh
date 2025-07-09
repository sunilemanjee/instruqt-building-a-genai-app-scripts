#!/bin/bash

# Script to download kibana-rel-studio.sh from GitHub and install it

echo "Downloading kibana-rel-studio.sh from GitHub..."

# Check if file already exists and inform user it will be overwritten
if [ -f /root/kibana-rel-studio.sh ]; then
    echo "File /root/kibana-rel-studio.sh already exists - it will be overwritten"
fi

# Download the script using curl (this will overwrite existing file)
curl -o /root/kibana-rel-studio.sh https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/kibana-rel-studio.sh

# Check if download was successful
if [ $? -eq 0 ]; then
    echo "Successfully downloaded kibana-rel-studio.sh to /root/"
    
    # Make the script executable
    chmod 755 /root/kibana-rel-studio.sh
    
    if [ $? -eq 0 ]; then
        echo "Successfully set executable permissions (755) on /root/kibana-rel-studio.sh"
        echo "Installation complete!"
        echo ""
        echo "Now running /root/kibana-rel-studio.sh..."
        echo "----------------------------------------"
        /root/kibana-rel-studio.sh
    else
        echo "Error: Failed to set executable permissions on /root/kibana-rel-studio.sh"
        exit 1
    fi
else
    echo "Error: Failed to download kibana-rel-studio.sh from GitHub"
    echo "Please check your internet connection and try again"
    exit 1
fi 