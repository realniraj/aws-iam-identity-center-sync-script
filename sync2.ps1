#Requires -Version 7.0

# Check if the required module is installed before attempting to import it.
if (-not (Get-Module -ListAvailable -Name Microsoft.Entra)) {
    Write-Error "The 'Microsoft.Entra' module is not installed. Please run 'Install-Module -Name Microsoft.Entra -Scope CurrentUser' in your PowerShell terminal and then re-run this script." -ErrorAction Stop
}

# Import the Microsoft.Entra module.
# Ensure you have it installed: Install-Module -Name Microsoft.Entra -Scope CurrentUser
# If you need beta features, also install: Install-Module -Name Microsoft.Entra.Beta -Scope CurrentUser
# Note: Microsoft.Entra module depends on Microsoft.Graph.* modules, so you'll get those too.
Import-Module Microsoft.Entra -ErrorAction Stop

#region Get
function Get-EntraSynchronizationJobId {
    [CmdletBinding(SupportsShouldProcess=$true)] # Added SupportsShouldProcess for best practice
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId # ServicePrincipalId is a string
    )
 
    begin {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " begin")
    }
 
    process {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " process")
        try {
            # Use Get-MgServicePrincipalSynchronizationJob from Microsoft.Graph.Applications
            # This cmdlet directly queries the /servicePrincipals/{id}/synchronization/jobs endpoint
            $syncJobs = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $ServicePrincipalId -All

            # Assuming there's only one relevant job for AWS SSO integration,
            # or you need the first one. Adjust if multiple jobs exist and require specific filtering.
            if ($syncJobs) {
                $jobId = $syncJobs[0].Id
                Write-Verbose "Found Synchronization Job ID: $jobId"
            } else {
                Write-Warning "No synchronization jobs found for Service Principal ID: $ServicePrincipalId"
                $jobId = $null # Explicitly set to null if no job found
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
 
    end {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " end")
        return $jobId
    }
}

function Get-EntraServicePrincipal {
    [CmdletBinding(SupportsShouldProcess=$true)] # Added SupportsShouldProcess for best practice
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )
 
    begin {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " begin")
    }
 
    process {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " process")
        try {
            # Use Get-MgServicePrincipal from Microsoft.Graph.Applications
            # Filter by display name directly at the source using -Filter for efficiency
            # The 'eq' operator is for exact match.
            $servicePrincipals = Get-MgServicePrincipal -Filter "displayName eq '$($DisplayName)'" -All

            if ($servicePrincipals.Count -eq 1) {
                $objectId = $servicePrincipals[0].Id
                Write-Verbose "Found Service Principal ID: $objectId for Display Name: '$DisplayName'"
            } elseif ($servicePrincipals.Count -gt 1) {
                Write-Warning "Multiple service principals found with display name '$DisplayName'. Returning the first one found."
                $objectId = $servicePrincipals[0].Id
            } else {
                Write-Error "No service principal found with display name '$DisplayName'." -ErrorAction Stop
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
 
    end {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " end")
        return $objectId
    }
}
#endregion

