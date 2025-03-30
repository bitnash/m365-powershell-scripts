<#
    .DESCRIPTION
        This PowerShell script audits all Azure AD App Registrations in your tenant and 
        identifies client secrets that are expiring within a configurable number of days (default: 30).

        Example for local execution:
        ----------------------------------------------------
        .\Notify-AppSecretExpire.ps1 `
            -ClientId "<your-client-id>" `
            -ClientSecret "<your-client-secret>" `
            -TenantId "<your-tenant-id>" `
            -WarningDays 30 `
            -SenderEmail "noreply@yourdomain.com" `
            -ToEmail "you@yourdomain.com" `
            -OutputPath "C:\Reports\AppSecretsExpirationReport.html" `
            -UseLocalParameters
        ----------------------------------------------------

    .NOTES
        AUTHOR: Marco Notarrigo
        LAST EDIT: Mar 30, 2025
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
        "Output"      { Write-Host $Message }
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

        # Delay error exit slightly so other messages can be written
        Start-Sleep -Milliseconds 200

        # Show usage as a warning or normal output
        Write-Log "Example usage:" -Level Warning
        Write-Log ".\Notify-AppSecretExpire.ps1 -ClientId <...> -ClientSecret <...> -TenantId <...> -SenderEmail <...> -ToEmail <...> -OutputPath <...> -UseLocalParameters" -Level Warning

        exit 1
    }
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

# ========= Extract Expiring Secrets =========
function Get-ExpiringAppSecrets($WarningDays,$Today) {
    try {
        $results = @()
        Write-Log "Retrieving App Registrations..." -Level Verbose
        $apps = Get-MgApplication -All

        foreach ($app in $apps) {
            $appId = $app.AppId
            $appName = $app.DisplayName
            $secrets = $app.PasswordCredentials

            # Extract notification email from Notes field (if set)
            $notifyEmail = "(not defined)"
            if ($app.Info) {
                if ($app.Info.Notes -match "NotifyEmail\s*=\s*([^\s;]+)") {
                    $notifyEmail = $matches[1]
                } elseif ($app.Notes -match "NotifyEmail\s*=\s*([^\s;]+)") {
                    $notifyEmail = $matches[1]
                }
            }

            foreach ($secret in $secrets) {
                $daysRemaining = ($secret.EndDateTime - $Today).Days

                if ($daysRemaining -le $WarningDays -and $daysRemaining -gt 0) {
                    $results += [PSCustomObject]@{
                        AppName = $appName
                        AppId = $appId
                        SecretDisplayName = $secret.DisplayName
                        ExpirationDate = $secret.EndDateTime
                        DaysRemaining = $daysRemaining
                        NotifyEmail = $notifyEmail
                    }
                }
            }
        }
        return $results
    } catch {
        Write-Log "Error extracting secrets: $_" -Level Error
        return @()
    }
}

# ========= Send Email via Microsoft Graph =========
function Send-GraphEmailReport($ToEmail,$AccessToken,$SenderEmail,$HtmlReport,$Subject) {
    try {
        $body = @{
            message = @{
                subject = $Subject
                body    = @{
                    contentType = "HTML"
                    content     = $HtmlReport
                }
                toRecipients = @(@{ emailAddress = @{ address = $ToEmail } })
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$SenderEmail/sendMail" `
            -Method POST -Headers @{ Authorization = "Bearer $AccessToken"; "Content-Type" = "application/json" } -Body $body

        Write-Log "Email report successfully sent to $ToEmail" -Level Output
    } catch {
        Write-Log "Failed to send email report: $_" -Level Error
    }
}

# ========= Main =========
try {
    Write-Log "Script starting..." -Level Output

    $token = Get-GraphAccessToken
    if (-not (Connect-ToGraph)) { throw "Graph auth failed." }

    $Today = Get-Date
    $ExpiringSecrets = Get-ExpiringAppSecrets $WarningDays $Today

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>App Secrets Expiration Report</title>
    <style>
        body { font-family: 'Segoe UI'; margin: 0; padding: 0; background: #f4f4f4; }
        .container { margin: 20px auto; padding: 20px; background: #fff; width: 95%; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #2563EB; }
        table { border-collapse: collapse; width: 100%; cursor: pointer; }
        th, td { text-align: left; padding: 10px; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        tr:hover { background-color: #f9f9f9; }
    </style>
    <script>
        document.addEventListener("DOMContentLoaded", function () {
            const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;

            const comparer = (idx, asc) => (a, b) =>
                ((v1, v2) =>
                    v1 !== "" && v2 !== "" && !isNaN(v1) && !isNaN(v2)
                        ? v1 - v2
                        : v1.toString().localeCompare(v2)
                )(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));

            document.querySelectorAll("th").forEach((th) =>
                th.addEventListener("click", () => {
                    const table = th.closest("table");
                    Array.from(table.querySelectorAll("tbody > tr"))
                        .sort(comparer(Array.from(th.parentNode.children).indexOf(th), (th.asc = !th.asc)))
                        .forEach((tr) => table.querySelector("tbody").appendChild(tr));
                })
            );
        });
    </script>
</head>
<body>
<div class='container'>
    <h1>App Secrets Expiration Report</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
    <table>
        <thead>
            <tr>
                <th>App Name</th>
                <th>App ID</th>
                <th>Secret Name</th>
                <th>Expires In</th>
                <th>Expiration Date</th>
                <th>Notify Email</th>
            </tr>
        </thead>
        <tbody>
"@

    foreach ($entry in $ExpiringSecrets) {
        $appLink = "https://portal.azure.com/?feature.msaljs=true#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/$($entry.AppId)/isMSAApp~/false"
        $secretNameLink = "<a href='$appLink' target='_blank'>$($entry.SecretDisplayName)</a>"

        $html += "<tr>
            <td>$($entry.AppName)</td>
            <td>$($entry.AppId)</td>
            <td>$secretNameLink</td>
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

    $subject = "Azure App Secrets Expiring in the Next $WarningDays Days"
    Send-GraphEmailReport $ToEmail $token $SenderEmail $html $subject

    Write-Log "Script complete." -Level Output
} catch {
    $err = $_
    $message = if ($err.Exception) { $err.Exception.Message } else { $err.ToString() }
    $stack   = if ($err.ScriptStackTrace) { $err.ScriptStackTrace } else { "<no stack trace>" }

    Write-Log "Fatal error: $message`n$stack" -Level Error
}