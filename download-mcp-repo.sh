#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#
# Script to download clone_and_setup_elastic_mcp.sh from GitHub and install it

# Set error handling
set -e

# Configuration
MAIN_SCRIPT="clone_and_setup_elastic_mcp.sh"
SCRIPTS=("reingest-with-endpoints.sh" "create-inference-endpoints.sh")
INSTALL_DIR="${INSTALL_DIR:-/root}"

echo "Downloading scripts from GitHub..."

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

# Download the main script (clone_and_setup_elastic_mcp.sh)
GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/main/${MAIN_SCRIPT}"
TARGET_PATH="${INSTALL_DIR}/${MAIN_SCRIPT}"

echo "Downloading ${MAIN_SCRIPT} from GitHub..."

# Check if file already exists and inform user it will be overwritten
if [ -f "$TARGET_PATH" ]; then
    echo "File $TARGET_PATH already exists - it will be overwritten"
fi

# Download the script using curl with error handling
echo "Downloading from: $GITHUB_URL"
if curl -f -L -o "$TARGET_PATH" "$GITHUB_URL"; then
    echo "Successfully downloaded ${MAIN_SCRIPT} to $INSTALL_DIR/"
    
    # Make the script executable
    if chmod 755 "$TARGET_PATH"; then
        echo "Successfully set executable permissions (755) on $TARGET_PATH"
    else
        echo "Error: Failed to set executable permissions on $TARGET_PATH"
        exit 1
    fi
else
    echo "Error: Failed to download ${MAIN_SCRIPT} from GitHub"
    echo "Please check your internet connection and try again"
    echo "URL attempted: $GITHUB_URL"
    exit 1
fi


# Download each script
for SCRIPT_NAME in "${SCRIPTS[@]}"; do
    GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/${SCRIPT_NAME}"
    TARGET_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"
    
    echo ""
    echo "Processing: ${SCRIPT_NAME}"
    
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
done


echo ""
echo "All scripts downloaded successfully!"
echo "Installation complete!"

# Now run the main script (clone_and_setup_elastic_mcp.sh)
echo ""
echo "Now running $TARGET_PATH..."
echo "----------------------------------------"
"${INSTALL_DIR}/${MAIN_SCRIPT}" 