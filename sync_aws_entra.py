import logging
import sys
import getpass
import asyncio

from azure.identity.aio import ClientSecretCredential
from msgraph import GraphServiceClient
from msgraph.generated.models.o_data_errors.o_data_error import ODataError

# --- Configuration ---
# Configure logging to show informational messages
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

async def get_graph_client(tenant_id: str, client_id: str, client_secret: str) -> GraphServiceClient:
    """
    Creates and returns an authenticated GraphServiceClient using the azure-identity library.

    Args:
        tenant_id (str): The tenant ID.
        client_id (str): The application (client) ID.
        client_secret (str): The client secret.

    Returns:
        GraphServiceClient: An authenticated client for making Graph API calls.
    """
    logging.info("Creating Graph API client...")
    credential = ClientSecretCredential(tenant_id, client_id, client_secret)
    scopes = ["https://graph.microsoft.com/.default"]
    graph_client = GraphServiceClient(credentials=credential, scopes=scopes)
    return graph_client

async def get_service_principal_id(graph_client: GraphServiceClient, display_name: str) -> str | None:
    """
    Finds the Object ID of a service principal by its display name using the Graph SDK.

    Args:
        graph_client (GraphServiceClient): The authenticated Graph API client.
        display_name (str): The display name of the service principal to find.

    Returns:
        str | None: The Object ID of the service principal, or None if not found.
    """
    logging.info(f"Searching for Service Principal with display name: '{display_name}'")
    
    # The SDK requires a function for the query parameters
    # Note: Filtering requires the ConsistencyLevel header for some properties.
    # The SDK handles adding this header when using advanced query capabilities.
    request_configuration = graph_client.service_principals.get.request_configuration(
        query_parameters = {
            "filter": f"displayName eq '{display_name}'",
            "count": True # Necessary for ConsistencyLevel header
        },
        headers = {
            "ConsistencyLevel": "eventual"
        }
    )
    
    response = await graph_client.service_principals.get(request_configuration=request_configuration)
    
    if response and response.value:
        if len(response.value) > 1:
            logging.warning(f"Multiple service principals found with the name '{display_name}'. Returning the first one.")
        return response.value[0].id
    return None

async def get_sync_job_id(graph_client: GraphServiceClient, sp_id: str) -> str | None:
    """
    Gets the ID of the first synchronization job for a given service principal using the Graph SDK.

    Args:
        graph_client (GraphServiceClient): The authenticated Graph API client.
        sp_id (str): The Object ID of the service principal.

    Returns:
        str | None: The ID of the synchronization job, or None if not found.
    """
    logging.info(f"Searching for synchronization jobs for Service Principal ID: {sp_id}")
    
    # Synchronization APIs are in the 'beta' endpoint, which the SDK can access.
    response = await graph_client.service_principals.by_service_principal_id(sp_id).synchronization.jobs.get()

    if response and response.value:
        return response.value[0].id
    return None

async def start_sync_job(graph_client: GraphServiceClient, sp_id: str, job_id: str):
    """
    Sends a request to start a specific synchronization job using the Graph SDK.

    Args:
        graph_client (GraphServiceClient): The authenticated Graph API client.
        sp_id (str): The Object ID of the service principal.
        job_id (str): The ID of the synchronization job to start.
    """
    logging.info(f"Sending request to start synchronization job ID: {job_id}")
    
    # The start action doesn't return content on success, so the SDK call returns None.
    await graph_client.service_principals.by_service_principal_id(sp_id).synchronization.jobs.by_synchronization_job_id(job_id).start.post()
    
    logging.info("Request to start synchronization job sent successfully.")

async def main():
    """Main async function to orchestrate the synchronization process."""
    print("--- AWS Single Sign-On Integration - Sync (Python SDK) ---")
    
    try:
        tenant_id = input("Enter Tenant ID: ")
        client_id = input("Enter App (Client) ID: ")
        client_secret = getpass.getpass("Enter Client Secret: ")
        display_name = input("Enter Display Name of AWS SSO Service Principal: ")

        print("\n--- Sync Starting ---")

        # 1. Create the Graph client
        graph_client = await get_graph_client(tenant_id, client_id, client_secret)
        
        # 2. Get Service Principal ID
        sp_id = await get_service_principal_id(graph_client, display_name)
        if not sp_id:
            raise Exception(f"Service Principal with display name '{display_name}' not found.")
        logging.info(f"Found Service Principal ID: {sp_id}")

        # 3. Get Sync Job ID
        job_id = await get_sync_job_id(graph_client, sp_id)
        if not job_id:
            raise Exception(f"No synchronization job found for Service Principal ID '{sp_id}'.")
        logging.info(f"Found Synchronization Job ID: {job_id}")

        # 4. Start the job
        await start_sync_job(graph_client, sp_id, job_id)
        
        print("\n--- AWS Single Sign-On Integration - Sync Completed Successfully ---")

    except ODataError as e:
        # The SDK provides a structured error object.
        logging.error(f"A Graph API error occurred: {e.error.code} - {e.error.message}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # The SDK uses asyncio, so we need to run the main function in an event loop.
    asyncio.run(main())