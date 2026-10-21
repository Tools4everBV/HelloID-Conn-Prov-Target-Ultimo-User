############################################################
# HelloID-Conn-Prov-Target-Ultimo-User-ImportPermissions-Group
# PowerShell V2
# HelloID script: Import permission memberships script
############################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Invoke-UltimoUserRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json;charset=utf-8'
    )
    process {
        try {
            $headers = @{
                APIKey               = $actionContext.Configuration.ApiKey
                ApplicationElementId = $actionContext.Configuration.ApplicationElementId
            }
            $splatParams = @{
                Uri         = $Uri
                Headers     = $headers
                Method      = $Method
                ContentType = $ContentType
            }
            if ($Body) {
                $splatParams['Body'] = [System.Text.Encoding]::UTF8.GetBytes($Body)
            }
            $response = Invoke-RestMethod @splatParams -Verbose:$false
            if ($response.properties.ResponseSummary.Succes -eq $false) {
                throw $response.properties.ResponseSummary.Message
            }
            Write-Output $response
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Resolve-UltimoUserError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        $webResponse = $false
        if ($ErrorObject.ErrorDetails) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
            $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails
            $webResponse = $true
        }
        elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if (-not([string]::IsNullOrWhiteSpace($streamReaderResponse))) {
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = $streamReaderResponse
                $webResponse = $true
            }
        }
        if ($webResponse) {
            try {
                $convertedErrorObject = ($httpErrorObj.FriendlyMessage | ConvertFrom-Json)
                if (-not [string]::IsNullOrEmpty($convertedErrorObject.Message)) {
                    $httpErrorObj.FriendlyMessage = $convertedErrorObject.Message
                }
            }
            catch {
                Write-Warning "Unexpected web service response, Error during Json conversion: $($_.Exception.Message)"
            }
        }
        Write-Output $httpErrorObj
    }
}
#endregion functions

try {
    Write-Information 'Starting import permission memberships script: retrieving which accounts are member of which Ultimo-User authorization groups'

    $actionMessage = 'querying accounts'
    $getAllUsersSplatParams = @{
        Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
        Method = 'POST'
        Body   = (@{
                Action = 'GetAllUsers'
            } | ConvertTo-Json)
    }
    $existingAccounts = (Invoke-UltimoUserRestMethod @getAllUsersSplatParams).properties.AllUsers
    Write-Information "Import permission memberships script: queried accounts. Result count: $(($existingAccounts | Measure-Object).Count)"

    $actionMessage = 'querying authorization groups'
    $getAuthorizationGroupsSplatParams = @{
        Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
        Method = 'POST'
        Body   = (@{
                Action = 'GetAllAuthorizationGroups'
            } | ConvertTo-Json)
    }
    $retrievedPermissions = (Invoke-UltimoUserRestMethod @getAuthorizationGroupsSplatParams).properties.AllAvailableAuthorizationGroups
    Write-Information "Import permission memberships script: queried authorization groups. Result count: $(($retrievedPermissions | Measure-Object).Count)"

    $permissionsGrouped = $retrievedPermissions | Group-Object -Property 'GroupId' -AsHashTable -AsString

    $importedPermissions = 0
    foreach ($account in $existingAccounts) {
        $actionMessage = "processing authorization groups of account with AccountReference: [$($account.Id)]"

        foreach ($group in $account.AuthorizationGroups) {
            # The configuration group is also returned as authorization group, which is not a permission
            if ($group.sgrousegroid -eq $account.ConfigurationGroup.sgroname) {
                continue
            }
            # Only return permissions that are also retrieved by permissions.ps1, HelloID cannot link anything else
            if (-not $permissionsGrouped.ContainsKey([string]$group.sgrousegroid)) {
                continue
            }

            Write-Output @{
                PermissionReference = @{
                    Reference = "$($group.sgrousegroid)"
                }
                DisplayName         = "$($permissionsGrouped[[string]$group.sgrousegroid].GroupName)"
                AccountReferences   = @("$($account.Id)")
            }
            $importedPermissions++
        }
    }
    Write-Information "Completed import permission memberships script. Imported [$($importedPermissions)] permission memberships"
}
catch {
    $ex = $PSItem
    $errorObj = Resolve-UltimoUserError -ErrorObject $ex
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    Write-Error "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
}
