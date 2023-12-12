<#
.SYNOPSIS 
    This PowerShell script restores deleted runbooks in an Azure Automation account. 
    It searches for deleted runbooks matching the provided names of the runbook and restores the most recent one.

.DESCRIPTION

    This PowerShell script is designed to restore deleted runbooks in an Azure Automation account. 
    It queries the Azure Automation API for deleted runbooks and, based on user input, 
    identifies and restores the specified runbooks.

.PARAMETER subscriptionId
    Required. Subscription of the Azure Automation account in which the runbook needs to be restored.
 
.PARAMETER resourceGroupName
    Required. The name of the resource group of the Azure Automation account.
    
.PARAMETER automationAccountName
    Required. The name of the Azure Automation account in which the runbook needs to be restored.
    
.PARAMETER runbookNames
    Required. The list of names of deleted runbooks to be restored. Ex :- ["runbook1", "runbook2", "runbook3"]

.NOTES
    AUTHOR: Azure Automation Product Team
    LASTEDIT: Dec 6, 2023 
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$automationAccountName,

    [Parameter(Mandatory = $true)]
    [string[]]$runbookNames
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

# Base URL of the Runbook Restore API
$runbookRestoreApiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/"

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

# Function to restore a runbook
function Restore-Runbook($runbookName, $runbookId, $runbookLocation) {
    $runbookApiUrl = $runbookRestoreApiUrl + $runbookName + "?api-version=2023-05-15-preview"
    
    # Payload for restoring the runbook
    $restorePayload = @{
        name       = $runbookName
        location   = $runbookLocation
        properties = @{
            createMode = "recover"
            runbookId  = $runbookId
        }
    } | ConvertTo-Json

    # Invoke API call to restore the runbook
    try {
        $restoreResponse = Invoke-RestMethod -Uri $runbookApiUrl -Method Put -Headers $Headers -Body $restorePayload

        if ($restoreResponse) {
            Write-Output "Runbook '$runbookName' restored successfully."
        } 
    } catch {
        Write-Error "Runbook restore failed. Response: $_"
    }
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

# Filter runbooks based on user input
$filteredRunbooks = $allDeletedRunbooks | Where-Object { $runbookNames -contains $_.name }

# Sort runbooks by deletion time in descending order
$sortedRunbooks = $filteredRunbooks | Sort-Object { [datetime]::Parse($_.properties.deletionTime) } -Descending

# Loop through each runbook, get the location and run the restore function
foreach ($runbookName in $runbookNames) {
    Write-Output "Searching '$runbookName' in the deleted runbooks..."
    $matchingRunbooks = $sortedRunbooks | Where-Object { $_.name -eq $runbookName }
    if ($matchingRunbooks.Count -gt 0) {
        if ($matchingRunbooks.Count -gt 1) {
            Write-Warning "Multiple runbooks with name '$runbookName' found in the deleted runbooks. Restoring the most recent deleted runbook..."
        }
        $mostRecentRunbook = $matchingRunbooks[0]
        $runbookId = $mostRecentRunbook.properties.runbookId
        $runbookLocation = $mostRecentRunbook.location

        Write-Output "Runbook '$runbookName' found in the deleted runbooks. Restoring the runbook..."
        # Restore the runbook
        Restore-Runbook -runbookName $runbookName -runbookId $runbookId -runbookLocation $runbookLocation
    } else {
        Write-Error "Runbook '$runbookName' not found in the deleted runbooks. Runbooks deleted within 30 days can be restored only."
    }
}
