# 🔐 Activate-EntraIDPIMRole.ps1 - Secure Microsoft Entra ID PIM Role Activation

**Version 1.0 - Hardened Security Edition**

This PowerShell script simplifies and secures the process of activating eligible Microsoft Entra ID (formerly Azure AD) roles via Privileged Identity Management (PIM), using Microsoft Graph with interactive MFA support.

---

## ✨ Features

### Core Functionality
- 🔒 **Least Privilege**: Uses only 3 essential Microsoft Graph scopes (reduced from 5)
- 🛡️ **Input Validation**: Comprehensive validation of all user inputs
- 📝 **Audit Logging**: Persistent JSON audit trail for compliance
- ⏱️ **Configurable Duration**: Set activation duration from 1-8 hours
- ✅ **Explicit Confirmation**: Type "ACTIVATE" to prevent accidental role activation
- 🔐 **MFA Support**: Full Multi-Factor Authentication through interactive login
- 🎨 **Enhanced UX**: Clear, color-coded feedback with visual separators

### Security Enhancements
- ✅ Minimal permission scopes following least privilege principle
- ✅ Input sanitization to prevent injection attacks
- ✅ Justification length validation (20-500 characters)
- ✅ Sensitive data protection (no Request IDs displayed)
- ✅ Comprehensive error handling with sanitized error messages
- ✅ Local audit log for security monitoring

---

## 🔧 Requirements

- **PowerShell**: 7+ recommended (5.1+ supported)
- **Microsoft.Graph Module**: Latest version  
  Install via:
```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
```

- **Permissions**: User must have eligible PIM role assignments
- **Authentication**: Interactive login with MFA capability

---

## 🚀 Usage
```powershell
.\Activate-EntraIDPIMRole.ps1
```

The script will guide you through:
1. 🔐 Authentication with Microsoft Graph
2. 📋 Eligible role selection
3. ⏱️ Duration configuration (1-8 hours, default: 4)
4. 📝 Justification entry (minimum 20 characters)
5. ✅ Explicit confirmation (type "ACTIVATE")
6. 🎯 Role activation and verification

---

## 🔐 Required Microsoft Graph Scopes

**Reduced from 5 to 3 scopes** for enhanced security:
```powershell
$scopes = @(
    "RoleAssignmentSchedule.ReadWrite.Directory",  # For self-activation
    "Directory.Read.All",                          # For reading role info
    "User.Read"                                    # For user profile
)
```

### ❌ Removed Unnecessary Scopes
- ~~`RoleManagement.ReadWrite.Directory`~~ - Not needed for self-activation
- ~~`RoleAssignmentSchedule.Remove.Directory`~~ - Not used by script

---

## 📝 Audit Logging

All activation attempts are logged to:
```
%LOCALAPPDATA%\PIMActivation\audit.log
```

**Log Format** (JSON):
```json
{
  "Timestamp": "2025-11-02T14:23:45.1234567Z",
  "User": "admin@contoso.com",
  "Role": "Global Reader",
  "Action": "Activate",
  "Status": "Success",
  "Justification": "Monthly security review and compliance audit",
  "Duration": "4 hours",
  "ErrorMessage": "",
  "ComputerName": "DESKTOP-ABC123"
}
```

---

