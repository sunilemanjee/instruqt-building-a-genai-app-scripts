#!/bin/bash

# Script to download clone_and_setup_elastic_mcp.sh from GitHub and install it

# Set error handling
set -e

# Configuration
SCRIPT_NAME="reingest-with-endpoints.sh"
INSTALL_DIR="${INSTALL_DIR:-/root}"
GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/${SCRIPT_NAME}"
TARGET_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"

echo "Downloading ${SCRIPT_NAME} from GitHub..."

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install curl and try again."
    exit 1
fi

# Check if target directory exists and is writable
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: Target directory $INSTALL_DIR does not exist"
    exit 1
fi

if [ ! -w "$INSTALL_DIR" ]; then
    echo "Error: Target directory $INSTALL_DIR is not writable"
    exit 1
fi

# Check if file already exists and inform user it will be overwritten
if [ -f "$TARGET_PATH" ]; then
    echo "File $TARGET_PATH already exists - it will be overwritten"
fi

# Download the script using curl with error handling
echo "Downloading from: $GITHUB_URL"
if curl -f -L -o "$TARGET_PATH" "$GITHUB_URL"; then
    echo "Successfully downloaded ${SCRIPT_NAME} to $INSTALL_DIR/"
    
    # Make the script executable
    if chmod 755 "$TARGET_PATH"; then
        echo "Successfully set executable permissions (755) on $TARGET_PATH"
        echo "Installation complete!"
        echo ""
        echo "Now running $TARGET_PATH..."
        echo "----------------------------------------"
        "$TARGET_PATH"
    else
        echo "Error: Failed to set executable permissions on $TARGET_PATH"
        exit 1
    fi
else
    echo "Error: Failed to download ${SCRIPT_NAME} from GitHub"
    echo "Please check your internet connection and try again"
    echo "URL attempted: $GITHUB_URL"
    exit 1
fi 