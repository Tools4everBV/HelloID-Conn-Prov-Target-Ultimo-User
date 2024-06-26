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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }


    Write-Information 'Use mapping to determine the desired Ultimo Configuration'
    $mappingGrouped = (Import-Csv $actionContext.Configuration.mappingFilePath ) | Group-Object -Property HelloIdTitle -AsHashTable -AsString
    if ($null -eq $mappingGrouped) {
        throw 'Empty Mapping File, please check you mapping'
    }

    if ([string]::IsNullOrEmpty($actionContext.Data.GroupId)) {
        throw 'No GroupId Specified in the FieldMapping. This is required for the UltimoConfiguration Mapping'
    }

    $mappedUltimoConfigurationName = $mappingGrouped["$($actionContext.Data.GroupId)"].UltimoConfiguration
    if ( $null -eq $mappedUltimoConfigurationName ) {
        throw "No Ultimo Configuration found in the mapping with [$($actionContext.Data.GroupId)]"
    }
    $actionContext.Data.GroupId = $mappedUltimoConfigurationName

    Write-Information "Verifying if a Ultimo-User account for [$($personContext.Person.DisplayName)] exists"
    try {
        $splatInvoke = @{
            uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
            Method = 'POST'
            Body   = ( @{
                    Action = 'GetUser'
                    UserId = $actionContext.References.Account
                } | ConvertTo-Json)
        }
        $correlatedAccount = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties.UserDetails
    } catch {
        if ($_.Exception.Message -ne "User $($actionContext.References.Account) not found.") {
            throw $_
        }
    }
    # Making sure PreviousData object match ActionContext.Data
    $outputContext.PreviousData = $correlatedAccount | Select-Object * , @{Name = 'UserDescription'; Expression = { $_.Description } }
    $outputContext.PreviousData | Add-Member -NotePropertyMembers @{
        groupId = $correlatedAccount.ConfigurationGroup.sgroname
    }
    # Always compare the account against the current account in target system
    # Custom compare object to compare because the inconsistency between request en response
    $currentAccount = [PSCustomObject]@{
        ExternalAccountName = $correlatedAccount.ExternalAccountName
        UserDescription     = $correlatedAccount.Description
    }

    $actionList = @()
    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($actionContext.Data.PSObject.Properties)
            DifferenceObject = @($currentAccount.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $actionList += 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        } else {
            $actionList += 'NoChanges'
            $dryRunMessage += 'No changes will be made to the account during enforcement'
        }
    } else {
        $actionList += 'NotFound'
        $dryRunMessage += "Ultimo-User account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }


    if ($correlatedAccount.ConfigurationGroup.sgroname -ne $mappedUltimoConfigurationName -and ('NotFound' -notin $actionList)) {
        $actionList += 'Update-Configuration'
    }


    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        foreach ($action in $actionList) {
            switch ($action) {
                'UpdateAccount' {
                    Write-Information "Updating Ultimo-User account with accountReference: [$($actionContext.References.Account)]"
                    if ('groupId' -in $actionContext.Data.PSObject.Properties.name ) {
                        $actionContext.Data.PSObject.Properties.Remove('groupId')
                    }
                    $actionContext.Data | Add-Member -NotePropertyMembers @{
                        Action = 'UpdateUser'
                        UserId = $actionContext.References.Account
                    } -Force
                    $splatInvoke['Body'] = ($actionContext.Data | ConvertTo-Json)
                    $null = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                            IsError = $false
                        })
                    break
                }

                'Update-Configuration' {
                    $configBody = @{
                        Action  = 'ChangeConfigurationGroup'
                        UserId  = $actionContext.References.Account
                        GroupId = $mappedUltimoConfigurationName
                    }
                    $splatInvoke['Body'] = ($configBody | ConvertTo-Json)
                    $null = Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Update-Configuration for account was successful. Configuration is: [$mappedUltimoConfigurationName]"
                            IsError = $false
                        })
                    break
                }

                'NoChanges' {
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "No changes to Ultimo-User account with accountReference: [$($actionContext.References.Account)]"
                            IsError = $false
                        })
                    Write-Information "No changes to Ultimo-User account with accountReference: [$($actionContext.References.Account)]"
                    break
                }

                'NotFound' {
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Ultimo-User account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                            IsError = $true
                        })
                    break
                }
            }
        }
    }
    if (-not ($outputContext.AuditLogs.isError -contains $true)) {
        $outputContext.Success = $true
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Could not update Ultimo-User account. Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })
}