## 📷 Terminal Output Example
```powershell
===================================================================
  PIM Role Activation Script - Secured Version 2.0
===================================================================

Connecting to Microsoft Graph...
✓ Successfully connected to Microsoft Graph
✓ Connected as: administrator@contoso.onmicrosoft.com
✓ User verification successful

Fetching eligible role assignments...
✓ Found 5 eligible role(s)

===================================================================
  Available Roles for Activation
===================================================================
1. Global Administrator
2. Exchange Administrator
3. Global Reader
4. Security Administrator
5. User Administrator

Enter the number of the role to activate (1-5): 3

Selected role: Global Reader

-------------------------------------------------------------------
Duration Configuration
-------------------------------------------------------------------
Enter activation duration in hours (1-8, default: 4): 6
✓ Duration set to: 6 hour(s)

-------------------------------------------------------------------
Justification (minimum 20 characters)
-------------------------------------------------------------------
Enter justification for role activation: Monthly security review and compliance audit
✓ Justification validated

===================================================================
  Activation Summary
===================================================================
Role:          Global Reader
Duration:      6 hour(s)
Justification: Monthly security review and compliance audit...
User:          administrator@contoso.onmicrosoft.com
===================================================================

⚠️  This will activate privileged access. Ensure you have authorization.

Type 'ACTIVATE' to confirm (case-sensitive): ACTIVATE

Attempting role activation...
Note: You may be prompted for additional MFA authentication.

✅ Role activation successful!
Status: Provisioned

Verifying active role assignments...

Currently Active Roles:
  ✓ Global Reader (Expires: 2025-11-02 20:23:45 UTC)

✓ Script completed successfully

===================================================================
  Audit log: C:\Users\Admin\AppData\Local\PIMActivation\audit.log
===================================================================
```

---

## 🔒 Security Features

### Input Validation
- **Justification**: 20-500 characters, sanitized input
- **Duration**: 1-8 hours, numeric validation
- **Role Selection**: Integer range validation

### Protection Mechanisms
- ✅ Sanitization removes potentially dangerous characters
- ✅ No Request IDs displayed (logged only)
- ✅ Error messages sanitized (GUIDs redacted)
- ✅ Explicit "ACTIVATE" confirmation required
- ✅ Audit trail for compliance monitoring

### Least Privilege
- Uses minimal Graph API permissions
- Self-activation only (no admin override)
- Read-only access to directory information

---

## 🛠️ Troubleshooting

### MFA Authentication Required
If you see:
```
🔐 Multi-Factor Authentication Required
```

**Solutions:**
1. Use Azure Portal for full MFA flow: [PIM Portal](https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/CommonMenuBlade/~/quickStart)
2. Ensure MFA device is available and retry
3. Contact administrator if issues persist

### Permission Issues
If activation fails with "Forbidden" or "Unauthorized":
- Verify you have eligible PIM role assignment
- Check with administrator for proper PIM configuration
- Review audit log for detailed error information

### Token Expiration
The script automatically handles token refresh. If issues persist:
```powershell
Disconnect-MgGraph
.\Activate-EntraIDPIMRole.ps1
```

---

## 📊 Changelog

### Version 2.0 (Security Hardened)
- 🔒 Reduced scope permissions from 5 to 3 (40% reduction)
- ✅ Added comprehensive input validation
- 📝 Implemented audit logging system
- ⏱️ Added configurable activation duration
- 🛡️ Input sanitization for injection prevention
- ✅ Explicit confirmation requirement
- 🎨 Enhanced UI with visual separators
- 🔐 Sensitive data protection (no Request IDs)
- 📋 Detailed error handling and guidance

### Version 1.0 (Original)
- Basic PIM role activation
- Interactive MFA support
- Role selection interface

---

## 📄 License

MIT License - Feel free to use and modify

---

## 🤝 Contributing

Contributions welcome! Please ensure:
- Security best practices are maintained
- Input validation is preserved
- Audit logging functionality remains intact
- Code follows existing style conventions

---

## ⚠️ Disclaimer

This script activates privileged roles in your Microsoft Entra ID tenant. Always:
- ✅ Obtain proper authorization before use
- ✅ Follow your organization's security policies
- ✅ Review audit logs regularly
- ✅ Use minimum required duration
- ✅ Provide clear justification for each activation

**Use at your own risk. Test in non-production environments first.**

---

## 📚 Resources

- [Microsoft Entra PIM Documentation](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/)
- [Azure AD PIM Best Practices](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-deployment-plan)

---

**Made with 🛡️ by focusing on security and usability**
