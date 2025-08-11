FROM codercom/code-server

# Install system dependencies including compression tools
USER root
RUN apt-get update && \
    apt-get install -y \
        git \
        python3 \
        python3-pip \
        python3-venv \
        pbzip2 \
        pigz \
        zstd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install esrally in root directory
RUN python3 -m venv /root/esrally-env && \
    /root/esrally-env/bin/pip install esrally

# Clone the rally-tracks repository in root directory
RUN git clone https://github.com/elastic/rally-tracks /root/rally-tracks

# Add virtual environment to PATH
ENV PATH="/root/esrally-env/bin:$PATH"

# Set the default command
CMD ["code-server", "workspace", "/root", "--user-data-dir", "/root", "--auth", "none", "--disable-telemetry"]