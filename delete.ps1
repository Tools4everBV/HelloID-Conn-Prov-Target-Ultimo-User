#################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Delete
# PowerShell V2
# Note: Ultimo does not support deleting a user, so this is a soft-delete.
#       The fields mapped for the Delete action in the field mapping are updated.
#################################################

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

            # Ultimo allows a maximum of 100 requests per 10 seconds. When that limit is exceeded (HTTP 429), wait for the next window and retry.
            # The daily quota is not retried, because waiting 10 seconds does not help. Only the message of the 10 seconds limit is known, so only that message is retried
            $maxRetries = 3
            $retryDelayInSeconds = 10
            $retryCount = 0
            while ($true) {
                try {
                    $response = Invoke-RestMethod @splatParams -Verbose:$false
                    break
                }
                catch {
                    $errorRecord = $_
                    $statusCode = $null
                    if ($null -ne $errorRecord.Exception.Response) {
                        $statusCode = [int]$errorRecord.Exception.Response.StatusCode
                    }
                    $errorBody = "$($errorRecord.ErrorDetails)"
                    if ([string]::IsNullOrEmpty($errorBody) -and $errorRecord.Exception -is [System.Net.WebException] -and $null -ne $errorRecord.Exception.Response) {
                        # Windows PowerShell does not fill ErrorDetails. Read the response body once and store it, so Resolve-UltimoUserError can still use it
                        $errorBody = [System.IO.StreamReader]::new($errorRecord.Exception.Response.GetResponseStream()).ReadToEnd()
                        if (-not [string]::IsNullOrWhiteSpace($errorBody)) {
                            $errorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($errorBody)
                        }
                    }
                    $isTooManyRequests = (($statusCode -eq 429) -or ($errorBody -match 'TooManyRequests')) -and ($errorBody -match '10 seconds')
                    if ($isTooManyRequests -and $retryCount -lt $maxRetries) {
                        $retryCount++
                        Write-Warning "Ultimo API request limit reached (HTTP 429). Retry [$($retryCount)/$($maxRetries)] in [$($retryDelayInSeconds)] seconds"
                        Start-Sleep -Seconds $retryDelayInSeconds
                    }
                    else {
                        throw $errorRecord
                    }
                }
            }
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

function Get-UltimoUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $UserId
    )
    process {
        try {
            $splatParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                Method = 'POST'
                Body   = (@{
                        Action = 'GetUser'
                        UserId = $UserId
                    } | ConvertTo-Json)
            }
            Write-Output (Invoke-UltimoUserRestMethod @splatParams).properties.UserDetails
        }
        catch {
            # Ultimo returns an error instead of an empty result when the user does not exist
            if ($_.Exception.Message -eq "User $($UserId) not found.") {
                Write-Output $null
            }
            else {
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
    }
}
#endregion functions

try {
    $actionMessage = 'verifying account reference'
    if ([string]::IsNullOrEmpty($actionContext.References.Account)) {
        throw 'The account reference could not be found'
    }

    $actionMessage = "querying account with AccountReference: [$($actionContext.References.Account)]"
    $correlatedAccount = Get-UltimoUser -UserId $actionContext.References.Account

    $actionMessage = 'determining action'
    # The configuration group can not be part of the soft-delete, it is not updated by the UpdateUser action
    $fieldsToUpdate = @($actionContext.Data.PSObject.Properties.Name | Where-Object { $_ -ne 'GroupId' })
    if ($null -eq $correlatedAccount) {
        $action = 'NotFound'
    }
    elseif ($fieldsToUpdate.Count -eq 0) {
        $action = 'NoFieldsMapped'
    }
    else {
        $action = 'DeleteAccount'
    }
    Write-Information "Determined action: $($action)"

    # Process
    switch ($action) {
        'DeleteAccount' {
            $actionMessage = "soft-deleting account with AccountReference: [$($actionContext.References.Account)]"

            $deleteAccountBody = $actionContext.Data | Select-Object * -ExcludeProperty GroupId
            $deleteAccountBody | Add-Member -NotePropertyMembers @{
                Action = 'UpdateUser'
                UserId = $actionContext.References.Account
            } -Force
            # The UserDescription is required by the UpdateUser action, so fall back to the current value
            if ('UserDescription' -notin $fieldsToUpdate) {
                $deleteAccountBody | Add-Member -NotePropertyMembers @{ UserDescription = $correlatedAccount.Description } -Force
            }
            $deleteAccountSplatParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                Method = 'POST'
                Body   = ($deleteAccountBody | ConvertTo-Json)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-UltimoUserRestMethod @deleteAccountSplatParams

                $outputContext.PreviousData = [PSCustomObject]@{
                    UserId              = $correlatedAccount.id
                    ExternalAccountName = $correlatedAccount.ExternalAccountName
                    UserDescription     = $correlatedAccount.Description
                }
                $outputContext.Data = $actionContext.Data

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'DeleteAccount'
                        Message = "Soft-deleted account with AccountReference: [$($actionContext.References.Account)]. Fields updated: [$($fieldsToUpdate -join ', ')]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would soft-delete account with AccountReference: [$($actionContext.References.Account)]. Fields to update: [$($fieldsToUpdate -join ', ')]"
            }
            break
        }

        'NoFieldsMapped' {
            $actionMessage = "soft-deleting account with AccountReference: [$($actionContext.References.Account)]"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'DeleteAccount'
                    Message = "No fields are mapped for the Delete action, so account with AccountReference: [$($actionContext.References.Account)] is not changed. Ultimo does not support deleting a user"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            $actionMessage = "soft-deleting account with AccountReference: [$($actionContext.References.Account)]"

            # Nothing to delete when the account no longer exists, so this is not treated as an error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'DeleteAccount'
                    Message = "Account with AccountReference: [$($actionContext.References.Account)] for person [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it is already deleted, or the account is not correlated"
                    IsError = $false
                })
            break
        }
    }

    $outputContext.Success = $true
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    $errorObj = Resolve-UltimoUserError -ErrorObject $ex
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })
}
