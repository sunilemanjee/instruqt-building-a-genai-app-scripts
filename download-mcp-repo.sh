#!/bin/bash

# Script to download clone_and_setup_elastic_mcp.sh from GitHub and install it

# Set error handling
set -e

# Configuration
SCRIPTS=("reingest-with-endpoints.sh" "create-inference-endpoints.sh")
QUANTIZATION_SCRIPTS=("create_indices_and_reindex.sh")
QUANTIZATION_FILES=("index-mapping-int4flat.json" "index-mapping-int8flat.json" "index-mapping-bbqflat.json")
INSTALL_DIR="${INSTALL_DIR:-/root}"
QUANTIZATION_DIR="${INSTALL_DIR}/quantization-indices"

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

# Create quantization directory if it doesn't exist
if [ ! -d "$QUANTIZATION_DIR" ]; then
    echo "Creating quantization directory: $QUANTIZATION_DIR"
    if mkdir -p "$QUANTIZATION_DIR"; then
        echo "Successfully created quantization directory"
    else
        echo "Error: Failed to create quantization directory $QUANTIZATION_DIR"
        exit 1
    fi
fi

if [ ! -w "$QUANTIZATION_DIR" ]; then
    echo "Error: Quantization directory $QUANTIZATION_DIR is not writable"
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

# Download quantization scripts
for SCRIPT_NAME in "${QUANTIZATION_SCRIPTS[@]}"; do
    GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/${SCRIPT_NAME}"
    TARGET_PATH="${QUANTIZATION_DIR}/${SCRIPT_NAME}"
    
    echo ""
    echo "Processing quantization script: ${SCRIPT_NAME}"
    
    # Check if file already exists and inform user it will be overwritten
    if [ -f "$TARGET_PATH" ]; then
        echo "File $TARGET_PATH already exists - it will be overwritten"
    fi

    # Download the script using curl with error handling
    echo "Downloading from: $GITHUB_URL"
    if curl -f -L -o "$TARGET_PATH" "$GITHUB_URL"; then
        echo "Successfully downloaded ${SCRIPT_NAME} to $QUANTIZATION_DIR/"
        
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

# Download quantization mapping files
for FILE_NAME in "${QUANTIZATION_FILES[@]}"; do
    GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/${FILE_NAME}"
    TARGET_PATH="${QUANTIZATION_DIR}/${FILE_NAME}"
    
    echo ""
    echo "Processing quantization file: ${FILE_NAME}"
    
    # Check if file already exists and inform user it will be overwritten
    if [ -f "$TARGET_PATH" ]; then
        echo "File $TARGET_PATH already exists - it will be overwritten"
    fi

    # Download the file using curl with error handling
    echo "Downloading from: $GITHUB_URL"
    if curl -f -L -o "$TARGET_PATH" "$GITHUB_URL"; then
        echo "Successfully downloaded ${FILE_NAME} to $QUANTIZATION_DIR/"
    else
        echo "Error: Failed to download ${FILE_NAME} from GitHub"
        echo "Please check your internet connection and try again"
        echo "URL attempted: $GITHUB_URL"
        exit 1
    fi
done

echo ""
echo "All scripts downloaded successfully!"
echo "Installation complete!"
echo ""
echo "Now running reingest-with-endpoints.sh..."
echo "----------------------------------------"
"${INSTALL_DIR}/reingest-with-endpoints.sh" 