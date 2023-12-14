<#
.SYNOPSIS 
    This PowerShell script lists deleted runbooks in an Azure Automation account. 

.DESCRIPTION

    This PowerShell script is designed to list deleted runbooks in an Azure Automation account. 

.PARAMETER subscriptionId
    Required. Subscription of the Azure Automation account in which the runbook needs to be listed.
 
.PARAMETER resourceGroupName
    Required. The name of the resource group of the Azure Automation account.
    
.PARAMETER automationAccountName
    Required. The name of the Azure Automation account in which the runbook needs to be listed.

.NOTES
    AUTHOR: Azure Automation Team
    LASTEDIT: Dec 7, 2023 
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$automationAccountName
)

# Function to log in to Azure
function Login-AzAccount {
    try
    {
        # This script requires system identity enabled for the automation account with 'Automation Contributor' role assignment on the identity.
        "Logging in to Azure..."
        Connect-AzAccount -Identity
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Base URL of the listDeletedRunbook API
$apiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/listDeletedRunbooks?api-version=2023-05-15-preview"

# Function to retrieve all deleted runbooks from the API
function Get-AllDeletedRunbooks {
    $allRunbooks = @()

    do {
        try {
            # Call the API
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $Headers -ErrorAction Stop

            # Add the current set of runbooks to the collection
            $allRunbooks += $response.value

            # Check for the presence of NextLink
            if ($response.nextLink) {
                $apiUrl = $response.nextLink
            } else {
                $apiUrl = $null
            }
        } catch {
            Write-Error "Failed to retrieve deleted runbooks. Response: $_"
            break
        }
    } while ($apiUrl)

    return $allRunbooks
}

# Main script

# Login to Azure
Login-AzAccount

# Get the user token
$userToken = (Get-AzAccessToken).Token
$Headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer $($userToken)"
}

# Retrieve all runbooks
$allDeletedRunbooks = Get-AllDeletedRunbooks

Write-Output "Below are deleted runbook names under automation account $automationAccountName"

# Loop through each runbook, get the location and run the restore function
foreach ($runbookName in $allDeletedRunbooks) {
    
    if ($allDeletedRunbooks.Count -gt 0) {
        Write-Output $runbookName
    } else {
        Write-Error "Cannot find any runbook in the deleted runbooks. Runbooks deleted within 30 days can be restored only."
    }
}




