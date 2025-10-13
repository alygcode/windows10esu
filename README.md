# Windows 10 ESU Remediation and Scripts

This repository contains PowerShell scripts for managing Windows 10 Extended Security Update (ESU) licenses in enterprise environments. These scripts are designed for use with Microsoft Intune Proactive Remediations to automate detection and activation of ESU licenses.

## Overview

Windows 10 Extended Security Updates (ESU) provide continued security updates for Windows 10 devices after the end of support. These scripts help organizations:

- **Detect** whether ESU licenses are properly installed and activated
- **Remediate** missing or inactive ESU licenses automatically
- **Monitor** ESU compliance across the organization

## Scripts

### windows10esu-discovery.ps1

**Purpose:** Detection script that checks if a Windows 10 ESU license is installed and activated.

**Functionality:**
- Queries the Windows licensing system using `slmgr.vbs`
- Checks for known ESU Activation IDs (Year 1, 2, and 3)
- Verifies the license status is "Licensed"

**Exit Codes:**
- `0` - Compliant: ESU license is installed and activated
- `1` - Non-Compliant: ESU license missing or not activated

**Supported ESU Years:**
- Year 1: `f520e45e-7413-4a34-a497-d2765967d094`
- Year 2: `1043add5-23b1-4afb-9a0f-64343c8f3f8d`
- Year 3: `83d49986-add3-41d7-ba33-87c7bfb5c0fb`

### windows10esu-remediation.ps1

**Purpose:** Remediation script that attempts to activate Windows 10 ESU licenses.

**Functionality:**
- Installs ESU product keys using `slmgr.vbs /ipk`
- Attempts activation for each configured key using `slmgr.vbs /ato`
- Handles multiple ESU years (Year 1, 2, and 3)

**Configuration Required:**
Before deploying this script, you must replace the placeholder hashtable with your actual ESU product keys. The hashtable should use the ESU Activation IDs as keys and your product keys as values:

```powershell
$ESUProductKeys = @{
    "f520e45e-7413-4a34-a497-d2765967d094" = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"  # Year 1 Product Key
    "1043add5-23b1-4afb-9a0f-64343c8f3f8d" = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"  # Year 2 Product Key
    "83d49986-add3-41d7-ba33-87c7bfb5c0fb" = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"  # Year 3 Product Key
}
```

**Note:** Replace the `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` placeholder values with your organization's actual ESU product keys for each year. Keep the Activation IDs as the keys.

## Prerequisites

- Windows 10 devices requiring ESU coverage
- Valid Windows 10 ESU product keys (purchased from Microsoft)
- Microsoft Intune with Proactive Remediations enabled (for automated deployment)
- Administrator privileges on target devices

## Deployment with Intune Proactive Remediations

1. Sign in to the Microsoft Intune admin center
2. Navigate to **Devices** > **Scripts and remediations** > **Proactive remediations**
3. Create a new remediation package:
   - **Detection script:** Upload `windows10esu-discovery.ps1`
   - **Remediation script:** Upload `windows10esu-remediation.ps1` (after configuring product keys)
4. Configure the schedule (e.g., daily checks)
5. Assign to appropriate device groups

## Manual Execution

Both scripts can be executed manually for testing:

```powershell
# Run detection script
.\windows10esu-discovery.ps1

# Run remediation script (after configuring product keys)
.\windows10esu-remediation.ps1
```

**Note:** Scripts must be run with administrator privileges.

## Security Considerations

- **Product Key Security:** ESU product keys are valuable assets. Store the remediation script securely and restrict access appropriately.
- **Intune Storage:** When deployed via Intune, scripts are stored securely in Azure and delivered to devices over encrypted connections.
- **Avoid Hard-Coding:** Consider using secure parameter passing or Azure Key Vault for production deployments instead of hard-coding keys in scripts.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Disclaimer

These scripts are provided as-is without warranty. Always test thoroughly in a non-production environment before deploying to production systems. Ensure you have valid ESU licenses from Microsoft before attempting activation.
