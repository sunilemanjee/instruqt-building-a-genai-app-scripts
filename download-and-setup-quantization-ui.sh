#!/bin/bash

# This file is maintained in git at:
# https://github.com/sunilemanjee/instruqt-building-a-genai-app-scripts
#
# Download and run setup-quantization-ui.sh script
set -euo pipefail  # Exit on error, undefined vars, pipe failures


# Configuration
REPO_NAME="quantization-test-ui"
GITHUB_REPO="sunilemanjee/quantization-test-ui"
GITHUB_BRANCH="main"
TARGET_DIR="/root"

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

REPO_PATH="$TARGET_DIR/$REPO_NAME"
BACKUP_PATH="$TARGET_DIR/${REPO_NAME}.backup.$(date +%Y%m%d_%H%M%S)"

# Check network connectivity
log "Checking network connectivity..."
if ! curl -s --max-time 10 --connect-timeout 10 https://raw.githubusercontent.com > /dev/null; then
    error "No internet connectivity. Please check your network connection."
    exit 1
fi

log "Cloning $REPO_NAME repository from GitHub..."

# Create backup if repository exists
if [[ -d "$REPO_PATH" ]]; then
    log "Creating backup of existing repository..."
    cp -r "$REPO_PATH" "$BACKUP_PATH"
    log "Backup created: $BACKUP_PATH"
fi

# Clone the repository
CLONE_URL="https://github.com/$GITHUB_REPO.git"

if git clone "$CLONE_URL" "$REPO_PATH"; then
    log "Repository cloned successfully!"
else
    error "Failed to clone repository from $CLONE_URL"
    if [[ -d "$BACKUP_PATH" ]]; then
        log "Restoring from backup..."
        rm -rf "$REPO_PATH" 2>/dev/null || true
        cp -r "$BACKUP_PATH" "$REPO_PATH"
    fi
    exit 1
fi

# Set executable permissions on setup script
SETUP_SCRIPT="$REPO_PATH/setup_env.sh"
log "Setting executable permissions on setup script..."
if chmod 755 "$SETUP_SCRIPT"; then
    log "Permissions set successfully!"
else
    error "Failed to set permissions on $SETUP_SCRIPT"
    exit 1
fi

# Verify the repository and setup script exist
if [[ -d "$REPO_PATH" && -f "$SETUP_SCRIPT" && -x "$SETUP_SCRIPT" ]]; then
    log "Repository is ready to setup!"
    
    # Basic content validation
    if ! head -n 1 "$SETUP_SCRIPT" | grep -q "^#!/bin/bash\|^#!/bin/sh"; then
        warn "Setup script may not be a valid bash script"
    fi
    
    log "Starting setup for $REPO_NAME..."
    echo "=================================="
    
    # Change to repository directory and run the setup script
    cd "$REPO_PATH"
    if ./setup_env.sh; then
        echo "=================================="
        log "Repository setup completed successfully!"
        log "Repository location: $REPO_PATH"
        log "You can now run the application with: cd $REPO_PATH && python run.py"
    else
        error "Repository setup failed with exit code $?"
        exit 1
    fi
else
    error "Repository or setup script does not exist: $REPO_PATH"
    exit 1
fi 