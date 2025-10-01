import os
import sys
import json
import time
import argparse
import requests
from typing import Dict, List, Optional, Union, Any


class VaultClient:
    """Client for interacting with HashiCorp Vault"""
    
    def __init__(self, vault_addr: str, vault_token: str, vault_namespace: Optional[str] = None):
        """
        Initialize the Vault client
        
        Args:
            vault_addr: Vault server address
            vault_token: Vault authentication token
            vault_namespace: Optional Vault namespace (for Enterprise Vault)
        """
        if not VAULT_AVAILABLE:
            raise ImportError("hvac module not installed. Install it with: pip install hvac")
            
        self.vault_addr = vault_addr
        self.vault_token = vault_token
        self.vault_namespace = vault_namespace
        
        # Initialize the hvac client
        self.client = hvac.Client(
            url=vault_addr,
            token=vault_token,
            namespace=vault_namespace
        )
        
        # Verify Vault connection
        if not self.client.is_authenticated():
            raise Exception("Failed to authenticate with Vault")
    
    def store_project_info(self, path_prefix: str, project_name: str, project_info: Dict[str, Any]) -> bool:
        """
        Store project information in Vault using v1 API
        
        Args:
            path_prefix: Prefix for the Vault path
            project_name: Name of the project
            project_info: Project information to store
            
        Returns:
            True if successful, False otherwise
        """
        try:
            path = f"{path_prefix}/{project_name}/info"
            self.client.secrets.kv.v1.create_or_update_secret(
                path=path,
                secret=project_info
            )
            return True
        except Exception as e:
            print(f"Error storing project info in Vault: {str(e)}")
            return False
    
    def get_project_info(self, path_prefix: str, project_name: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve project information from Vault using v1 API
        
        Args:
            path_prefix: Prefix for the Vault path
            project_name: Name of the project
            
        Returns:
            Project information or None if not found or error
        """
        try:
            path = f"{path_prefix}/{project_name}/info"
            response = self.client.secrets.kv.v1.read_secret(path=path)
            return response['data'] if response and 'data' in response else None
        except Exception as e:
            print(f"Error retrieving project info from Vault: {str(e)}")
            return None#!/usr/bin/env python3
"""
Elastic Cloud Serverless API Project Manager

This script provides functionality to manage Elastic Cloud Serverless projects via the API:
- Create new projects (elasticsearch, observability, security)
- Delete existing projects
- Update project configurations
- Reset project credentials

The script is designed to be containerized and run in a Kubernetes environment, 
accepting configuration via environment variables, with HashiCorp Vault integration
for securely storing and retrieving project information.

Usage:
    python elastic_cloud_project_manager.py [--operation] [additional arguments]

Environment Variables:
    ELASTIC_API_KEY: API key for authentication
    ELASTIC_PROJECT_TYPE: Type of project (elasticsearch, observability, security)
    ELASTIC_REGIONS: Comma-separated list of regions to create projects in
    ELASTIC_OPERATION: Operation to perform (create, delete, update)
    ELASTIC_PROJECT_NAME: Name of the project (for creation)
    ELASTIC_PROJECT_ID: ID of the project (for deletion/update)
    
    # Vault integration
    VAULT_ADDR: HashiCorp Vault address (e.g., https://vault.example.com:8200)
    VAULT_TOKEN: Token for Vault authentication
    VAULT_NAMESPACE: Optional Vault namespace for enterprise Vault
    VAULT_PATH_PREFIX: Prefix for Vault paths (default: secret/k8s/eden/staging-3)
"""

# Try to import hvac - if not available, Vault integration will be disabled
try:
    import hvac
    VAULT_AVAILABLE = True
except ImportError:
    VAULT_AVAILABLE = False
    print("Warning: hvac package not installed. Vault integration will be disabled.")
    print("To enable Vault integration, install hvac: pip install hvac")


# Valid values for API parameters based on Elastic Cloud Serverless API documentation
VALID_PROJECT_TYPES = ['elasticsearch', 'observability', 'security']
VALID_OPTIMIZED_FOR = ['general_purpose', 'vector']


def validate_project_type(project_type: str) -> bool:
    """
    Validate project type parameter
    
    Args:
        project_type: The project type to validate
        
    Returns:
        True if valid, False otherwise
    """
    if project_type not in VALID_PROJECT_TYPES:
        print(f"Error: Invalid project type '{project_type}'. Valid values are: {', '.join(VALID_PROJECT_TYPES)}")
        return False
    return True


def validate_optimized_for(optimized_for: str, project_type: str) -> bool:
    """
    Validate optimized_for parameter
    
    Args:
        optimized_for: The optimization type to validate
        project_type: The project type (optimized_for only applies to elasticsearch projects)
        
    Returns:
        True if valid, False otherwise
    """
    if optimized_for is None:
        return True  # Optional parameter
        
    if project_type != 'elasticsearch':
        print(f"Warning: optimized_for parameter is only applicable to 'elasticsearch' projects, not '{project_type}' projects. Ignoring this parameter.")
        return True
        
    if optimized_for not in VALID_OPTIMIZED_FOR:
        print(f"Error: Invalid optimized_for value '{optimized_for}'. Valid values are: {', '.join(VALID_OPTIMIZED_FOR)}")
        return False
    return True



class ElasticCloudClient:
    """Client for interacting with the Elastic Cloud Serverless API"""
    
    BASE_URL = "https://api.elastic-cloud.com/api/v1/serverless"
    
    def __init__(self, api_key: str):
        """
        Initialize the Elastic Cloud client
        
        Args:
            api_key: API key for authentication
        """
        self.api_key = api_key
        self.headers = {
            "Authorization": f"ApiKey {api_key}",
            "Content-Type": "application/json"
        }
    
    def create_project(self, 
                       project_type: str, 
                       name: str, 
                       region_id: str, 
                       alias: Optional[str] = None,
                       optimized_for: Optional[str] = None) -> Dict[str, Any]:
        """
        Create a new project
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            name: Project name
            region_id: Region ID (e.g., aws-us-east-1)
            alias: Custom domain label (optional)
            optimized_for: Optimization type (e.g., general_purpose for elasticsearch)
            
        Returns:
            Response JSON from the API
        """
        url = f"{self.BASE_URL}/projects/{project_type}"
        
        payload = {
            "name": name,
            "region_id": region_id
        }
        
        if alias:
            payload["alias"] = alias
            
        if optimized_for and project_type == "elasticsearch":
            payload["optimized_for"] = optimized_for
        
        response = requests.post(url, headers=self.headers, json=payload)
        
        if response.status_code == 200 or response.status_code == 201:
            return response.json()
        else:
            print(f"Error creating project: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to create project: {response.text}")
    
    def delete_project(self, project_type: str, project_id: str) -> bool:
        """
        Delete an existing project
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            project_id: Project ID to delete
            
        Returns:
            True if successful, raises an exception otherwise
        """
        url = f"{self.BASE_URL}/projects/{project_type}/{project_id}"
        
        response = requests.delete(url, headers=self.headers)
        
        if response.status_code == 200 or response.status_code == 204:
            return True
        else:
            print(f"Error deleting project: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to delete project: {response.text}")
    
    def update_project(self, 
                       project_type: str, 
                       project_id: str, 
                       name: Optional[str] = None,
                       alias: Optional[str] = None,
                       if_match: Optional[str] = None) -> Dict[str, Any]:
        """
        Update an existing project
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            project_id: Project ID to update
            name: New project name (optional)
            alias: New custom domain label (optional)
            if_match: ETag value from a previous GET request (for concurrency control)
            
        Returns:
            Response JSON from the API
        """
        url = f"{self.BASE_URL}/projects/{project_type}/{project_id}"
        
        payload = {}
        if name:
            payload["name"] = name
        if alias:
            payload["alias"] = alias
            
        headers = self.headers.copy()
        if if_match:
            headers["If-Match"] = if_match
        
        response = requests.patch(url, headers=headers, json=payload)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Error updating project: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to update project: {response.text}")
    
    def reset_credentials(self, project_type: str, project_id: str) -> Dict[str, Any]:
        """
        Reset project credentials
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            project_id: Project ID
            
        Returns:
            Response JSON from the API with new credentials
        """
        url = f"{self.BASE_URL}/projects/{project_type}/{project_id}/_reset-credentials"
        
        response = requests.post(url, headers=self.headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Error resetting credentials: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to reset credentials: {response.text}")
    
    def get_project(self, project_type: str, project_id: str) -> Dict[str, Any]:
        """
        Get project details
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            project_id: Project ID
            
        Returns:
            Response JSON from the API with project details
        """
        url = f"{self.BASE_URL}/projects/{project_type}/{project_id}"
        
        response = requests.get(url, headers=self.headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Error getting project: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to get project: {response.text}")
    
    def get_project_status(self, project_type: str, project_id: str) -> Dict[str, Any]:
        """
        Get project status
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            project_id: Project ID
            
        Returns:
            Response JSON from the API with project status
        """
        url = f"{self.BASE_URL}/projects/{project_type}/{project_id}/status"
        
        response = requests.get(url, headers=self.headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Error getting project status: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to get project status: {response.text}")
    
    def list_projects(self, project_type: str) -> List[Dict[str, Any]]:
        """
        List all projects of a specific type
        
        Args:
            project_type: Type of project (elasticsearch, observability, security)
            
        Returns:
            List of projects
        """
        url = f"{self.BASE_URL}/projects/{project_type}"
        
        response = requests.get(url, headers=self.headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Error listing projects: {response.status_code}")
            print(response.text)
            raise Exception(f"Failed to list projects: {response.text}")


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Elastic Cloud Serverless API Project Manager')
    
    parser.add_argument('--operation', choices=['create', 'delete', 'update', 'reset-credentials', 'list'],
                        help='Operation to perform')
    
    parser.add_argument('--project-type', choices=VALID_PROJECT_TYPES,
                        help=f'Type of project. Valid values: {", ".join(VALID_PROJECT_TYPES)}')
    
    parser.add_argument('--regions', help='Comma-separated list of regions')
    
    parser.add_argument('--project-name', help='Name of the project (for creation)')
    
    parser.add_argument('--project-id', help='ID of the project (for deletion/update)')
    
    parser.add_argument('--api-key', help='API key for authentication')
    
    parser.add_argument('--alias', help='Custom domain label (optional)')
    
    parser.add_argument('--optimized-for', choices=VALID_OPTIMIZED_FOR,
                        help=f'Optimization type (for elasticsearch projects only). Valid values: {", ".join(VALID_OPTIMIZED_FOR)}')
    
    parser.add_argument('--wait-for-ready', action='store_true', 
                        help='Wait for the project to be fully initialized')
    
    # Vault integration parameters
    parser.add_argument('--vault-addr', help='HashiCorp Vault address')
    
    parser.add_argument('--vault-token', help='Token for Vault authentication')
    
    parser.add_argument('--vault-namespace', help='Vault namespace (for Enterprise Vault)')
    
    parser.add_argument('--vault-path-prefix', default='secret/k8s/eden/staging-3',
                        help='Prefix for Vault paths')
    
    return parser.parse_args()


def main():
    """Main function"""
    # Parse arguments from command line
    args = parse_args()
    
    # Environment variables have precedence over command line arguments
    api_key = os.environ.get('ELASTIC_API_KEY') or args.api_key
    project_type = os.environ.get('ELASTIC_PROJECT_TYPE') or args.project_type
    regions_str = os.environ.get('ELASTIC_REGIONS') or args.regions
    operation = os.environ.get('ELASTIC_OPERATION') or args.operation
    project_name = os.environ.get('ELASTIC_PROJECT_NAME') or args.project_name
    project_id = os.environ.get('ELASTIC_PROJECT_ID') or args.project_id
    alias = os.environ.get('ELASTIC_PROJECT_ALIAS') or args.alias
    optimized_for = os.environ.get('ELASTIC_OPTIMIZED_FOR') or args.optimized_for
    wait_for_ready = os.environ.get('ELASTIC_WAIT_FOR_READY', 'false').lower() == 'true' or args.wait_for_ready
    
    # Vault configuration
    vault_addr = os.environ.get('VAULT_ADDR') or args.vault_addr
    vault_token = os.environ.get('VAULT_TOKEN') or args.vault_token
    vault_namespace = os.environ.get('VAULT_NAMESPACE') or args.vault_namespace
    vault_path_prefix = os.environ.get('VAULT_PATH_PREFIX', 'secret/k8s/eden/staging-3') or args.vault_path_prefix
    
    # Check if Vault integration is available and configured
    use_vault = VAULT_AVAILABLE and vault_addr and vault_token
    
    # Validate parameters
    if not api_key:
        print("Error: API key is required")
        sys.exit(1)
    
    if not operation:
        print("Error: Operation is required")
        sys.exit(1)
    
    if not project_type:
        print("Error: Project type is required")
        sys.exit(1)
    
    # Validate project_type
    if not validate_project_type(project_type):
        sys.exit(1)
    
    # Validate optimized_for (only for elasticsearch projects)
    if not validate_optimized_for(optimized_for, project_type):
        sys.exit(1)
    
    if operation == 'create' and (not project_name or not regions_str):
        print("Error: Project name and regions are required for creation")
        sys.exit(1)
    
    if operation in ['delete', 'update', 'reset-credentials'] and not project_name and not project_id:
        print(f"Error: Either Project name or Project ID is required for {operation} operation")
        sys.exit(1)
    
    # Initialize Elastic client
    elastic_client = ElasticCloudClient(api_key)
    
    # Initialize Vault client if Vault is configured
    vault_client = None
    if use_vault:
        try:
            print(f"Initializing Vault client with address: {vault_addr}")
            vault_client = VaultClient(vault_addr, vault_token, vault_namespace)
            print("Successfully connected to Vault")
        except Exception as e:
            print(f"Warning: Failed to initialize Vault client: {str(e)}")
            print("Continuing without Vault integration...")
            use_vault = False
    
    # Parse regions
    regions = regions_str.split(',') if regions_str else []
    
    # Perform the requested operation
    try:
        if operation == 'create':
            if not regions:
                print("Error: At least one region is required for creation")
                sys.exit(1)
                
            # Create a project in each specified region
            results = {}
            for region in regions:
                print(f"Creating {project_type} project '{project_name}' in region {region}...")
                result = elastic_client.create_project(
                    project_type=project_type,
                    name=project_name,
                    region_id=region,
                    alias=alias,
                    optimized_for=optimized_for
                )
                
                project_id = result.get('id')
                if project_id and wait_for_ready:
                    print(f"Waiting for project {project_id} to be fully initialized...")
                    while True:
                        status = elastic_client.get_project_status(project_type, project_id)
                        if status.get('phase') == 'initialized':
                            print(f"Project {project_id} is now ready!")
                            break
                        print(f"Project status: {status.get('phase', 'unknown')}. Waiting...")
                        time.sleep(5)
                
                results[region] = result
                print(f"Successfully created project in {region}. Project ID: {project_id}")
                
                # Print out important details
                if 'endpoints' in result:
                    print("\nEndpoints:")
                    for service, url in result['endpoints'].items():
                        print(f"  {service}: {url}")
                
                if 'credentials' in result:
                    print("\nCredentials:")
                    print(f"  Username: {result['credentials'].get('username', 'N/A')}")
                    print(f"  Password: {result['credentials'].get('password', 'N/A')}")
                
                print(f"\nCloud ID: {result.get('cloud_id', 'N/A')}")
                print("=" * 80)
                
                # Store project information in Vault
                if vault_client:
                    vault_data = {
                        'id': result.get('id'),
                        'name': result.get('name'),
                        'alias': result.get('alias'),
                        'region_id': result.get('region_id'),
                        'CLOUD_ID': result.get('cloud_id'),
                        'type': result.get('type'),
                        'project_type': project_type
                    }
                    
                    # Add endpoints if available - break them down into individual URLs
                    if 'endpoints' in result:
                        endpoints = result['endpoints']
                        if 'elasticsearch' in endpoints:
                            vault_data['ELASTICSEARCH_URL'] = endpoints['elasticsearch']
                        if 'kibana' in endpoints:
                            vault_data['KIBANA_URL'] = endpoints['kibana']
                    
                    # Add credentials if available - break them down and create CLOUD_AUTH
                    if 'credentials' in result:
                        credentials = result['credentials']
                        username = credentials.get('username')
                        password = credentials.get('password')
                        
                        if username:
                            vault_data['ELASTICSEARCH_USERNAME'] = username
                        if password:
                            vault_data['ELASTICSEARCH_PASSWORD'] = password
                        if username and password:
                            vault_data['CLOUD_AUTH'] = f"{username}:{password}"
                    
                    # Store in Vault
                    success = vault_client.store_project_info(
                        path_prefix=vault_path_prefix,
                        project_name=project_name,
                        project_info=vault_data
                    )
                    
                    if success:
                        print(f"Successfully stored project information in Vault at {vault_path_prefix}/{project_name}/info")
                    else:
                        print("Failed to store project information in Vault")
            
            # Write results to a file that could be used by another process
            with open('/tmp/project_results.json', 'w') as f:
                json.dump(results, f, indent=2)
            
        elif operation == 'delete':
            # If project_id is not provided but project_name is, try to get project_id from Vault
            if not project_id and project_name and vault_client:
                print(f"Project ID not provided, attempting to retrieve from Vault...")
                vault_info = vault_client.get_project_info(vault_path_prefix, project_name)
                
                if vault_info and 'id' in vault_info:
                    project_id = vault_info['id']
                    print(f"Found project ID in Vault: {project_id}")
                    
                    # Also get project_type from Vault if not provided
                    if (not project_type or project_type == "elasticsearch") and 'project_type' in vault_info:
                        project_type = vault_info['project_type']
                        print(f"Using project type from Vault: {project_type}")
                else:
                    print("Could not find project information in Vault")
            
            if not project_id:
                print("Error: Project ID is required for deletion")
                sys.exit(1)
                
            print(f"Deleting {project_type} project {project_id}...")
            result = elastic_client.delete_project(project_type, project_id)
            if result:
                print(f"Successfully deleted project {project_id}")
            
        elif operation == 'update':
            # If project_id is not provided but project_name is, try to get project_id from Vault
            if not project_id and project_name and vault_client:
                print(f"Project ID not provided, attempting to retrieve from Vault...")
                vault_info = vault_client.get_project_info(vault_path_prefix, project_name)
                
                if vault_info and 'id' in vault_info:
                    project_id = vault_info['id']
                    print(f"Found project ID in Vault: {project_id}")
                    
                    # Also get project_type from Vault if not provided
                    if (not project_type or project_type == "elasticsearch") and 'project_type' in vault_info:
                        project_type = vault_info['project_type']
                        print(f"Using project type from Vault: {project_type}")
                else:
                    print("Could not find project information in Vault")
            
            if not project_id:
                print("Error: Project ID is required for update")
                sys.exit(1)
                
            print(f"Updating {project_type} project {project_id}...")
            result = elastic_client.update_project(
                project_type=project_type,
                project_id=project_id,
                name=project_name,
                alias=alias
            )
            print(f"Successfully updated project {project_id}")
            print(json.dumps(result, indent=2))
            
            # Update Vault information if configured
            if vault_client and project_name:
                # First retrieve existing information
                existing_info = vault_client.get_project_info(vault_path_prefix, project_name)
                
                if existing_info:
                    # Update with new information
                    existing_info.update({
                        'name': result.get('name', existing_info.get('name')),
                        'alias': result.get('alias', existing_info.get('alias'))
                    })
                    
                    # Store updated information
                    success = vault_client.store_project_info(
                        path_prefix=vault_path_prefix,
                        project_name=project_name,
                        project_info=existing_info
                    )
                    
                    if success:
                        print(f"Successfully updated project information in Vault")
                    else:
                        print("Failed to update project information in Vault")
                else:
                    print(f"No existing project information found in Vault for {project_name}")
            
        elif operation == 'reset-credentials':
            # If project_id is not provided but project_name is, try to get project_id from Vault
            if not project_id and project_name and vault_client:
                print(f"Project ID not provided, attempting to retrieve from Vault...")
                vault_info = vault_client.get_project_info(vault_path_prefix, project_name)
                
                if vault_info and 'id' in vault_info:
                    project_id = vault_info['id']
                    print(f"Found project ID in Vault: {project_id}")
                    
                    # Also get project_type from Vault if not provided
                    if (not project_type or project_type == "elasticsearch") and 'project_type' in vault_info:
                        project_type = vault_info['project_type']
                        print(f"Using project type from Vault: {project_type}")
                else:
                    print("Could not find project information in Vault")
            
            if not project_id:
                print("Error: Project ID is required for resetting credentials")
                sys.exit(1)
                
            print(f"Resetting credentials for {project_type} project {project_id}...")
            result = elastic_client.reset_credentials(project_type, project_id)
            print(f"Successfully reset credentials for project {project_id}")
            
            # The reset-credentials API returns credentials directly in the response
            if 'username' in result and 'password' in result:
                print("\nNew Credentials:")
                print(f"  Username: {result.get('username', 'N/A')}")
                print(f"  Password: {result.get('password', 'N/A')}")
            
            # Update credentials in Vault if configured
            if vault_client and project_name and ('username' in result or 'password' in result):
                # First retrieve existing information
                existing_info = vault_client.get_project_info(vault_path_prefix, project_name)
                
                if existing_info:
                    # Update credentials in the new format
                    username = result.get('username')
                    password = result.get('password')
                    
                    if username:
                        existing_info['ELASTICSEARCH_USERNAME'] = username
                    if password:
                        existing_info['ELASTICSEARCH_PASSWORD'] = password
                    if username and password:
                        existing_info['CLOUD_AUTH'] = f"{username}:{password}"
                    
                    # Store updated information
                    success = vault_client.store_project_info(
                        path_prefix=vault_path_prefix,
                        project_name=project_name,
                        project_info=existing_info
                    )
                    
                    if success:
                        print(f"Successfully updated credentials in Vault")
                    else:
                        print("Failed to update credentials in Vault")
                else:
                    print(f"No existing project information found in Vault for {project_name}")
            
        elif operation == 'list':
            print(f"Listing all {project_type} projects...")
            result = elastic_client.list_projects(project_type)
            print(json.dumps(result, indent=2))
            
        else:
            print(f"Unknown operation: {operation}")
            sys.exit(1)
            
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()