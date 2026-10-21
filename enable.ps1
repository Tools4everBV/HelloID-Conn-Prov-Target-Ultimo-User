#################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Enable
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

            # Ultimo allows a maximum of 100 requests per 10 seconds. When exceeded (HTTP 429), wait for the next window and retry
            $maxRetries = 3
            $retryDelayInSeconds = 10
            $retryCount = 0
            while ($true) {
                try {
                    $response = Invoke-RestMethod @splatParams -Verbose:$false
                    break
                }
                catch {
                    $statusCode = $null
                    if ($null -ne $_.Exception.Response) {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                    $isTooManyRequests = ($statusCode -eq 429) -or ("$($_.ErrorDetails)" -match 'TooManyRequests')
                    if ($isTooManyRequests -and $retryCount -lt $maxRetries) {
                        $retryCount++
                        Write-Warning "Ultimo API request limit reached (HTTP 429). Retry [$($retryCount)/$($maxRetries)] in [$($retryDelayInSeconds)] seconds"
                        Start-Sleep -Seconds $retryDelayInSeconds
                    }
                    else {
                        throw
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
    if ($null -ne $correlatedAccount) {
        $action = 'EnableAccount'
    }
    else {
        $action = 'NotFound'
    }
    Write-Information "Determined action: $($action)"

    # Process
    switch ($action) {
        'EnableAccount' {
            $actionMessage = "enabling account with AccountReference: [$($actionContext.References.Account)]"

            $enableAccountSplatParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                Method = 'POST'
                Body   = (@{
                        Action          = 'UpdateUser'
                        UserDescription = $correlatedAccount.Description
                        UserId          = $actionContext.References.Account
                        EnableAccount   = $true
                    } | ConvertTo-Json)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-UltimoUserRestMethod @enableAccountSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'EnableAccount'
                        Message = "Enabled account with AccountReference: [$($actionContext.References.Account)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would enable account with AccountReference: [$($actionContext.References.Account)]"
            }
            break
        }

        'NotFound' {
            $actionMessage = "enabling account with AccountReference: [$($actionContext.References.Account)]"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'EnableAccount'
                    Message = "Account with AccountReference: [$($actionContext.References.Account)] for person [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $true
                })
            break
        }
    }

    if (-not($outputContext.AuditLogs.IsError -contains $true)) {
        $outputContext.Success = $true
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
