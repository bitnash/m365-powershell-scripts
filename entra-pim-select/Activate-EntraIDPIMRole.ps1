# ==============================================================================
# PIM Role Activation Script - Secured Version
# Version: 1.0
# Security: Hardened with least privilege, input validation, and audit logging
# ==============================================================================

# Disconnect any existing sessions
Disconnect-MgGraph -ErrorAction SilentlyContinue

# Required scopes - MINIMIZED (Least Privilege Principle)
$scopes = @(
"RoleAssignmentSchedule.ReadWrite.Directory",  # For self-activation only
"Directory.Read.All",                          # For reading role information
"User.Read"                                     # For reading user profile
)

# Configuration
$maxDurationHours = 8
$minDurationHours = 1
$defaultDurationHours = 4
$minJustificationLength = 20
$maxJustificationLength = 500
$logDirectory = "$env:LOCALAPPDATA\PIMActivation"

# Initialize logging
function Initialize-AuditLog {
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}
}

function Write-AuditLog {
param(
    [string]$User,
    [string]$Role,
    [string]$Action,
    [string]$Status,
    [string]$Justification = "",
    [string]$Duration = "",
    [string]$ErrorMessage = ""
)

$logPath = Join-Path $logDirectory "audit.log"
$logEntry = [PSCustomObject]@{
    Timestamp = Get-Date -Format "o"
    User = $User
    Role = $Role
    Action = $Action
    Status = $Status
    Justification = $Justification
    Duration = $Duration
    ErrorMessage = $ErrorMessage
    ComputerName = $env:COMPUTERNAME
} | ConvertTo-Json -Compress

Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
}

function Sanitize-Input {
param([string]$InputString)  

# Remove potentially dangerous characters, keep alphanumeric, spaces, and basic punctuation
$sanitized = $InputString -replace '[^\w\s\.\-,;:()\[\]\/]', ''
return $sanitized.Trim()
}

# Initialize logging
Initialize-AuditLog

Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "  PIM Role Activation Script - Secured Version 2.0" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host ""

# Connect with interactive authentication
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
Write-Host "✓ Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
Write-Host "✗ Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
Write-AuditLog -User "Unknown" -Role "N/A" -Action "Connect" -Status "Failed" -ErrorMessage $_.Exception.Message
exit 1
}

# Verify connection and get user context
$context = Get-MgContext
Write-Host "✓ Connected as: $($context.Account)" -ForegroundColor Green

try {
$currentUser = Get-MgUser -UserId $context.Account -ErrorAction Stop
Write-Host "✓ User verification successful" -ForegroundColor Green
} catch {
Write-Host "✗ User verification failed: $($_.Exception.Message)" -ForegroundColor Red
Write-AuditLog -User $context.Account -Role "N/A" -Action "Verify" -Status "Failed" -ErrorMessage $_.Exception.Message
exit 1
}

# Get eligible role assignments
Write-Host "`nFetching eligible role assignments..." -ForegroundColor Cyan
try {
$eligibleRoles = Get-MgRoleManagementDirectoryRoleEligibilitySchedule `
                    -ExpandProperty RoleDefinition `
                    -All `
                    -Filter "principalId eq '$($currentUser.Id)'" `
                    -ErrorAction Stop

if (-not $eligibleRoles) {
    Write-Host "No eligible roles found for your account." -ForegroundColor Yellow
    Write-AuditLog -User $context.Account -Role "N/A" -Action "Query" -Status "NoRolesFound"
    exit 0
}

Write-Host "✓ Found $($eligibleRoles.Count) eligible role(s)" -ForegroundColor Green
} catch {
Write-Host "✗ Failed to fetch eligible roles: $($_.Exception.Message)" -ForegroundColor Red
Write-AuditLog -User $context.Account -Role "N/A" -Action "Query" -Status "Failed" -ErrorMessage $_.Exception.Message
exit 1
}

# Display available roles
Write-Host "`n===================================================================" -ForegroundColor Yellow
Write-Host "  Available Roles for Activation" -ForegroundColor Yellow
Write-Host "===================================================================" -ForegroundColor Yellow
$roleIndex = 1
$eligibleRoles | ForEach-Object {
Write-Host "$roleIndex. $($_.RoleDefinition.DisplayName)" -ForegroundColor White
$roleIndex++
}

