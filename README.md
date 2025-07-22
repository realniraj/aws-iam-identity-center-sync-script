# Entra ID to AWS IAM Identity Center Manual Sync Script

## 1. Overview

This document describes a PowerShell script (`sync2.ps1`) designed to manually initiate a provisioning synchronization from Microsoft Entra ID to AWS IAM Identity Center (formerly AWS Single Sign-On).

In a typical cloud environment, user and group provisioning from an identity provider like Entra ID to a service provider like AWS is automated but runs on a schedule (e.g., every 40 minutes). This script provides a mechanism for administrators to trigger an on-demand synchronization. This is particularly useful after making immediate changes in Entra ID, such as adding a new user to a group that grants AWS access, and needing those changes to be reflected in AWS instantly without waiting for the next scheduled cycle.

The script securely connects to the Microsoft Graph API using an Entra ID Application Registration and its credentials to perform the necessary operations.

## 2. Core Features

*   **On-Demand Synchronization**: The primary function is to start the Entra ID provisioning job for AWS IAM Identity Center immediately.
*   **Secure Authentication**: Uses the Client Credentials flow (Application ID and a Client Secret) to authenticate with Microsoft Graph, avoiding the need to use a privileged user account. Client secrets are handled securely as `SecureString` objects in memory.
*   **Dynamic Object Discovery**: The script does not require hardcoded object IDs. It dynamically looks up the Service Principal for the AWS application using its display name.
*   **Prerequisite Validation**: Automatically checks if the required `Microsoft.Entra` PowerShell module is installed on the host machine, providing a user-friendly error if it is not.
*   **Robust & Verbose**: Incorporates `try...catch` blocks for error handling and provides detailed verbose output (`-Verbose` switch) for easy troubleshooting.
*   **Modern PowerShell Practices**: Built using advanced functions, `[CmdletBinding()]`, and leverages the official Microsoft Graph PowerShell SDK cmdlets (`Microsoft.Entra` module) instead of manual REST API calls.

## 3. Prerequisites

Before running this script, the following must be in place:

### 3.1. Software Requirements

1.  **PowerShell 7.0 or higher**: The script explicitly requires a modern version of PowerShell.
2.  **Microsoft.Entra Module**: The script depends on this module. It can be installed by running the following command in PowerShell:
    ```powershell
    Install-Module -Name Microsoft.Entra -Scope CurrentUser -Repository PSGallery -Force
    ```

### 3.2. Microsoft Entra ID Configuration

1.  **AWS IAM Identity Center Enterprise Application**: You must have the AWS IAM Identity Center application configured in Entra ID for provisioning.
2.  **Application Registration**: An App Registration must be created in Entra ID to grant the script programmatic access.
    *   **Application (Client) ID**: This will be required to run the script.
    *   **Client Secret**: A client secret must be generated for this App Registration. The secret *value* (not the Secret ID) is required.
3.  **API Permissions**: The App Registration must be granted the following **Application** permissions for Microsoft Graph. An administrator must grant consent for these permissions.
    *   `Application.Read.All`: To find the AWS Service Principal by its display name.
    *   `Synchronization.Read.All`: To read the synchronization jobs associated with the Service Principal.
    *   `Synchronization.ReadWrite.All`: To start the synchronization job.

## 4. How to Use the Script

1.  Open a PowerShell 7+ terminal.
2.  Navigate to the directory containing `sync2.ps1`.
3.  Execute the script:
    ```powershell
    .\sync2.ps1
    ```
4.  The script will interactively prompt you for the following information:
    *   **Tenant Id**: The Directory (tenant) ID of your Microsoft Entra ID instance.
    *   **App Id**: The Application (client) ID of your App Registration.
    *   **Client Secret**: The client secret value from your App Registration. Input will be hidden for security.
    *   **Display Name of AWS SSO Service Principal**: The exact display name of the AWS IAM Identity Center enterprise application in Entra ID (e.g., "AWS IAM Identity Center").
5.  The script will then connect to Entra ID and perform the synchronization.

To see detailed step-by-step logging, run the script with the `-Verbose` switch:
```powershell
.\sync2.ps1 -Verbose
```

## 5. Script Workflow & Logic

The script is organized into several functions, orchestrated by a main `Initialization` function.

1.  **Prerequisite Check**: The script first checks if the `Microsoft.Entra` module is available. If not, it exits with an informative error.
2.  **`Initialization` Function**:
    *   Prompts the user for the necessary credentials and identifiers.
    *   Calls `Connect-Entra` to establish a secure, authenticated session with Microsoft Graph using the provided App ID and Client Secret.
    *   Calls `Get-EntraServicePrincipal` to retrieve the unique Object ID of the AWS enterprise application.
    *   Passes the retrieved Service Principal ID to `Get-EntraSynchronizationJobId` to find the corresponding provisioning Job ID.
    *   Calls `Start-EntraSynchronizationJob` with the Service Principal ID and Job ID to trigger the sync.
    *   Upon completion, it prints a success message and calls `Disconnect-Entra` to terminate the session.
3.  **`Get-EntraServicePrincipal` Function**:
    *   Takes a `DisplayName` as input.
    *   Uses the `Get-MgServicePrincipal` cmdlet with a `-Filter` to efficiently query the Graph API for a service principal with a matching display name.
    *   Includes logic to handle cases where no service principal is found or multiple are found.
    *   Returns the Object ID of the found service principal.
4.  **`Get-EntraSynchronizationJobId` Function**:
    *   Takes a `ServicePrincipalId` as input.
    *   Uses the `Get-MgServicePrincipalSynchronizationJob` cmdlet to retrieve all synchronization jobs for that service principal.
    *   It assumes the first job in the returned list is the correct one, which is standard for the AWS integration.
    *   Returns the ID of the found job.
5.  **`Start-EntraSynchronizationJob` Function**:
    *   Takes a `ServicePrincipalId` and `JobId` as input.
    *   Calls the `Start-MgServicePrincipalSynchronizationJob` cmdlet, which sends the request to the Graph API to start the provisioning.
    *   The Graph API typically returns a `204 No Content` status on success, and the function handles this by returning a user-friendly success message.