#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#
# Download and run setup-quantization-ui.sh script
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/setup-quantization-ui.sh"
TARGET_DIR="/root"
SCRIPT_NAME="setup-quantization-ui.sh"
SCRIPT_PATH="$TARGET_DIR/$SCRIPT_NAME"

# Quantization configuration
QUANTIZATION_SCRIPTS=("create_indices_and_reindex.sh")
QUANTIZATION_FILES=("index-mapping-int4flat.json" "index-mapping-int8flat.json" "index-mapping-bbqflat.json")
QUANTIZATION_DIR="${TARGET_DIR}/quantization-indices"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Validate target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    error "Target directory does not exist: $TARGET_DIR"
    exit 1
fi

if [[ ! -w "$TARGET_DIR" ]]; then
    error "No write permission for target directory: $TARGET_DIR"
    exit 1
fi

# Check network connectivity
log "Checking network connectivity..."
if ! curl -s --max-time 10 --connect-timeout 10 https://raw.githubusercontent.com > /dev/null; then
    error "No internet connectivity. Please check your network connection."
    exit 1
fi

# Create quantization directory if it doesn't exist
log "Setting up quantization directory..."
if [ ! -d "$QUANTIZATION_DIR" ]; then
    log "Creating quantization directory: $QUANTIZATION_DIR"
    if mkdir -p "$QUANTIZATION_DIR"; then
        log "Successfully created quantization directory"
    else
        error "Failed to create quantization directory $QUANTIZATION_DIR"
        exit 1
    fi
fi

if [ ! -w "$QUANTIZATION_DIR" ]; then
    error "Quantization directory $QUANTIZATION_DIR is not writable"
    exit 1
fi

# Download quantization scripts
log "Downloading quantization scripts..."
for SCRIPT_NAME in "${QUANTIZATION_SCRIPTS[@]}"; do
    GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/${SCRIPT_NAME}"
    TARGET_PATH="${QUANTIZATION_DIR}/${SCRIPT_NAME}"
    
    log "Processing quantization script: ${SCRIPT_NAME}"
    
    # Check if file already exists and inform user it will be overwritten
    if [ -f "$TARGET_PATH" ]; then
        warn "File $TARGET_PATH already exists - it will be overwritten"
    fi

    # Download the script using curl with error handling
    if curl -f -L -o "$TARGET_PATH" "$GITHUB_URL"; then
        log "Successfully downloaded ${SCRIPT_NAME} to $QUANTIZATION_DIR/"
        
        # Make the script executable
        if chmod 755 "$TARGET_PATH"; then
            log "Successfully set executable permissions (755) on $TARGET_PATH"
        else
            error "Failed to set executable permissions on $TARGET_PATH"
            exit 1
        fi
    else
        error "Failed to download ${SCRIPT_NAME} from GitHub"
        error "Please check your internet connection and try again"
        error "URL attempted: $GITHUB_URL"
        exit 1
    fi
done

# Download quantization mapping files
log "Downloading quantization mapping files..."
for FILE_NAME in "${QUANTIZATION_FILES[@]}"; do
    GITHUB_URL="https://raw.githubusercontent.com/sunilemanjee/instruqt-building-a-genai-app-scripts/refs/heads/main/${FILE_NAME}"
    TARGET_PATH="${QUANTIZATION_DIR}/${FILE_NAME}"
    
    log "Processing quantization file: ${FILE_NAME}"
    
    # Check if file already exists and inform user it will be overwritten
    if [ -f "$TARGET_PATH" ]; then
        warn "File $TARGET_PATH already exists - it will be overwritten"
    fi

    # Download the file using curl with error handling
    if curl -f -L -o "$TARGET_PATH" "$GITHUB_URL"; then
        log "Successfully downloaded ${FILE_NAME} to $QUANTIZATION_DIR/"
    else
        error "Failed to download ${FILE_NAME} from GitHub"
        error "Please check your internet connection and try again"
        error "URL attempted: $GITHUB_URL"
        exit 1
    fi
done

log "Quantization setup completed successfully!"

# Download the setup script
log "Downloading setup script from $SCRIPT_URL..."
if curl -s -o "$SCRIPT_PATH" "$SCRIPT_URL"; then
    log "Setup script downloaded successfully!"
else
    error "Failed to download setup script from $SCRIPT_URL"
    exit 1
fi

# Set executable permissions on the downloaded script
log "Setting executable permissions on setup script..."
if chmod 755 "$SCRIPT_PATH"; then
    log "Permissions set successfully!"
else
    error "Failed to set permissions on $SCRIPT_PATH"
    exit 1
fi

# Verify the script exists and is executable
if [[ -f "$SCRIPT_PATH" && -x "$SCRIPT_PATH" ]]; then
    log "Setup script is ready to run!"
    
    # Basic content validation
    if ! head -n 1 "$SCRIPT_PATH" | grep -q "^#!/bin/bash\|^#!/bin/sh"; then
        warn "Setup script may not be a valid bash script"
    fi
    
    log "Starting setup script..."
    echo "=================================="
    
    # Run the setup script
    if bash "$SCRIPT_PATH"; then
        echo "=================================="
        log "Setup script completed successfully!"
        log "Script location: $SCRIPT_PATH"
    else
        error "Setup script failed with exit code $?"
        exit 1
    fi
else
    error "Setup script does not exist or is not executable: $SCRIPT_PATH"
    exit 1
fi 