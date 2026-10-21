############################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Import
# PowerShell V2
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
    Write-Information 'Starting import of Ultimo-User accounts'

    $actionMessage = 'querying accounts'
    $getAllUsersSplatParams = @{
        Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
        Method = 'POST'
        Body   = (@{
                Action = 'GetAllUsers'
            } | ConvertTo-Json)
    }
    $existingAccounts = (Invoke-UltimoUserRestMethod @getAllUsersSplatParams).properties.AllUsers
    Write-Information "Queried accounts. Result count: $(($existingAccounts | Measure-Object).Count)"

    $importedAccounts = 0
    foreach ($account in $existingAccounts) {
        $actionMessage = "processing account with UserId [$($account.Id)]"

        # An account is enabled when it has an activation date
        $enabled = $false
        if ($account.PSObject.Properties.Name -contains 'ActivationDateTime' -and -not([string]::IsNullOrEmpty($account.ActivationDateTime))) {
            $enabled = $true
        }

        $userName = $account.ExternalAccountName
        if ([string]::IsNullOrEmpty($userName)) {
            $userName = $account.Id
        }

        $displayName = $account.Description
        if ([string]::IsNullOrEmpty($displayName)) {
            $displayName = $account.Id
        }

        # Add the properties as named in the field mapping
        $account | Add-Member -NotePropertyMembers @{
            UserId          = $account.Id
            UserDescription = $account.Description
        } -Force

        Write-Output @{
            AccountReference = $account.Id
            DisplayName      = $displayName
            UserName         = $userName
            Enabled          = $enabled
            Data             = $account
        }
        $importedAccounts++
    }
    Write-Information "Completed import of Ultimo-User accounts. Result count: $($importedAccounts)"
}
catch {
    $ex = $PSItem
    $errorObj = Resolve-UltimoUserError -ErrorObject $ex
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    Write-Error "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
}
