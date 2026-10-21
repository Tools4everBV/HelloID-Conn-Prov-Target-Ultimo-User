#################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Update
# PowerShell V2
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
                    if ([string]::IsNullOrEmpty($errorBody) -and $errorRecord.Exception.GetType().FullName -eq 'System.Net.WebException' -and $null -ne $errorRecord.Exception.Response) {
                        # Windows PowerShell does not fill ErrorDetails. Read the response body once and keep it on the exception, so Resolve-UltimoUserError can still use it
                        $errorBody = [System.IO.StreamReader]::new($errorRecord.Exception.Response.GetResponseStream()).ReadToEnd()
                        $errorRecord.Exception.Data['ResponseBody'] = $errorBody
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
        elseif (-not [string]::IsNullOrWhiteSpace($ErrorObject.Exception.Data['ResponseBody'])) {
            $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Data['ResponseBody']
            $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Data['ResponseBody']
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

    $actionMessage = 'calculating changes'
    $actionList = @()
    $propertiesChanged = @()
    if ($null -ne $correlatedAccount) {
        # The request and response of the API use different property names, so a custom object is used to compare
        $currentAccount = [PSCustomObject]@{
            ExternalAccountName = $correlatedAccount.ExternalAccountName
            UserDescription     = $correlatedAccount.Description
        }
        $outputContext.PreviousData = [PSCustomObject]@{
            UserId              = $correlatedAccount.id
            ExternalAccountName = $correlatedAccount.ExternalAccountName
            UserDescription     = $correlatedAccount.Description
            GroupId             = $correlatedAccount.ConfigurationGroup.sgroname
        }

        # Only compare the properties that are mapped, null and empty values are treated as equal
        foreach ($property in $currentAccount.PSObject.Properties.Name) {
            if ($actionContext.Data.PSObject.Properties.Name -contains $property) {
                if ("$($actionContext.Data.$property)" -ne "$($currentAccount.$property)") {
                    $propertiesChanged += $property
                }
            }
        }
        if ($propertiesChanged.Count -gt 0) {
            $actionList += 'UpdateAccount'
        }

        if (-not [string]::IsNullOrEmpty($actionContext.Data.GroupId) -and $correlatedAccount.ConfigurationGroup.sgroname -ne $actionContext.Data.GroupId) {
            $actionList += 'UpdateConfiguration'
        }

        if ($actionList.Count -eq 0) {
            $actionList += 'NoChanges'
        }
    }
    else {
        $actionList += 'NotFound'
    }
    Write-Information "Determined action(s): $($actionList -join ', ')"

    # Process
    foreach ($action in $actionList) {
        switch ($action) {
            'UpdateAccount' {
                $actionMessage = "updating account with AccountReference: [$($actionContext.References.Account)]"

                # The configuration group is updated separately, so it is not part of the update body
                $updateAccountBody = $actionContext.Data | Select-Object * -ExcludeProperty GroupId
                $updateAccountBody | Add-Member -NotePropertyMembers @{
                    Action = 'UpdateUser'
                    UserId = $actionContext.References.Account
                } -Force
                $updateAccountSplatParams = @{
                    Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                    Method = 'POST'
                    Body   = ($updateAccountBody | ConvertTo-Json)
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    $null = Invoke-UltimoUserRestMethod @updateAccountSplatParams

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'UpdateAccount'
                            Message = "Updated account with AccountReference: [$($actionContext.References.Account)]. Properties updated: [$($propertiesChanged -join ', ')]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would update account with AccountReference: [$($actionContext.References.Account)]. Properties to update: [$($propertiesChanged -join ', ')]"
                }
                break
            }

            'UpdateConfiguration' {
                $actionMessage = "updating Configuration Group of account with AccountReference: [$($actionContext.References.Account)] to [$($actionContext.Data.GroupId)]"

                $updateConfigurationSplatParams = @{
                    Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                    Method = 'POST'
                    Body   = (@{
                            Action  = 'ChangeConfigurationGroup'
                            UserId  = $actionContext.References.Account
                            GroupId = $actionContext.Data.GroupId
                        } | ConvertTo-Json)
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    $null = Invoke-UltimoUserRestMethod @updateConfigurationSplatParams

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'UpdateAccount'
                            Message = "Updated Configuration Group of account with AccountReference: [$($actionContext.References.Account)] from [$($correlatedAccount.ConfigurationGroup.sgroname)] to [$($actionContext.Data.GroupId)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would update Configuration Group of account with AccountReference: [$($actionContext.References.Account)] from [$($correlatedAccount.ConfigurationGroup.sgroname)] to [$($actionContext.Data.GroupId)]"
                }
                break
            }

            'NoChanges' {
                Write-Information "No changes to account with AccountReference: [$($actionContext.References.Account)]"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'UpdateAccount'
                        Message = "No changes will be made to account with AccountReference: [$($actionContext.References.Account)] because it already corresponds with the account data"
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $actionMessage = "updating account with AccountReference: [$($actionContext.References.Account)]"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'UpdateAccount'
                        Message = "Account with AccountReference: [$($actionContext.References.Account)] for person [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $true
                    })
                break
            }
        }
    }

    if (-not($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
        $outputContext.Data = $actionContext.Data
    }
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