# Get user selection with validation
do {
Write-Host ""
$selectedRoleInput = Read-Host "Enter the number of the role to activate (1-$($eligibleRoles.Count))"

if ($selectedRoleInput -match '^\d+$') {
    $selectedRoleIndex = [int]$selectedRoleInput
    if ($selectedRoleIndex -ge 1 -and $selectedRoleIndex -le $eligibleRoles.Count) {
        break
    }
}
Write-Host "✗ Invalid selection. Please enter a number between 1 and $($eligibleRoles.Count)" -ForegroundColor Red
} while ($true)

# Get selected role information
$selectedRole = $eligibleRoles[$selectedRoleIndex - 1]
$myRole = $eligibleRoles | Where-Object {$_.RoleDefinition.DisplayName -eq $selectedRole.RoleDefinition.DisplayName}

Write-Host "`nSelected role: $($selectedRole.RoleDefinition.DisplayName)" -ForegroundColor Green

# Get and validate duration
Write-Host "`n-------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Duration Configuration" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------------" -ForegroundColor Cyan
do {
$durationInput = Read-Host "Enter activation duration in hours ($minDurationHours-$maxDurationHours, default: $defaultDurationHours)"

if ([string]::IsNullOrWhiteSpace($durationInput)) {
    $duration = $defaultDurationHours
    break
}

if ($durationInput -match '^\d+$') {
    $duration = [int]$durationInput
    if ($duration -ge $minDurationHours -and $duration -le $maxDurationHours) {
        break
    }
}
Write-Host "✗ Invalid duration. Please enter a number between $minDurationHours and $maxDurationHours" -ForegroundColor Red
} while ($true)

$durationISO = "PT${duration}H"
Write-Host "✓ Duration set to: $duration hour(s)" -ForegroundColor Green

# Get and validate justification
Write-Host "`n-------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Justification (minimum $minJustificationLength characters)" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------------" -ForegroundColor Cyan
do {
$justification = Read-Host "Enter justification for role activation"

if ([string]::IsNullOrWhiteSpace($justification)) {
    Write-Host "✗ Justification cannot be empty" -ForegroundColor Red
    continue
}

$justification = Sanitize-Input $justification

if ($justification.Length -lt $minJustificationLength) {
    Write-Host "✗ Justification too short. Minimum $minJustificationLength characters required (current: $($justification.Length))" -ForegroundColor Red
    continue
}

if ($justification.Length -gt $maxJustificationLength) {
    Write-Host "✗ Justification too long. Maximum $maxJustificationLength characters allowed" -ForegroundColor Red
    continue
}

break
} while ($true)

Write-Host "✓ Justification validated" -ForegroundColor Green

# Display summary and request confirmation
Write-Host "`n===================================================================" -ForegroundColor Yellow
Write-Host "  Activation Summary" -ForegroundColor Yellow
Write-Host "===================================================================" -ForegroundColor Yellow
Write-Host "Role:          $($selectedRole.RoleDefinition.DisplayName)" -ForegroundColor White
Write-Host "Duration:      $duration hour(s)" -ForegroundColor White
Write-Host "Justification: $($justification.Substring(0, [Math]::Min(50, $justification.Length)))..." -ForegroundColor White
Write-Host "User:          $($context.Account)" -ForegroundColor White
Write-Host "===================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  This will activate privileged access. Ensure you have authorization." -ForegroundColor Yellow
Write-Host ""

# Explicit confirmation
$confirmation = Read-Host "Type 'ACTIVATE' to confirm (case-sensitive)"
if ($confirmation -cne "ACTIVATE") {
Write-Host "`n✗ Activation cancelled by user" -ForegroundColor Red
Write-AuditLog -User $context.Account -Role $selectedRole.RoleDefinition.DisplayName -Action "Activate" -Status "Cancelled"
exit 0
}

