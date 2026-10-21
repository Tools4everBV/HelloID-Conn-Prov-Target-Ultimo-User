#################################################
# HelloID-Conn-Prov-Target-Ultimo-User-RevokePermission-Group
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
    if ($null -eq $correlatedAccount) {
        $action = 'NotFound'
    }
    elseif ($actionContext.References.Permission.Reference -notin $correlatedAccount.AuthorizationGroups.sgrousegroid) {
        $action = 'AlreadyRevoked'
    }
    else {
        $action = 'RevokePermission'
    }
    Write-Information "Determined action: $($action)"

    # Process
    switch ($action) {
        'RevokePermission' {
            $actionMessage = "revoking permission [$($actionContext.PermissionDisplayName)] with reference [$($actionContext.References.Permission.Reference)] from account with AccountReference: [$($actionContext.References.Account)]"

            $revokePermissionSplatParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
                Method = 'POST'
                Body   = (@{
                        Action  = 'RevokeAuthorizationGroup'
                        UserId  = $actionContext.References.Account
                        GroupId = $actionContext.References.Permission.Reference
                    } | ConvertTo-Json)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-UltimoUserRestMethod @revokePermissionSplatParams

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'RevokePermission'
                        Message = "Revoked permission [$($actionContext.PermissionDisplayName)] with reference [$($actionContext.References.Permission.Reference)] from account with AccountReference: [$($actionContext.References.Account)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would revoke permission [$($actionContext.PermissionDisplayName)] with reference [$($actionContext.References.Permission.Reference)] from account with AccountReference: [$($actionContext.References.Account)]"
            }
            break
        }

        'AlreadyRevoked' {
            $actionMessage = "revoking permission [$($actionContext.PermissionDisplayName)] from account with AccountReference: [$($actionContext.References.Account)]"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'RevokePermission'
                    Message = "Permission [$($actionContext.PermissionDisplayName)] with reference [$($actionContext.References.Permission.Reference)] is already revoked from account with AccountReference: [$($actionContext.References.Account)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            $actionMessage = "revoking permission [$($actionContext.PermissionDisplayName)] from account with AccountReference: [$($actionContext.References.Account)]"

            # Nothing to revoke when the account no longer exists, so this is not treated as an error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'RevokePermission'
                    Message = "Account with AccountReference: [$($actionContext.References.Account)] for person [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
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
