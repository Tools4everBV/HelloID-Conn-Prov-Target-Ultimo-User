#############################################
# HelloID-Conn-Prov-Target-Ultimo-User-Update
#
# Version: 1.0.0
#############################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    UserId              = $aRef
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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($aRef))) {
        throw 'The account reference could not be found'
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

    Write-Verbose "Verifying if a Ultimo-User account for [$($p.DisplayName)] exists"
    try {
        $splatInvoke = @{
            uri    = "$($config.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
            Method = 'POST'
            Body   = ( @{
                    Action = 'GetUser'
                    UserId = $aRef
                } | ConvertTo-Json)
        }
        $currentUser = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties.UserDetails
        $userFound = $true
    } catch {
        if ($_.Exception.Message -eq "User $($aRef) not found.") {
            $userFound = $false
        } else {
            throw $_
        }
    }

    # Always compare the account against the current account in target system
    # Custom compare object to compare because the inconsistency between request en response
    $currentAccount = [PSCustomObject]@{
        ExternalAccountName = $currentUser.ExternalAccountName
        UserDescription     = $currentUser.Description
    }
    $splatCompareProperties = @{
        ReferenceObject  = @($account.PSObject.Properties)
        DifferenceObject = @($currentAccount.PSObject.Properties)
    }
    $actions = @()
    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
    if ($propertiesChanged -and $userFound) {
        $actions += 'Update'
        $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ',')]"
    } elseif (-not($propertiesChanged)) {
        $actions += 'NoChanges'
        $dryRunMessage = 'No changes will be made to the account during enforcement'
    } elseif (-not $userFound) {
        $actions += 'NotFound'
        $dryRunMessage = "Ultimo-User account for: [$($p.DisplayName)] not found. Possibly deleted"
    }
    Write-Verbose $dryRunMessage

    if ($currentUser.ConfigurationGroup.sgroname -ne $mappedUltimoConfigurationName -and ('NotFound' -notin $actions)) {
        $actions += 'Update-Configuration'
    }


    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        foreach ($action in $actions) {
            switch ($action) {
                'Update' {
                    Write-Verbose "Updating Ultimo-User account with accountReference: [$aRef]"
                    if ('groupId' -in $account.PSObject.Properties.name ) {
                        $account.PSObject.Properties.Remove('groupId')
                    }
                    $account | Add-Member -NotePropertyMembers @{
                        Action = 'UpdateUser'
                    }
                    $splatInvoke['Body'] = ($account | ConvertTo-Json)
                    $null = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties

                    $success = $true
                    $auditLogs.Add([PSCustomObject]@{
                            Message = 'Update account was successful'
                            IsError = $false
                        })
                    break
                }

                'NoChanges' {
                    Write-Verbose "No changes to Ultimo-User account with accountReference: [$aRef]"

                    $success = $true
                    $auditLogs.Add([PSCustomObject]@{
                            Message = 'No changes will be made to the account during enforcement'
                            IsError = $false
                        })
                    break
                }

                'NotFound' {
                    $success = $false
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Ultimo-User account for: [$($p.DisplayName)] not found. Possibly deleted"
                            IsError = $true
                        })
                    break
                }

                'Update-Configuration' {
                    $configBody = @{
                        Action  = 'ChangeConfigurationGroup'
                        UserId  = $aRef
                        GroupId = $mappedUltimoConfigurationName
                    }
                    $splatInvoke['Body'] = ($configBody | ConvertTo-Json)
                    $null = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false

                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Update-Configuration for account was successful. Configuration is: [$mappedUltimoConfigurationName]"
                            IsError = $false
                        })
                    break
                }
            }
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    $auditMessage = "Could not update Ultimo-User account. Error: $($errorObj.FriendlyMessage)"
    Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
