# Azure App Secret Expiry Alerts

This script audits Entra ID App Registrations and sends email alerts when client secrets are about to expire.

## 📁 Files

- `Notify-AppSecretExpire.ps1` – Main script that checks for secrets nearing expiration and generates an HTML report.

## 📦 Usage

You can run this script locally using parameters, or inside **Azure Automation** using pre-defined variables.

## 🧪 Example (Local Execution)

```powershell
.\Notify-AppSecretExpire.ps1 `
    -ClientId "<your-client-id>" `
    -ClientSecret "<your-client-secret>" `
    -TenantId "<your-tenant-id>" `
    -SenderEmail "noreply@yourdomain.com" `
    -ToEmail "admin@yourdomain.com" `
    -OutputPath "C:\Reports\AppSecretsExpirationReport.html" `
    -UseLocalParameters
```
## 🔐 Requirements

- Microsoft Graph App Registration with "Mail.Send","Application.Read.All", "Directory.Read.All"  permissions
- Azure Automation or PowerShell 5.1+

