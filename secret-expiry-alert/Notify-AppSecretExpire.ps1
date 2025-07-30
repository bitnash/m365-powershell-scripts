<#
    .DESCRIPTION
        This PowerShell script audits all Azure AD App Registrations in your tenant and 
        identifies client secrets and certificates that are expiring within a configurable number of days (default: 30).

    .NOTES
        AUTHOR: Marco Notarrigo
        LAST EDIT: Jun 20, 2025
#>

param (
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$TenantId,
    [int]$WarningDays = 30,
    [string]$SenderEmail,
    [string]$ToEmail,
    [string]$OutputPath,
    [switch]$UseLocalParameters
)

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("Output", "Error", "Warning", "Verbose", "Information")]
        [string]$Level = "Output"
    )
    $isAzure = -not $UseLocalParameters.IsPresent
    if ($Level -eq "Verbose" -and $isAzure) { $VerbosePreference = "Continue" }

    switch ($Level) {
        "Output"      { Write-Host $Message }
        "Error"       { Write-Error $Message }
        "Warning"     { Write-Warning $Message }
        "Verbose"     { Write-Verbose $Message }
        "Information" { if ($PSVersionTable.PSVersion.Major -ge 5) { Write-Information $Message } else { Write-Output "[INFO] $Message" } }
    }
}

if (-not $UseLocalParameters) {
    $ClientId              = Get-AutomationVariable -Name 'ClientID'
    $ClientSecret          = Get-AutomationVariable -Name 'ClientSecret'
    $TenantId              = Get-AutomationVariable -Name 'TenantID'
    $WarningDays           = Get-AutomationVariable -Name 'WarningDays'
    $SenderEmail           = Get-AutomationVariable -Name 'SenderEmail'
    $ToEmail               = Get-AutomationVariable -Name 'ToEmail'    
} else {
    $missing = @()
    if (-not $ClientId)      { $missing += 'ClientId' }
    if (-not $ClientSecret)  { $missing += 'ClientSecret' }
    if (-not $TenantId)      { $missing += 'TenantId' }
    if (-not $SenderEmail)   { $missing += 'SenderEmail' }
    if (-not $ToEmail)       { $missing += 'ToEmail' }
    if (-not $OutputPath)    { $missing += 'OutputPath' }

    if ($missing.Count -gt 0) {
        $missingList = $missing -join ', '
        Write-Log "Missing required parameter(s) when running with -UseLocalParameters: $missingList" -Level Error
        Start-Sleep -Milliseconds 200
        Write-Log "Example usage:" -Level Warning
        Write-Log ".\Notify-AppSecretExpire.ps1 -ClientId <...> -ClientSecret <...> -TenantId <...> -SenderEmail <...> -ToEmail <...> -OutputPath <...> -UseLocalParameters" -Level Warning
        exit 1
    }
}

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

function Get-ExpiringAppSecrets($WarningDays, $Today) {
    $results = @()
    $apps = Get-MgApplication -All

    foreach ($app in $apps) {
        $notifyEmail = "(not defined)"
        if ($app.Info) {
            if ($app.Info.Notes -match "NotifyEmail\s*=\s*([^\s;]+)") {
                $notifyEmail = $matches[1]
            } elseif ($app.Notes -match "NotifyEmail\s*=\s*([^\s;]+)") {
                $notifyEmail = $matches[1]
            }
        }

        foreach ($secret in $app.PasswordCredentials) {
            $daysRemaining = ($secret.EndDateTime - $Today).Days
            if ($daysRemaining -le $WarningDays -and $daysRemaining -gt 0) {
                $results += [PSCustomObject]@{
                    AppName = $app.DisplayName
                    AppId = $app.AppId
                    SecretDisplayName = $secret.DisplayName
                    ExpirationDate = $secret.EndDateTime
                    DaysRemaining = $daysRemaining
                    NotifyEmail = $notifyEmail
                    Type = "Secret"
                }
            }
        }
    }
    return $results
}

function Get-ExpiringAppCertificates($WarningDays, $Today) {
    $results = @()
    $apps = Get-MgApplication -All

    foreach ($app in $apps) {
        $notifyEmail = "(not defined)"
        if ($app.Info) {
            if ($app.Info.Notes -match "NotifyEmail\s*=\s*([^\s;]+)") {
                $notifyEmail = $matches[1]
            } elseif ($app.Notes -match "NotifyEmail\s*=\s*([^\s;]+)") {
                $notifyEmail = $matches[1]
            }
        }

        foreach ($cert in $app.KeyCredentials) {
            $daysRemaining = ($cert.EndDateTime - $Today).Days
            if ($daysRemaining -le $WarningDays -and $daysRemaining -gt 0) {
                $results += [PSCustomObject]@{
                    AppName = $app.DisplayName
                    AppId = $app.AppId
                    SecretDisplayName = $cert.DisplayName
                    ExpirationDate = $cert.EndDateTime
                    DaysRemaining = $daysRemaining
                    NotifyEmail = $notifyEmail
                    Type = "Certificate"
                }
            }
        }
    }
    return $results
}

