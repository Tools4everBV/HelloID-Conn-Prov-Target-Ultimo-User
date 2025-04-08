############################################################
# HelloID-Conn-Prov-Target-Ultimo-User-Import
# PowerShell V2
############################################################

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
                Write-Warning ($response.properties.ResponseSummary | ConvertTo-Json)
                throw $response.properties.ResponseSummary.Message
            }
            
            return $response
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
	Write-Information 'Starting target account import'  
	
    Write-Information 'Retrieving users'
    $splatInvoke = @{
        uri    = "$($actionContext.Configuration.BaseUrl)/api/v1/action/_ExternalAuthorizationManagement"
        Method = 'POST'
        Body   = ( @{
                Action = 'GetAllUsers'
            } | ConvertTo-Json)
    }

    $getAllUserResponse = Invoke-UltimoUserRestMethod  @splatInvoke -Verbose:$false
    $existingAccounts = $getAllUserResponse.properties.AllUsers

    $existingAccounts  | Add-Member -MemberType NoteProperty -Name 'UserDescription' -Value $null
    $existingAccounts  | Add-Member -MemberType NoteProperty -Name 'UserId' -Value $null

    foreach ($account in $existingAccounts) {
        
		$enabled = $false
        if([bool]($account.PSobject.Properties.name -Contains "ActivationDateTime") -and -not([string]::IsNullOrEmpty($account.ActivationDateTime))) {
            $enabled = $true
        }
		
        $userName = $account.ExternalAccountName
        if([string]::IsNullOrEmpty($userName)){
            $userName = $account.Id
        }

        $displayname = $account.Description
        if([string]::IsNullOrEmpty($displayname)){
            $displayname = $account.Id
        }

        $account.UserDescription = $account.Description
        $account.UserId = $account.Id

        # Return the result
        Write-Output @{
            AccountReference = $account.Id
            DisplayName      = $displayname
            UserName         = $userName
            Enabled          = $enabled
            Data             = $account
        }
    }
    Write-Information 'Target account import completed'
} catch {
    $ex = $PSItem
    $errorObj = Resolve-Ultimo-UserError -ErrorObject $ex
    Write-Warning "Could not retrieve Ultimo-User users. Error: $($errorObj.FriendlyMessage)"
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
}