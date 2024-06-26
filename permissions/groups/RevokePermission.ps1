#################################################################
# HelloID-Conn-Prov-Target-Ultimo-User-RevokePermission-Group
# PowerShell V2
#################################################################

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
# Begin
try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

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

    if ($null -ne $correlatedAccount) {
        $action = 'RevokePermission'
        $dryRunMessage = "Revoke Ultimo-User permission: [$($actionContext.References.Permission.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Ultimo-User account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'RevokePermission' {
                Write-Information "Revoking Ultimo-User permission: [$($actionContext.References.Permission.DisplayName)] - [$($actionContext.References.Permission.Reference)]"

                if ($actionContext.References.Permission.Reference -in $correlatedAccount.AuthorizationGroups.sgrousegroid) {
                    $splatInvoke['Body'] = @{
                        Action  = 'RevokeAuthorizationGroup'
                        UserId  = $actionContext.References.Account
                        GroupId = $actionContext.References.Permission.Reference
                    } | ConvertTo-Json
                    $null = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false)
                } else {
                    Write-Information "Permissions [$($actionContext.References.Permission.DisplayName)] already revoked"
                }
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Revoke permission [$($actionContext.References.Permission.DisplayName)] was successful"
                        IsError = $false
                    })
            }

            'NotFound' {
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Ultimo-User account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $false
                    })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Could not revoke Ultimo-User account. Error: $($errorObj.FriendlyMessage)"
            IsError = $true
        })
}