# Disconnect any existing sessions
Disconnect-MgGraph -ErrorAction SilentlyContinue

# Required scopes
$scopes = @(
    "RoleAssignmentSchedule.ReadWrite.Directory", 
    "RoleManagement.ReadWrite.Directory", 
    "RoleAssignmentSchedule.Remove.Directory",
    "Directory.Read.All",
    "User.Read"
)

Write-Host "Connecting to Microsoft Graph with enhanced authentication..." -ForegroundColor Cyan

# Connect with interactive authentication (better for MFA)
try {
    Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Host "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verify connection and get user context
$context = Get-MgContext
Write-Host "Connected as: $($context.Account)" -ForegroundColor Green

# Force a fresh token by making a simple Graph call
try {
    $currentUser = Get-MgUser -UserId $context.Account -ErrorAction Stop
    Write-Host "User verification successful" -ForegroundColor Green
} catch {
    Write-Host "User verification failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get eligible role assignments
Write-Host "Fetching eligible role assignments..." -ForegroundColor Cyan
try {
    $eligibleRoles = Get-MgRoleManagementDirectoryRoleEligibilitySchedule `
                        -ExpandProperty RoleDefinition `
                        -All `
                        -Filter "principalId eq '$($currentUser.Id)'" `
                        -ErrorAction Stop
    
    if (-not $eligibleRoles) {
        Write-Host "No eligible roles found for your account." -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "Failed to fetch eligible roles: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Display available roles
Write-Host "`nAvailable roles for activation:" -ForegroundColor Yellow
$roleIndex = 1
$eligibleRoles | ForEach-Object {
    Write-Host "$roleIndex. $($_.RoleDefinition.DisplayName)" -ForegroundColor White
    $roleIndex++
}

# Get user selection
do {
    $selectedRoleIndex = Read-Host "`nEnter the number of the role you want to activate (1-$($eligibleRoles.Count))"
    $selectedRoleIndex = [int]$selectedRoleIndex
} while ($selectedRoleIndex -lt 1 -or $selectedRoleIndex -gt $eligibleRoles.Count)

# Get selected role information
$selectedRole = $eligibleRoles[$selectedRoleIndex - 1]
$myRole = $eligibleRoles | Where-Object {$_.RoleDefinition.DisplayName -eq $selectedRole.RoleDefinition.DisplayName}

Write-Host "`nSelected role: $($selectedRole.RoleDefinition.DisplayName)" -ForegroundColor Green

# Prepare activation request
$justification = Read-Host "Enter justification for role activation (or press Enter for default)"
if (-not $justification) {
    $justification = "Activating $($selectedRole.RoleDefinition.DisplayName) role via PowerShell script"
}

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
            Duration = "PT4H" # 4 hours
        }
    }
}

Write-Host "`nAttempting to activate role..." -ForegroundColor Cyan
Write-Host "Note: You may be prompted for additional MFA authentication." -ForegroundColor Yellow

try {
    # Force a fresh authentication token by reconnecting if needed
    $tokenExpiry = $context.TokenExpiresOn
    if ($tokenExpiry -and $tokenExpiry -lt (Get-Date).AddMinutes(5)) {
        Write-Host "Token is expiring soon, reconnecting..." -ForegroundColor Yellow
        Disconnect-MgGraph
        Connect-MgGraph -Scopes $scopes -NoWelcome
    }
    
    # Attempt role activation
    $result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorAction Stop
    
    Write-Host "`n✅ Role activation request submitted successfully!" -ForegroundColor Green
    Write-Host "Request ID: $($result.Id)" -ForegroundColor Cyan
    Write-Host "Status: $($result.Status)" -ForegroundColor Cyan
    
    # Check current active assignments
    Write-Host "`nChecking current active role assignments..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2  # Give some time for the activation to process
    
    $activeRoles = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance `
                    -ExpandProperty RoleDefinition `
                    -All `
                    -Filter "principalId eq '$($currentUser.Id)'"
    
    if ($activeRoles) {
        Write-Host "`nCurrently active roles:" -ForegroundColor Green
        $activeRoles | ForEach-Object {
            $expirationTime = if ($_.EndDateTime) { 
                $_.EndDateTime.ToString("yyyy-MM-dd HH:mm:ss UTC") 
            } else { 
                "No expiration" 
            }
            Write-Host "  ✓ $($_.RoleDefinition.DisplayName) (Expires: $expirationTime)" -ForegroundColor White
        }
    } else {
        Write-Host "No currently active role assignments found." -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "`n❌ Role activation failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Message -like "*MfaRule*") {
        Write-Host "`n🔐 MFA Authentication Required:" -ForegroundColor Yellow
        Write-Host "The role activation requires Multi-Factor Authentication." -ForegroundColor Yellow
        Write-Host "`nPossible solutions:" -ForegroundColor Cyan
        Write-Host "1. Use the Azure Portal to activate this role manually" -ForegroundColor White
        Write-Host "2. Ensure your MFA device is available and try again" -ForegroundColor White
        Write-Host "3. Contact your administrator about MFA policies" -ForegroundColor White
        Write-Host "`nAzure Portal PIM: https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/CommonMenuBlade/~/quickStart" -ForegroundColor Cyan
    }
}

Write-Host "`nScript completed." -ForegroundColor Green