# Prepare activation request
$params = @{
Action = "selfActivate"
PrincipalId = $myRole.PrincipalId
RoleDefinitionId = $myRole.RoleDefinitionId
DirectoryScopeId = $myRole.DirectoryScopeId
Justification = $justification
ScheduleInfo = @{
    StartDateTime = (Get-Date).ToUniversalTime()
    Expiration = @{
        Type = "AfterDuration"
        Duration = $durationISO
    }
}
}

Write-Host "`nAttempting role activation..." -ForegroundColor Cyan
Write-Host "Note: You may be prompted for additional MFA authentication." -ForegroundColor Yellow

try {
# Check token expiry and reconnect if needed
$tokenExpiry = $context.TokenExpiresOn
if ($tokenExpiry -and $tokenExpiry -lt (Get-Date).AddMinutes(5)) {
    Write-Host "Token expiring soon, refreshing connection..." -ForegroundColor Yellow
    Disconnect-MgGraph
    Connect-MgGraph -Scopes $scopes -NoWelcome
}

# Attempt role activation
$result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorAction Stop

Write-Host "`n✅ Role activation successful!" -ForegroundColor Green
Write-Host "Status: $($result.Status)" -ForegroundColor Cyan

# Log success (without sensitive Request ID)
Write-AuditLog -User $context.Account `
            -Role $selectedRole.RoleDefinition.DisplayName `
            -Action "Activate" `
            -Status "Success" `
            -Justification $justification `
            -Duration "$duration hours"

# Check current active assignments
Write-Host "`nVerifying active role assignments..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

$activeRoles = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance `
                -ExpandProperty RoleDefinition `
                -All `
                -Filter "principalId eq '$($currentUser.Id)'"

if ($activeRoles) {
    Write-Host "`nCurrently Active Roles:" -ForegroundColor Green
    $activeRoles | ForEach-Object {
        $expirationTime = if ($_.EndDateTime) { 
            $_.EndDateTime.ToString("yyyy-MM-dd HH:mm:ss UTC") 
        } else { 
            "Permanent" 
        }
        Write-Host "  ✓ $($_.RoleDefinition.DisplayName) (Expires: $expirationTime)" -ForegroundColor White
    }
} else {
    Write-Host "⚠️  No active role assignments found yet. Activation may still be processing." -ForegroundColor Yellow
}

Write-Host "`n✓ Script completed successfully" -ForegroundColor Green

} catch {
Write-Host "`n✗ Role activation failed!" -ForegroundColor Red

# Log failure (sanitized error message)
$sanitizedError = $_.Exception.Message -replace '\b[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\b', '[GUID]'

Write-AuditLog -User $context.Account `
            -Role $selectedRole.RoleDefinition.DisplayName `
            -Action "Activate" `
            -Status "Failed" `
            -Justification $justification `
            -Duration "$duration hours" `
            -ErrorMessage $sanitizedError

if ($_.Exception.Message -like "*MfaRule*") {
    Write-Host "`n🔐 Multi-Factor Authentication Required" -ForegroundColor Yellow
    Write-Host "-------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "This role requires additional MFA authentication." -ForegroundColor White
    Write-Host "`nAlternative Options:" -ForegroundColor Cyan
    Write-Host "1. Activate via Azure Portal (supports full MFA flow)" -ForegroundColor White
    Write-Host "2. Ensure your MFA device is available and retry" -ForegroundColor White
    Write-Host "3. Contact your administrator if issues persist" -ForegroundColor White
    Write-Host "`nAzure Portal PIM:" -ForegroundColor Cyan
    Write-Host "https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/CommonMenuBlade/~/quickStart" -ForegroundColor White
} elseif ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Unauthorized*") {
    Write-Host "`n⚠️  Permission Issue Detected" -ForegroundColor Yellow
    Write-Host "-------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "You may not have permission to activate this role." -ForegroundColor White
    Write-Host "Contact your administrator to verify your PIM eligibility." -ForegroundColor White
} else {
    Write-Host "`nError details have been logged for troubleshooting." -ForegroundColor Yellow
}

exit 1
}

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "  Audit log: $logDirectory\audit.log" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
