##################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Permissions
#
# Version: 1.0.0
##################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json

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

try {
    $splatInvoke = @{
        uri    = "$($config.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
        Method = 'POST'
        Body   = ( @{
                Action = 'GetAllAuthorizationGroups'
            } | ConvertTo-Json)
    }
    $permissions = (Invoke-UltimoUserRestMethod  @splatInvoke -Verbose:$false).properties.AllAvailableAuthorizationGroups

    foreach ($permission in  $permissions) {
        Write-Output @{
            DisplayName    = $permission.GroupName
            Identification = @{
                Reference = $permission.GroupId
            }
        } | ConvertTo-Json -Depth 10
    }
} catch {
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    Write-Warning "Could not retrieve Ultimo-User permissions. Error: $($errorObj.FriendlyMessage)"
    Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
}
