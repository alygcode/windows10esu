# windows10esu

Windows 10 ESU Remediation and Scripts

## Overview
This repository contains PowerShell scripts and helpers to assist with Extended Security Updates (ESU) related remediation and management tasks for Windows 10. The scripts are intended to detect common ESU-related issues, apply remediation steps, and provide safe options for testing before making changes.

## What this repo provides
- A set of PowerShell scripts (100% PowerShell codebase) to help with ESU detection and remediation.
- Utilities to inspect system state relevant to ESU activation and updates.
- Examples and patterns for running remediation tasks safely in test and production environments.

## Requirements
- Windows 10 with ESU eligibility (per Microsoft guidance).
- PowerShell 5.1 or PowerShell 7+.
- Administrative privileges to run scripts that change system settings or apply remediation.
- Recommended: test all changes in a VM or lab environment before applying to production systems.

## How to use
1. Open an elevated PowerShell prompt (Run as Administrator).
2. If scripts are blocked by execution policy, run:
   powershell -ExecutionPolicy Bypass -File .\YourScript.ps1
3. Use built-in help or a -WhatIf/-DryRun parameter (if available) to preview changes:
   .\YourScript.ps1 -WhatIf
4. Review script output carefully and run without -WhatIf only when you understand the changes.

Note: Script filenames and parameters vary. Use the script's header/comments and the -Help/-? options to discover available parameters.

## Safety and testing
- Always run scripts in a controlled test environment before deploying widely.
- Back up critical data and system restore points where appropriate.
- Review the script source to understand exactly what changes will be made.

## Contributing
Contributions, issues, and pull requests are welcome. When opening an issue or PR, include:
- PowerShell version and Windows build number
- Exact command you ran and the full output or error
- Steps to reproduce (if applicable)

## Support / Contact
Open an issue in this repository for support requests, bug reports, or feature suggestions.

## License
See the LICENSE file in this repository (if present) for license details. If no LICENSE file is included, assume standard GitHub default unless the owner specifies otherwise.