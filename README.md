# Instruqt Building a GenAI App Scripts

This repository contains scripts and tools for setting up and managing a GenAI application environment with Elasticsearch, Kibana, and Model Context Protocol (MCP) components.

## Overview

This project provides automation scripts for:
- Setting up Elasticsearch MCP server
- Configuring Kibana Relevance Studio
- Managing API keys and authentication
- Data validation and checking
- Server lifecycle management

## Scripts

### Setup and Installation
- `clone_and_setup_elastic_mcp.sh` - Clones and sets up the Elasticsearch MCP repository
- `download-mcp-repo.sh` - Downloads the MCP repository
- `download-kibana-rel-studio.sh` - Downloads Kibana Relevance Studio
- `create-api-key.sh` - Creates and manages API keys for authentication

### Data Management
- `2-View Hotels Data.sh` - Script to view and manage hotels data
- `2-View Hotels Data Check Script.sh` - Validation script for hotels data

### Server Management
- `start-rest-server.sh` - Starts the REST server
- `stop_servers.sh` - Stops running servers
- `kibana-rel-studio.sh` - Manages Kibana Relevance Studio

### Configuration
- `lifecycle-es3-api-v1-setup` - Setup script for ES3 API v1 lifecycle management

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd instruqt-building-a-genai-app-scripts
   ```

2. **Set up Elasticsearch MCP:**
   ```bash
   chmod +x clone_and_setup_elastic_mcp.sh
   ./clone_and_setup_elastic_mcp.sh
   ```

3. **Create API keys:**
   ```bash
   chmod +x create-api-key.sh
   ./create-api-key.sh
   ```

4. **Start the REST server:**
   ```bash
   chmod +x start-rest-server.sh
   ./start-rest-server.sh
   ```

## Environment Variables

The scripts use several environment variables:
- `REGIONS` - AWS region (no longer needed - scripts automatically detect the region from JSON)
- `KIBANA_URL` - Kibana server URL
- `ES_API_KEY` - Elasticsearch API key

## Data Validation

Use the data check scripts to validate your setup:
```bash
chmod +x "2-View Hotels Data Check Script.sh"
./2-View Hotels Data Check Script.sh
```

## Stopping Services

To stop all running services:
```bash
chmod +x stop_servers.sh
./stop_servers.sh
```

## Requirements

- Python 3
- Bash shell
- Git
- Access to Elasticsearch and Kibana instances
- Valid API credentials

## Troubleshooting

- Ensure all scripts have execute permissions (`chmod +x script.sh`)
- Check that `/tmp/project_results.json` exists and contains valid credentials
- Verify network connectivity to Elasticsearch and Kibana instances
- Review script logs for detailed error messages

## Contributing

When adding new scripts:
1. Make them executable (`chmod +x`)
2. Add proper error handling
3. Update this README with documentation
4. Test thoroughly before committing 