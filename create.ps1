#################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $actionMessage = 'validating mandatory fields'
    if ([string]::IsNullOrEmpty($actionContext.Data.EmployeeId)) {
        throw 'Mandatory attribute [account.EmployeeId] is empty. Please make sure it is correctly mapped'
    }
    # Ultimo does not accept these characters in an Id that is used in the route of the API
    if ($actionContext.Data.EmployeeId -match '[/<>*%&:\\?]') {
        throw "Attribute [account.EmployeeId] with value [$($actionContext.Data.EmployeeId)] contains a character that Ultimo does not accept in an Id: / < > * % & : \ ?"
    }
    if ([string]::IsNullOrEmpty($actionContext.Data.GroupId)) {
        throw 'Mandatory attribute [account.GroupId] is empty. Please make sure it is correctly mapped to an existing Ultimo Configuration Group'
    }

    $actionMessage = "validating if Ultimo employee [$($actionContext.Data.EmployeeId)] exists"
    try {
        $getEmployeeSplatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($actionContext.Data.EmployeeId)')"
            Method = 'GET'
        }
        $null = Invoke-UltimoUserRestMethod @getEmployeeSplatParams
    }
    catch {
        $ex = $PSItem
        $errorObj = Resolve-UltimoUserError -ErrorObject $ex
        throw "Could not find Ultimo employee [$($actionContext.Data.EmployeeId)], $($errorObj.FriendlyMessage)"
    }

    # Validate correlation configuration
    $actionMessage = 'validating correlation configuration'
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($correlationField)) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($correlationValue)) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $actionMessage = "querying account where [$($correlationField)] = [$($correlationValue)]"
        $correlatedAccount = Get-UltimoUser -UserId $correlationValue
    }

    $actionMessage = 'determining action'
    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    }
    else {
        $action = 'CreateAccount'
    }
    Write-Information "Determined action: $($action)"

    # Process
    switch ($action) {
        'CreateAccount' {
            $actionMessage = "creating account for person [$($personContext.Person.DisplayName)] with UserId [$($actionContext.Data.UserId)] and Configuration Group [$($actionContext.Data.GroupId)]"

            $createAccountBody = $actionContext.Data | Select-Object *
            $createAccountBody | Add-Member -NotePropertyMembers @{ Action = 'CreateUser' } -Force
            $createAccountSplatParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                Method = 'POST'
                Body   = ($createAccountBody | ConvertTo-Json)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                $createAccountResponse = Invoke-UltimoUserRestMethod @createAccountSplatParams

                $outputContext.Data = $actionContext.Data
                $outputContext.Data.UserId = $createAccountResponse.properties.UserDetails.id
                $outputContext.AccountReference = $createAccountResponse.properties.UserDetails.id

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CreateAccount'
                        Message = "Created account with AccountReference: [$($outputContext.AccountReference)] and Configuration Group [$($actionContext.Data.GroupId)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would create account for person [$($personContext.Person.DisplayName)] with UserId [$($actionContext.Data.UserId)] and Configuration Group [$($actionContext.Data.GroupId)]"
            }
            break
        }

        'CorrelateAccount' {
            $actionMessage = "correlating account on field [$($correlationField)] with value [$($correlationValue)]"

            $outputContext.Data = [PSCustomObject]@{
                UserId              = $correlatedAccount.id
                ExternalAccountName = $correlatedAccount.ExternalAccountName
                UserDescription     = $correlatedAccount.Description
                GroupId             = $correlatedAccount.ConfigurationGroup.sgroname
            }
            $outputContext.AccountReference = $correlatedAccount.id
            $outputContext.AccountCorrelated = $true

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = "Correlated account with AccountReference: [$($correlatedAccount.id)] on field [$($correlationField)] with value [$($correlationValue)]"
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