#region Start
function Start-EntraSynchronizationJob {
    [CmdletBinding(SupportsShouldProcess=$true)] # Added SupportsShouldProcess for best practice
    [OutputType([string])] # Output type might be null or an object depending on Graph API response
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,
 
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )
 
    begin {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " begin")
    }
 
    process {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " process")
        try {
            # Use Start-MgServicePrincipalSynchronizationJob from Microsoft.Graph.Applications
            # This cmdlet directly calls the /start endpoint
            $response = Start-MgServicePrincipalSynchronizationJob -ServicePrincipalId $ServicePrincipalId -SynchronizationJobId $JobId -WhatIf:$false # Explicitly run action

            # Graph API for /start usually returns 204 No Content on success, so $response might be null
            if ($response) {
                Write-Verbose "Synchronization job started successfully. Response: $($response | ConvertTo-Json -Depth 2)"
                return $response # Return the response if any
            } else {
                Write-Verbose "Synchronization job start request sent. No content returned (expected for success)."
                return "Synchronization job start request sent successfully." # Indicate success
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
 
    end {
        Write-Verbose -Message ("Initiating function " + $MyInvocation.MyCommand + " end")
    }
}
#endregion

#region Initialization
function Initialization {
    [CmdletBinding()]
    param ()

    begin {
        Clear-Host
        Write-Host "AWS Single Sign-On Integration - Sync`n" -ForegroundColor Yellow

        # Collect authentication details
        $tenantId = Read-Host -Prompt "Tenant Id"
        if ([string]::IsNullOrEmpty($tenantId)) { Write-Error -Message "Tenant Id cannot be blank." -ErrorAction Stop }

        $applicationId = Read-Host -Prompt "App Id"
        if ([string]::IsNullOrEmpty($applicationId)) { Write-Error -Message "Application Id cannot be blank." -ErrorAction Stop }

        $clientSecret = Read-Host -Prompt "Client Secret" -AsSecureString
        if ([string]::IsNullOrEmpty($clientSecret)) { Write-Error -Message "Client Secret cannot be blank." -ErrorAction Stop }

        # Collect service principal display name
        $displayName = Read-Host -Prompt "Display Name of AWS SSO Service Principal"
        if ([string]::IsNullOrEmpty($displayName)) { Write-Error -Message "Display Name cannot be blank." -ErrorAction Stop }

        Clear-Host
        Write-Host "AWS Single Sign-On Integration - Sync Starting" -ForegroundColor Yellow
    }

    process {
        Write-Verbose -Message "Connecting to Microsoft Entra ID..."
        try {
            # Connect using the Microsoft.Entra module's connection cmdlet.
            # This uses the client credentials flow with the provided app details.
            # Ensure your App Registration has the necessary Microsoft Graph API permissions (e.g., Synchronization.Read.All, Synchronization.ReadWrite.All, Application.Read.All).
            Connect-Entra -TenantId $tenantId -ApplicationId $applicationId -ClientSecret $clientSecret -ErrorAction Stop
            Write-Verbose "Successfully connected to Microsoft Entra ID."
        }
        catch {
            Write-Error "Failed to connect to Microsoft Entra ID. Please check your Tenant ID, Application ID, Client Secret, and App Registration permissions." -ErrorRecord $_ -ErrorAction Stop
        }

        Write-Verbose "Getting Service Principal ID..."
        $servicePrincipalId = Get-EntraServicePrincipal -DisplayName $displayName -Verbose:$VerbosePreference
        if ([string]::IsNullOrEmpty($servicePrincipalId)) {
            Write-Error "Could not retrieve Service Principal ID. Aborting synchronization." -ErrorAction Stop
        }
        Write-Verbose "Service Principal ID: $servicePrincipalId"

        Write-Verbose "Getting Synchronization Job ID..."
        $jobId = Get-EntraSynchronizationJobId -ServicePrincipalId $servicePrincipalId -Verbose:$VerbosePreference
        if ([string]::IsNullOrEmpty($jobId)) {
            Write-Error "Could not retrieve Synchronization Job ID. Aborting synchronization." -ErrorAction Stop
        }
        Write-Verbose "Synchronization Job ID: $jobId"

        Write-Verbose "Starting Synchronization Job..."
        Start-EntraSynchronizationJob -ServicePrincipalId $servicePrincipalId -JobId $jobId -Verbose:$VerbosePreference
        Write-Verbose "Synchronization job start request completed."
    }

    end {
        Write-Host "AWS Single Sign-On Integration - Sync Completed" -ForegroundColor Green
        # Disconnect from Microsoft Graph after operations are done
        Disconnect-Entra -Confirm:$false
        Write-Verbose "Disconnected from Microsoft Entra ID."
    }
}
#endregion

# Execute the main initialization function
Initialization
