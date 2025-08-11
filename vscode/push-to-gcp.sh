#!/bin/bash

# GCP Artifact Registry details
# Replace these with your actual registry details
PROJECT_ID="elastic-sa"
REGION="us-central1"
REPOSITORY="instruqt"
REGISTRY_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"
IMAGE_NAME="vscode-serverless-rally"
TAG="2025-08-10"

echo "Setting up GCP Artifact Registry authentication..."

# Check if already logged in to GCP
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "Not logged in to GCP. Please login first..."
    gcloud auth login
fi

# Check if the correct project is set
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
    echo "Setting project to ${PROJECT_ID}..."
    gcloud config set project ${PROJECT_ID}
fi

# Configure Docker to use gcloud as a credential helper for the specific region
echo "Configuring Docker authentication for GCP Artifact Registry..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

if [ $? -eq 0 ]; then
    echo "✅ Successfully configured Docker authentication!"
    
    echo "Tagging local image with date tag..."
    # First tag the local image with the date tag
    podman tag localhost/${IMAGE_NAME}:latest ${IMAGE_NAME}:${TAG}
    
    echo "Tagging image for GCP Artifact Registry..."
    # Tag the local image for GCP Artifact Registry
    podman tag ${IMAGE_NAME}:${TAG} ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}

    if [ $? -eq 0 ]; then
        echo "✅ Image tagged successfully!"
        echo "Pushing image to GCP Artifact Registry..."
        
        # Push the image to GCP Artifact Registry
        podman push ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}
        
        if [ $? -eq 0 ]; then
            echo "✅ Image pushed successfully to GCP Artifact Registry!"
            echo "Image location: ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
            echo ""
            echo "To pull this image on another machine:"
            echo "gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet"
            echo "podman pull ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
            echo ""
            echo "To run this image:"
            echo "podman run -d -p 8080:8080 ${REGISTRY_URL}/${IMAGE_NAME}:${TAG}"
        else
            echo "❌ Failed to push image to GCP Artifact Registry!"
            exit 1
        fi
    else
        echo "❌ Failed to tag image!"
        echo "Make sure the local image exists: ${IMAGE_NAME}:${TAG}"
        exit 1
    fi
else
    echo "❌ Failed to configure Docker authentication for GCP Artifact Registry!"
    echo "Make sure you have the necessary permissions for project: ${PROJECT_ID}"
    exit 1
fi
