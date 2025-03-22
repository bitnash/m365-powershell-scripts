<#
    .DESCRIPTION
        This script checks Microsoft 365 users from a dynamic group,
        and notifies them if their password expires within X days.
        Works in both Azure Automation and locally.

        Example for local execution:
        ----------------------------------------------------
        .\YourScriptName.ps1 `
            -ClientId "your-client-id" `
            -ClientSecret "your-client-secret" `
            -TenantId "your-tenant-id" `
            -GroupId "your-group-id" `
            -PasswordExpirationDays xx `
            -SenderEmail "you@domain.com" `
            -UseLocalParameters
        ----------------------------------------------------

    .NOTES
        AUTHOR: Marco Notarrigo
        LAST EDIT: Mar 22, 2025
#>

param (
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$TenantId,
    [string]$GroupId,
    [int]$PasswordExpirationDays,
    [string]$SenderEmail,
    [switch]$UseLocalParameters
)

# ========= Helper: Smart Logger =========
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("Output", "Error", "Warning", "Verbose", "Information")]
        [string]$Level = "Output"
    )
    $isAzure = -not $UseLocalParameters.IsPresent
    if ($Level -eq "Verbose" -and $isAzure) { $VerbosePreference = "Continue" }

    switch ($Level) {
        "Output"      { Write-Output $Message }
        "Error"       { Write-Error $Message }
        "Warning"     { Write-Warning $Message }
        "Verbose"     { Write-Verbose $Message }
        "Information" { if ($PSVersionTable.PSVersion.Major -ge 5) { Write-Information $Message } else { Write-Output "[INFO] $Message" } }
    }
}

# ========= Load Automation Vars if not local =========
if (-not $UseLocalParameters) {
    $ClientId              = Get-AutomationVariable -Name 'ClientID'
    $ClientSecret          = Get-AutomationVariable -Name 'ClientSecret'
    $TenantId              = Get-AutomationVariable -Name 'TenantID'
    $GroupId               = Get-AutomationVariable -Name 'GroupId'
    $PasswordExpirationDays= Get-AutomationVariable -Name 'PasswordExpirationDays'
    $SenderEmail           = Get-AutomationVariable -Name 'SenderEmail'
}

# ========= Token: Microsoft Graph =========
function Get-GraphAccessToken {
    try {
        $body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
        }
        return (Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body).access_token
    } catch {
        Write-Log "Token error: $_" -Level Error
        throw $_
    }
}

# ========= Connect to Graph =========
function Connect-ToGraph {
    try {
        $secureCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, (ConvertTo-SecureString $ClientSecret -AsPlainText -Force)
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $secureCred -NoWelcome
        return $true
    } catch {
        Write-Log "Graph connection failed: $_" -Level Error
        return $false
    }
}

# ========= Utility =========
function Mask-UPN ($upn) {
    if ($upn -match "^(.{2})(.*)(@.*)$") { return "$($matches[1])$($matches[2] -replace '.', '*')$($matches[3])" }
    return "Invalid UPN"
}

# ========= Get Group Members =========
function Get-GroupUsers ($GroupId) {
    try {
        $users = Get-MgGroupMember -GroupId $GroupId -All | Where-Object { $_.UserPrincipalName } | Select-Object Id, UserPrincipalName
        if (-not $users) { Write-Log "Group is empty or fetch failed." -Level Warning }
        return ,$users
    } catch {
        Write-Log "Failed to retrieve users: $_" -Level Error
        return @()
    }
}

# ========= Get User Info =========
function Get-UserDetails ($Id) {
    try {
        Get-MgUser -UserId $Id -Property DisplayName, UserPrincipalName, LastPasswordChangeDateTime |
            Select-Object DisplayName, UserPrincipalName, LastPasswordChangeDateTime
    } catch {
        Write-Log "Failed user lookup for $Id: $_" -Level Error
        return $null
    }
}

# ========= Send Email =========
function Send-EmailNotification ($User, $DaysRemaining, $AccessToken, $SenderEmail) {
    try {
        $body = @{
            message = @{
                subject = "Your Microsoft 365 Password is Expiring Soon!"
                body    = @{
                    contentType = "HTML"
                    content     = "Hello $($User.DisplayName),<br><br>Your password will expire in $DaysRemaining days. Please update it.<br>"
                }
                toRecipients = @(@{ emailAddress = @{ address = $User.UserPrincipalName } })
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$SenderEmail/sendMail" `
            -Method POST -Headers @{ Authorization = "Bearer $AccessToken"; "Content-Type" = "application/json" } -Body $body

        Write-Log "Email sent to $(Mask-UPN $User.UserPrincipalName)" -Level Output
    } catch {
        Write-Log "Email failure for $(Mask-UPN $User.UserPrincipalName): $_" -Level Error
    }
}

# ========= Main =========
try {
    $token = Get-GraphAccessToken
    if (-not (Connect-ToGraph)) { throw "Graph auth failed." }

    $users = Get-GroupUsers $GroupId
    if ($users.Count -eq 0) { throw "No users to process." }

    foreach ($user in $users) {
        $details = Get-UserDetails $user.Id
        if (-not $details -or -not $details.LastPasswordChangeDateTime) {
            Write-Log "No password date for $(Mask-UPN $details.UserPrincipalName)" -Level Warning
            continue
        }

        $expiry = $details.LastPasswordChangeDateTime.AddDays($PasswordExpirationDays)
        $remaining = ($expiry - (Get-Date)).Days

        Write-Log "User: $(Mask-UPN $details.UserPrincipalName) | Days remaining: $remaining" -Level Output

        if ($remaining -le 7 -and $remaining -ge 0) {
            Write-Log "Sending alert..." -Level Verbose
            # Send-EmailNotification -User $details -DaysRemaining $remaining -AccessToken $token -SenderEmail $SenderEmail
        }
    }

    Disconnect-MgGraph | Out-Null
    Write-Log "Script complete." -Level Output
} catch {
    Write-Log "Fatal error: $_" -Level Error
}
