#!/bin/bash

echo "🔒 Security Update Script for VS Code Serverless Image"
echo "Addressing CVE-2023-45853 (zlib MiniZip vulnerability)"
echo "======================================================"

# Check if we're in the right directory
if [ ! -f "Dockerfile" ]; then
    echo "❌ Error: Dockerfile not found in current directory"
    echo "Please run this script from the vscode directory"
    exit 1
fi

echo ""
echo "📋 Current Security Status:"
echo "CVE-2023-45853: zlib MiniZip integer overflow vulnerability"
echo "Affects: zipOpenNewFileInZip4_64 function"
echo "Risk: Heap-based buffer overflow via long filenames/comments"
echo ""

echo "🛠️  Mitigation Strategies:"
echo "1. Update base image to latest version"
echo "2. Update system packages (especially zlib)"
echo "3. Add security hardening measures"
echo "4. Consider alternative compression libraries"
echo ""

echo "📝 Recommended Actions:"
echo "1. Rebuild image with updated base image"
echo "2. Add security package updates to Dockerfile"
echo "3. Consider using alternative compression tools"
echo "4. Implement input validation for zip operations"
echo ""

echo "🔧 Quick Fix - Update Dockerfile with security patches:"
echo "Add these lines to your Dockerfile after the FROM statement:"
echo ""
echo "  # Security updates for CVE-2023-45853"
echo "  RUN apt-get update && \\"
echo "      apt-get upgrade -y zlib1g && \\"
echo "      apt-get clean && \\"
echo "      rm -rf /var/lib/apt/lists/*"
echo ""

echo "🚀 To rebuild with security fixes:"
echo "1. Update your Dockerfile with the security patches above"
echo "2. Run: ./build-vscode-image.sh"
echo "3. Run: ./push-to-gcp.sh"
echo ""

echo "⚠️  Additional Security Recommendations:"
echo "- Consider using p7zip instead of zip for compression"
echo "- Implement file size limits for zip operations"
echo "- Add input validation for zip filenames"
echo "- Use container security scanning tools regularly"
echo ""

echo "📊 To check for other vulnerabilities:"
echo "Run: podman scan localhost/vscode-serverless-rally:latest"
echo ""

read -p "Would you like me to create an updated Dockerfile with security patches? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Creating updated Dockerfile with security patches..."
    cp Dockerfile Dockerfile.backup
    echo "Backup created: Dockerfile.backup"
    
    # Create updated Dockerfile with security patches
    cat > Dockerfile.security << 'EOF'
FROM codercom/code-server:latest

# Install system dependencies including compression tools
USER root

# Security updates for CVE-2023-45853 and other vulnerabilities
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        git \
        python3 \
        python3-pip \
        python3-venv \
        pbzip2 \
        pigz \
        zstd \
        p7zip-full \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Security hardening: Update zlib specifically
RUN apt-get update && \
    apt-get install -y --only-upgrade zlib1g && \
    apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch to coder user and install esrally in their home directory
USER coder
RUN python3 -m venv /home/coder/esrally-env && \
    /home/coder/esrally-env/bin/pip install esrally

# Clone the rally-tracks repository in coder's home directory
RUN git clone https://github.com/elastic/rally-tracks /home/coder/rally-tracks

# Add virtual environment to PATH
ENV PATH="/home/coder/esrally-env/bin:$PATH"

# Set the default command
CMD ["code-server", "workspace", "/home/coder", "--user-data-dir", "/home/coder", "--auth", "none", "--disable-telemetry"]
EOF

    echo "✅ Created Dockerfile.security with security patches"
    echo "To use the secure version:"
    echo "  mv Dockerfile.security Dockerfile"
    echo "  ./build-vscode-image.sh"
    echo "  ./push-to-gcp.sh"
else
    echo "No changes made. You can manually update the Dockerfile as needed."
fi

echo ""
echo "🔍 To verify the fix:"
echo "1. Rebuild the image"
echo "2. Run: podman scan localhost/vscode-serverless-rally:latest"
echo "3. Check if CVE-2023-45853 is resolved"
