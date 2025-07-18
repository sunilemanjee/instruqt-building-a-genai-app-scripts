#!/bin/bash

# Script to download eland-setup.sh from GitHub and install it

# Define the target file path
TARGET_FILE="/root/eland-setup.sh"
GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/eland-setup.sh"

echo "Downloading eland-setup.sh from GitHub..."

# Check if file already exists and inform user it will be overwritten
if [ -f "$TARGET_FILE" ]; then
    echo "File $TARGET_FILE already exists - it will be overwritten"
fi

# Download the script using curl with fail-on-error flag
curl -f -o "$TARGET_FILE" "$GITHUB_URL"

# Check if download was successful
if [ $? -eq 0 ]; then
    echo "Successfully downloaded eland-setup.sh to /root/"
    
    # Validate that the downloaded file is not empty and contains script content
    if [ ! -s "$TARGET_FILE" ]; then
        echo "Error: Downloaded file is empty"
        exit 1
    fi
    
    if ! head -n 1 "$TARGET_FILE" | grep -q "^#!"; then
        echo "Error: Downloaded file does not appear to be a valid script (missing shebang)"
        exit 1
    fi
    
    # Make the script executable
    chmod 755 "$TARGET_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Successfully set executable permissions (755) on $TARGET_FILE"
        echo "Installation complete!"
        echo ""
        echo "Now sourcing $TARGET_FILE to set environment variables..."
        echo "----------------------------------------"
        source "$TARGET_FILE"
    else
        echo "Error: Failed to set executable permissions on $TARGET_FILE"
        exit 1
    fi
else
    echo "Error: Failed to download eland-setup.sh from GitHub"
    echo "Please check your internet connection and try again"
    echo "URL: $GITHUB_URL"
    exit 1
fi 