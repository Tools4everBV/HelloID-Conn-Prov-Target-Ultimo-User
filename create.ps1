#############################################
# HelloID-Conn-Prov-Target-Ultimo-User-Create
#
# Version: 1.0.0
#############################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    EmployeeId          = $p.ExternalId
    UserId              = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
    ExternalAccountName = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
    UserDescription     = $p.DisplayName
    GroupId             = $p.PrimaryContract.Title.Code
}


# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

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
                APIKey               = $config.APIKey
                ApplicationElementId = $config.ApplicationElementId
            }
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }
            if ($Body) {
                Write-Verbose 'Adding body to request'
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

# Begin
try {
    if ([string]::IsNullOrEmpty($($account.UserId))) {
        throw 'Mandatory attribute [account.UserId] is empty. Please make sure it is correctly mapped'
    }
    if ([string]::IsNullOrEmpty($($account.EmployeeId))) {
        throw 'Mandatory attribute [account.EmployeeId] is empty. Please make sure it is correctly mapped'
    }

    # Mapping
    Write-Verbose 'Use mapping to determine the desired Ultimo Configuration'
    $mappingGrouped = (Import-Csv $config.mappingFilePath ) | Group-Object -Property HelloIdTitle -AsHashTable -AsString
    if ($null -eq $mappingGrouped) {
        throw 'Empty Mapping File, please check you mapping'
    }
    $mappedUltimoConfigurationName = $mappingGrouped["$($account.GroupId)"].UltimoConfiguration
    if ( $null -eq $mappedUltimoConfigurationName ) {
        throw "No Ultimo Configuration found in the mapping with [$($Account.GroupId)]"
    }


    Write-Verbose 'Validate if the Ultimo Employee Account exists.'
    try {
        $splatInvoke = @{
            uri    = "$($config.BaseUrl)/api/v1/object/Employee('$($account.EmployeeId)')"
            Method = 'GET'
        }
        $null = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false
    } catch {
        $_.Exception.Source = 'GetEmployee'
        throw $_
    }

    Write-Verbose 'Validate if the Ultimo User Account already exists.'
    try {
        $splatInvoke = @{
            uri    = "$($config.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
            Method = 'POST'
            Body   = ( @{
                    Action = 'GetUser'
                    UserId = $account.UserId
                } | ConvertTo-Json)
        }
        $currentUser = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties.UserDetails
        $userFound = $true
    } catch {
        if ($_.Exception.Message -eq "User $($account.UserId) not found.") {
            $userFound = $false
        } else {
            throw $_
        }
    }

    #Verify if a user must be either [created and correlated], [updated and correlated], [Update-Configuration] or [correlated]
    $actions = @()
    if (-not $userFound) {
        $actions += 'Create-Correlate'
    } elseif ($($config.UpdatePersonOnCorrelate) -eq $true) {
        $actions += 'Update-Correlate'
    } else {
        $actions += 'Correlate'
    }

    # Perform checks only during correlation
    if ('Update-Correlate' -in $actions) {
        $previousAccount = [PSCustomObject]@{
            ExternalAccountName = $currentUser.ExternalAccountName
            UserDescription     = $currentUser.Description
        }
        $splatCompareProperties = @{
            ReferenceObject  = @($account.PSObject.Properties)
            DifferenceObject = @($previousAccount.PSObject.Properties)
        }
        $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
        if (-not $propertiesChanged) {
            Write-Verbose 'No changes were found with the existing account, so only perform a correlation action'
            $actions = $actions -replace 'Update-Correlate' , 'Correlate'
        }
    }

    # Check if the configuration groups require an update on an existing account
    if ((('Update-Correlate' -in $actions) -or ('Correlate' -in $actions)) -and
        ($currentUser.ConfigurationGroup.sgroname -ne $mappedUltimoConfigurationName)
    ) {
        $actions += 'Update-Configuration'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Ultimo-User account for: [$($p.DisplayName)], will be executed during enforcement"
        Write-Warning "Desired Ultimo ConfigurationName [$mappedUltimoConfigurationName], will be applied during enforcement"

        if ($propertiesChanged) {
            Write-Warning "Account property(s) required to update: [$($propertiesChanged.name -join ', ')]"
        }
    }

    # Process
    if (-not($dryRun -eq $true)) {
        foreach ($action in $actions) {
            switch ($action) {
                'Create-Correlate' {
                    Write-Verbose 'Creating and correlating Ultimo-User account'
                    $account | Add-Member -NotePropertyMembers @{
                        Action = 'CreateUser'
                    }
                    $account.GroupId = $mappedUltimoConfigurationName

                    $splatInvoke['Body'] = ($account | ConvertTo-Json)
                    $newUser = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false

                    $accountReference = $newUser.properties.UserDetails.id
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Creating account was successful. AccountReference is: [$accountReference]"
                            IsError = $false
                        })

                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Set-Configuration for account was successful. Configuration is: [$mappedUltimoConfigurationName]"
                            IsError = $false
                        })
                    break
                }

                'Update-Correlate' {
                    Write-Verbose 'Updating and correlating Ultimo-User account'
                    if ('groupId' -in $account.PSObject.Properties.name ) {
                        $account.PSObject.Properties.Remove('groupId')
                    }

                    $account | Add-Member -NotePropertyMembers @{
                        Action = 'UpdateUser'
                    }
                    $splatInvoke['Body'] = ($account | ConvertTo-Json)
                    $null = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false
                    $accountReference = $currentUser.id
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Updating-Correlating account was successful. AccountReference is: [$accountReference]"
                            IsError = $false
                        })
                    break
                }

                'Correlate' {
                    Write-Verbose 'Correlating Ultimo-User account'
                    $accountReference = $currentUser.id
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Correlating account was successful. AccountReference is: [$accountReference]"
                            IsError = $false
                        })
                    break
                }

                'Update-Configuration' {
                    $configBody = @{
                        Action  = 'ChangeConfigurationGroup'
                        UserId  = $currentUser.id
                        GroupId = $mappedUltimoConfigurationName
                    }

                    $splatInvoke['Body'] = ($configBody | ConvertTo-Json)
                    $null = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false

                    $accountReference = $currentUser.id
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Update-Configuration for account was successful. Configuration is: [$mappedUltimoConfigurationName]"
                            IsError = $false
                        })
                    break
                }
            }
        }
        $success = $true
    }
} catch {
    $success = $false
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    $auditMessage = "Could not $action Ultimo-User account. Error: $($errorObj.FriendlyMessage)"
    Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

    if ($_.Exception.Source -eq 'GetEmployee') {
        $auditMessage = "Could not Create Ultimo-User account. Error: Could not find Employee account, $($errorObj.FriendlyMessage)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })

} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        AuditLogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
