# 🔐 PIMSelect.ps1 - Automate Microsoft Entra ID (formerly Azure AD) PIM Role Activation

This PowerShell script simplifies the process of activating eligible Microsoft Entra ID (formerly Azure AD) roles via Privileged Identity Management (PIM), using Microsoft Graph with interactive MFA support.

---

## ✨ Features

- Connects securely to Microsoft Graph using required scopes.
- Supports Multi-Factor Authentication (MFA) through interactive login.
- Retrieves the current user’s context.
- Lists and activates eligible PIM roles.
- Interactive role selection if multiple roles are available.
- Provides clear, color-coded feedback.
- Gracefully handles errors and token expiration.

---

## 🔧 Requirements

- PowerShell 7+
- Microsoft.Graph PowerShell module  
  Install via:

  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser

---

## 🚀 Usage
```powershell
.\PIMSelect.ps1
```

---

## 🔐 Required Microsoft Graph Scopes

$scopes = @(
    "RoleAssignmentSchedule.ReadWrite.Directory",
    "RoleManagement.ReadWrite.Directory",
    "RoleAssignmentSchedule.Remove.Directory",
    "Directory.Read.All",
    "User.Read"
)

---

## 📷 Termina Output

```powershell
Connecting to Microsoft Graph with enhanced authentication...
Successfully connected to Microsoft Graph
Connected as: administrator@contoso.onmicrosoft.com
User verification successful
Fetching eligible role assignments...

Available roles for activation:
1. Global Administrator
2. Exchange Administrator
3. Global Reader
4. Security Administrator
5. User Administrator

Enter the number of the role you want to activate (1-5): 3

Selected role: Global Reader
Enter justification for role activation (or press Enter for default): Reviewing tenant-wide configuration for upcoming internal audit.

Attempting to activate role...
Note: You may be prompted for additional MFA authentication.

✅ Role activation request submitted successfully!
Request ID: 993d1ad5-b8bb-49f9-9ef0-43a6310dc080
Status: Provisioned

Checking current active role assignments...

Currently active roles:
  ✓ Global Reader (Expires: 2025-06-07 14:23:45 UTC)

Script completed.
```
