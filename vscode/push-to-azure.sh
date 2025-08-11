#!/bin/bash

# Azure Container Registry details
# Replace these with your actual registry details
REGISTRY_NAME="sunmanreg"
REGISTRY_URL="${REGISTRY_NAME}.azurecr.io"
IMAGE_NAME="vscode-serverless-rally"
TAG="latest"

echo "Setting up Azure Container Registry authentication..."

# Check if already logged in to Azure
if ! az account show &>/dev/null; then
    echo "Not logged in to Azure. Please login first..."
    az login --scope https://management.core.windows.net//.default
fi

# Get the registry password/token
echo "Getting registry access token..."
REGISTRY_PASSWORD=$(az acr credential show --name ${REGISTRY_NAME} --query "passwords[0].value" -o tsv)

if [ $? -eq 0 ] && [ -n "$REGISTRY_PASSWORD" ]; then
    echo "✅ Successfully obtained registry credentials!"
    
    # Login to the registry using podman
    echo "Logging in to Azure Container Registry..."
    echo "$REGISTRY_PASSWORD" | podman login ${REGISTRY_URL} --username ${REGISTRY_NAME} --password-stdin
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully logged in to Azure Container Registry!"
        
        echo "Tagging image for Azure Container Registry..."
        # Tag the local image for Azure Container Registry
        podman tag ${IMAGE_NAME}:${TAG} ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}

        if [ $? -eq 0 ]; then
            echo "✅ Image tagged successfully!"
            echo "Pushing image to Azure Container Registry..."
            
            # Push the image to Azure Container Registry
            podman push ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}
            
            if [ $? -eq 0 ]; then
                echo "✅ Image pushed successfully to Azure Container Registry!"
                echo "Image location: ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
                echo ""
                echo "To pull this image on another machine:"
                echo "podman pull ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
                echo ""
                echo "To run this image:"
                echo "podman run -d -p 8080:8080 ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
            else
                echo "❌ Failed to push image to Azure Container Registry!"
                exit 1
            fi
        else
            echo "❌ Failed to tag image!"
            echo "Make sure the local image exists: ${IMAGE_NAME}:${TAG}"
            exit 1
        fi
    else
        echo "❌ Failed to login to Azure Container Registry!"
        exit 1
    fi
else
    echo "❌ Failed to get registry credentials!"
    echo "Make sure you have access to the registry: ${REGISTRY_NAME}"
    exit 1
fi
