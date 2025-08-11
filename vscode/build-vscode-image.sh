#!/bin/bash

echo "Building VSCode image..."
# Build the image with platform specification for compatibility
podman build --platform=linux/amd64 -t vscode-serverless-rally:latest .

if [ $? -eq 0 ]; then
    echo "Image built successfully!"
    
    # Comprehensive cleanup of any existing containers and processes on port 8080
    echo "Performing comprehensive cleanup..."
    
    # Stop and remove any containers using port 8080
    echo "Stopping any existing containers on port 8080..."
    podman stop $(podman ps -q --filter "publish=8080") 2>/dev/null || true
    podman rm $(podman ps -aq --filter "publish=8080") 2>/dev/null || true
    
    # Stop and remove any containers with our image name
    echo "Stopping any existing vscode-serverless-rally containers..."
    podman stop $(podman ps -q --filter "ancestor=vscode-serverless-rally:latest") 2>/dev/null || true
    podman rm $(podman ps -aq --filter "ancestor=vscode-serverless-rally:latest") 2>/dev/null || true
    
    # Check what's currently running on port 8080
    echo "Checking what's currently using port 8080..."
    podman ps --filter "publish=8080" 2>/dev/null || true
    
    # Wait a moment for cleanup to complete
    sleep 2
    
    echo "Starting container in background..."
    # Start container in background and get container ID
    CONTAINER_ID=$(podman run -d -p 8080:8080 vscode-serverless-rally:latest)
    
    if [ -n "$CONTAINER_ID" ]; then
        echo "Container started with ID: $CONTAINER_ID"
        echo "Waiting for container to be ready..."
        sleep 5
        
        echo "Verifying all tools are installed correctly..."
        # Verify all tools including esrally from virtual environment in root
        podman exec -it $CONTAINER_ID bash -c "git --version && pbzip2 --version && pigz --version && zstd --version && /root/esrally-env/bin/esrally --version"
        
        if [ $? -eq 0 ]; then
            echo "✅ All tools verified successfully!"
            echo "Stopping container after successful verification..."
            podman stop $CONTAINER_ID
            podman rm $CONTAINER_ID
            echo "✅ Container stopped and removed successfully!"
            echo ""
            echo "To start the container manually, run:"
            echo "podman run -d -p 8080:8080 vscode-serverless-rally:latest"
            echo "To access the container shell, run: podman exec -it <container_id> bash"
        else
            echo "❌ Tool verification failed!"
            podman stop $CONTAINER_ID
            podman rm $CONTAINER_ID
            exit 1
        fi
    else
        echo "❌ Failed to start container!"
        exit 1
    fi
else
    echo "❌ Image build failed!"
    exit 1
fi