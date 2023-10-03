#############################################
# HelloID-Conn-Prov-Target-Ultimo-User-Enable
#
# Version: 1.0.0
#############################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

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

    Write-Verbose "Verifying if a Ultimo-User account for [$($p.DisplayName)] exists"
    $splatInvoke = @{
        uri    = "$($config.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
        Method = 'POST'
        Body   = ( @{
                Action = 'GetUser'
                UserId = $aRef
            } | ConvertTo-Json)
    }
    $currentUser = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false).properties.UserDetails

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] Enable Ultimo-User account for: [$($p.DisplayName)] will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        Write-Verbose "Enabling Ultimo-User account with accountReference: [$aRef]"
        $splatInvoke['Body'] = @{
            Action          = 'UpdateUser'
            UserDescription = $currentUser.Description
            UserId          = $aRef
            EnableAccount   = $true
        } | ConvertTo-Json
        $null = (Invoke-UltimoUserRestMethod @splatInvoke -Verbose:$false)
    }

    $success = $true
    $auditLogs.Add([PSCustomObject]@{
            Message = 'Enable account was successful'
            IsError = $false
        })

} catch {
    $success = $false
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    $auditMessage = "Could not enable Ultimo-User account. Error: $($errorObj.FriendlyMessage)"
    Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
