# Password Expiry Alerts

This script notifies Microsoft 365 users when their password is close to expiration.

## 📁 Files

- `Notify-M365PasswordExpiry.ps1` – Main script to send email alerts using Microsoft Graph

## 📦 Usage

You can run this script locally with parameters, or inside Azure Automation with pre-defined variables.

## 🧪 Example (Local Execution)

```powershell
.$SCRIPT_NAME.ps1 -ClientId \"xxxxx\" -ClientSecret \"xxxxx\" -TenantId \"xxxxx\" -GroupId \"xxxxx\" -PasswordExpirationDays 45 -SenderEmail \"noreply@yourdomain.com\" -UseLocalParameters
```

## 🔐 Requirements

- Microsoft Graph App Registration with Mail.Send, User.Read.All, Group.Read.All permissions
- Azure Automation or PowerShell 5.1+