function Send-GraphEmailReport($ToEmail, $AccessToken, $SenderEmail, $HtmlReport, $Subject) {
    $body = @{
        message = @{
            subject = $Subject
            body    = @{ contentType = "HTML"; content = $HtmlReport }
            toRecipients = @(@{ emailAddress = @{ address = $ToEmail } })
        }
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$SenderEmail/sendMail" `
        -Method POST -Headers @{ Authorization = "Bearer $AccessToken"; "Content-Type" = "application/json" } -Body $body

    Write-Log "Email report successfully sent to $ToEmail" -Level Output
}

try {
    Write-Log "Script starting..." -Level Output

    $token = Get-GraphAccessToken
    if (-not (Connect-ToGraph)) { throw "Graph auth failed." }

    $Today = Get-Date
    $ExpiringSecrets = Get-ExpiringAppSecrets $WarningDays $Today
    $ExpiringCerts = Get-ExpiringAppCertificates $WarningDays $Today
    $AllExpiring = $ExpiringSecrets + $ExpiringCerts

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>App Credentials Expiration Report</title>
    <style>
        body { font-family: 'Segoe UI'; margin: 0; padding: 0; background: #f4f4f4; }
        .container { margin: 20px auto; padding: 20px; background: #fff; width: 95%; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #2563EB; }
        table { border-collapse: collapse; width: 100%; cursor: pointer; }
        th, td { text-align: left; padding: 10px; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        tr:hover { background-color: #f9f9f9; }
    </style>
</head>
<body>
<div class='container'>
    <h1>App Credentials Expiration Report</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
    <table>
        <thead>
            <tr>
                <th>App Name</th>
                <th>App ID</th>
                <th>Credential Name</th>
                <th>Type</th>
                <th>Expires In</th>
                <th>Expiration Date</th>
                <th>Notify Email</th>
            </tr>
        </thead>
        <tbody>
"@

foreach ($entry in $AllExpiring) {
    $appLink = "https://portal.azure.com/?feature.msaljs=true#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/$($entry.AppId)/isMSAApp~/false"
    $credentialName = "<a href='$appLink' target='_blank'>$($entry.SecretDisplayName)</a>"
    $html += "<tr>
        <td>$($entry.AppName)</td>
        <td>$($entry.AppId)</td>
        <td>$credentialName</td>
        <td>$($entry.Type)</td>
        <td>$($entry.DaysRemaining) days</td>
        <td>$($entry.ExpirationDate.ToString('yyyy-MM-dd'))</td>
        <td>$($entry.NotifyEmail)</td>
    </tr>"
}

$html += "</tbody></table></div></body></html>"

    if ($OutputPath) {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Log "Report saved to $OutputPath" -Level Output
    } else {
        Write-Log "OutputPath not specified. Report was not saved locally." -Level Warning
    }

    $subject = "Azure App Credentials Expiring in the Next $WarningDays Days"

    if (-not $UseLocalParameters) {
        Send-GraphEmailReport $ToEmail $token $SenderEmail $html $subject

        $AllExpiring | Where-Object { $_.NotifyEmail -ne "(not defined)" } | Group-Object NotifyEmail | ForEach-Object {
            $recipient = $_.Name
            $teamHtml = "<html><body><h1>Credentials Expiring for Your Application</h1><p><strong>Note:</strong> Contact your administrator to renew your credentials.</p><table border='1'><tr><th>App Name</th><th>App Id</th><th>Credential</th><th>Type</th><th>Days Remaining</th><th>Expiration Date</th></tr>"
            foreach ($item in $_.Group) {
                 $teamHtml += "<tr><td>$($item.AppName)</td><td>$($item.AppId)</td><td>$($item.SecretDisplayName)</td><td>$($item.Type)</td><td>$($item.DaysRemaining)</td><td>$($item.ExpirationDate.ToString('yyyy-MM-dd'))</td></tr>"
            }
            $teamHtml += "</table></body></html>"
            Send-GraphEmailReport $recipient $token $SenderEmail $teamHtml "[Warning]: Credential Expiration Alert"
        }
    } else {
        Write-Log "Local run detected. Email report not sent." -Level Information
    }

    Write-Log "Script complete." -Level Output
} catch {
    $err = $_
    $message = if ($err.Exception) { $err.Exception.Message } else { $err.ToString() }
    $stack   = if ($err.ScriptStackTrace) { $err.ScriptStackTrace } else { "<no stack trace>" }
    Write-Log "Fatal error: $message`n$stack" -Level Error
}
