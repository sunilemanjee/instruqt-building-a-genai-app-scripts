#!/bin/bash

# Script to push index.html to Azure Storage Container
# Usage: ./push-to-azure-storage.sh

set -e  # Exit on any error

# Configuration - Set these environment variables or modify the defaults
STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT:-your-storage-account}"
CONTAINER_NAME="${AZURE_CONTAINER_NAME:-web}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-your-resource-group}"
LOCATION="${AZURE_LOCATION:-eastus}"
FILE_PATH="${FILE_PATH:-index.html}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Azure CLI is installed
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first:"
        echo "  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI is installed"
}

# Function to check if user is logged in to Azure
check_azure_login() {
    if ! az account show &> /dev/null; then
        print_error "You are not logged in to Azure. Please run: az login"
        exit 1
    fi
    print_success "Logged in to Azure"
}

# Function to check if storage account exists, create if not
ensure_storage_account() {
    print_status "Checking if storage account '$STORAGE_ACCOUNT_NAME' exists..."
    
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        print_success "Storage account '$STORAGE_ACCOUNT_NAME' exists"
    else
        print_warning "Storage account '$STORAGE_ACCOUNT_NAME' does not exist. Creating..."
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2
        print_success "Storage account '$STORAGE_ACCOUNT_NAME' created"
    fi
}

# Function to check if container exists, create if not
ensure_container() {
    print_status "Checking if container '$CONTAINER_NAME' exists..."
    
    if az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT_NAME" &> /dev/null; then
        print_success "Container '$CONTAINER_NAME' exists"
    else
        print_warning "Container '$CONTAINER_NAME' does not exist. Creating..."
        az storage container create \
            --name "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --public-access blob
        print_success "Container '$CONTAINER_NAME' created with public blob access"
    fi
}

# Function to upload the file
upload_file() {
    print_status "Uploading '$FILE_PATH' to container '$CONTAINER_NAME'..."
    
    if [ ! -f "$FILE_PATH" ]; then
        print_error "File '$FILE_PATH' does not exist"
        exit 1
    fi
    
    # Upload the file
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$CONTAINER_NAME" \
        --name "$FILE_PATH" \
        --file "$FILE_PATH" \
        --overwrite
    
    print_success "File '$FILE_PATH' uploaded successfully"
}

# Function to get the public URL
get_public_url() {
    local url=$(az storage blob url \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$CONTAINER_NAME" \
        --name "$FILE_PATH" \
        --output tsv)
    
    print_success "File is now available at: $url"
}

# Function to display configuration
show_config() {
    echo
    print_status "Configuration:"
    echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "  Container: $CONTAINER_NAME"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  File: $FILE_PATH"
    echo
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Environment Variables (optional):"
    echo "  AZURE_STORAGE_ACCOUNT    - Azure Storage Account name (default: your-storage-account)"
    echo "  AZURE_CONTAINER_NAME     - Container name (default: web)"
    echo "  AZURE_RESOURCE_GROUP     - Resource Group name (default: your-resource-group)"
    echo "  AZURE_LOCATION          - Azure location (default: eastus)"
    echo "  FILE_PATH               - File to upload (default: index.html)"
    echo
    echo "Example:"
    echo "  export AZURE_STORAGE_ACCOUNT=mywebappstorage"
    echo "  export AZURE_CONTAINER_NAME=static-website"
    echo "  export AZURE_RESOURCE_GROUP=my-resource-group"
    echo "  $0"
    echo
}

# Main execution
main() {
    echo "=========================================="
    echo "  Azure Storage Upload Script"
    echo "=========================================="
    
    # Check for help flag
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    show_config
    
    # Validate configuration
    if [[ "$STORAGE_ACCOUNT_NAME" == "your-storage-account" ]]; then
        print_error "Please set AZURE_STORAGE_ACCOUNT environment variable or modify the script"
        show_usage
        exit 1
    fi
    
    if [[ "$RESOURCE_GROUP" == "your-resource-group" ]]; then
        print_error "Please set AZURE_RESOURCE_GROUP environment variable or modify the script"
        show_usage
        exit 1
    fi
    
    # Execute the workflow
    check_azure_cli
    check_azure_login
    ensure_storage_account
    ensure_container
    upload_file
    get_public_url
    
    echo
    print_success "Upload completed successfully!"
    echo "=========================================="
}

# Run main function
main "$@"
