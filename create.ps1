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
                APIKey               = $actionContext.Configuration.APIKey
                ApplicationElementId = $actionContext.Configuration.ApplicationElementId
            }
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }
            if ($Body) {
                $splatParams['Body'] = $Body
            }
            $response = Invoke-RestMethod @splatParams -Verbose:$false
            if ( $response.properties.ResponseSummary.Succes -eq $false) {
                throw  $response.properties.ResponseSummary.Message
            }
            Write-Output $response
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Resolve-Ultimo-UserError {
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
        try {
            if ($ErrorObject.ErrorDetails) {
                $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
                $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails
                $webResponse = $true
            } elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not([string]::IsNullOrWhiteSpace($streamReaderResponse))) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                    $httpErrorObj.FriendlyMessage = $streamReaderResponse
                    $webResponse = $true
                }
            }
            if ($webResponse ) {
                $responseObject = $httpErrorObj.ErrorDetails | ConvertFrom-Json
                $httpErrorObj.FriendlyMessage = $responseObject.Message
            }
        } catch {
            $httpErrorObj.FriendlyMessage = "Received an unexpected response. The JSON could not be converted, error: [$($_.Exception.Message)]. Original error from web service: [$($ErrorObject.ErrorDetails)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    if ([string]::IsNullOrEmpty($($actionContext.Data.EmployeeId))) {
        throw 'Mandatory attribute [account.EmployeeId] is empty. Please make sure it is correctly mapped'
    }

    Write-Information 'Use mapping to determine the desired Ultimo Configuration'
    $mappingGrouped = (Import-Csv $actionContext.Configuration.mappingFilePath ) | Group-Object -Property HelloIdTitle -AsHashTable -AsString
    if ($null -eq $mappingGrouped) {
        throw 'Empty Mapping File, please check you mapping'
    }
    $mappedUltimoConfigurationName = $mappingGrouped["$($actionContext.Data.GroupId)"].UltimoConfiguration
    if ( $null -eq $mappedUltimoConfigurationName ) {
        throw "No Ultimo Configuration found in the mapping with [$($actionContext.Data.GroupId)]"
    }

    Write-Information 'Validate if the Ultimo Employee Account exists.'
    try {
        $splatInvoke = @{
            uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/object/Employee('$($actionContext.Data.EmployeeId)')"
            Method = 'GET'
        }
        $null = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false
    } catch {
        $_.Exception.Source = 'GetEmployee'
        throw $_
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Verify if a user must be either [created ] or just [correlated]
        Write-Information 'Validate if the Ultimo User Account already exists.'
        try {
            $splatInvoke = @{
                uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                Method = 'POST'
                Body   = ( @{
                        Action = 'GetUser'
                        UserId = $correlationValue
                    } | ConvertTo-Json)
            }
            $correlatedAccount = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties.UserDetails
        } catch {
            if ($_.Exception.Message -ne "User $($actionContext.Data.UserId) not found.") {
                throw $_
            }
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Ultimo-User account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
        Write-Information "Desired Ultimo ConfigurationName [$mappedUltimoConfigurationName], will be applied during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Information 'Creating and correlating Ultimo-User account'
                $actionContext.Data | Add-Member -NotePropertyMembers @{
                    Action = 'CreateUser'
                }
                $actionContext.Data.GroupId = $mappedUltimoConfigurationName

                $splatInvoke['Body'] = ($actionContext.Data | ConvertTo-Json)
                $createdAccount = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false


                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.Properties.UserDetails.id

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Creating account was successful. AccountReference is: [$($outputContext.AccountReference)]"
                        IsError = $false
                    })

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Set-Configuration for account was successful. Configuration is: [$mappedUltimoConfigurationName]"
                        IsError = $false
                    })

                break
            }
            'CorrelateAccount' {
                Write-Information 'Correlating Ultimo-User account'

                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.id
                $outputContext.AccountCorrelated = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Correlated account: [$($correlatedAccount.id)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                        IsError = $false
                    })
                break
            }
        }
    }
    $outputContext.success = $true
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    $auditMessage = "Could not create or correlate Ultimo-User account. Error: $($errorObj.FriendlyMessage)"
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

    if ($_.Exception.Source -eq 'GetEmployee') {
        $auditMessage = "Could not Create Ultimo-User account. Error: Could not find Employee account, $($errorObj.FriendlyMessage)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
