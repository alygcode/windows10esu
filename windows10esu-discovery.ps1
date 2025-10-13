<#
.SYNOPSIS
  Checks if Windows 10 ESU license is installed and activated.
  Returns exit code 0 if ESU is compliant, 1 if not.
  Designed for use as a detection script in Intune Proactive Remediations.
#>

# Known ESU Activation IDs (Windows 10)
$ActivationIDs = @(
    "f520e45e-7413-4a34-a497-d2765967d094", # Year 1
    "1043add5-23b1-4afb-9a0f-64343c8f3f8d", # Year 2
    "83d49986-add3-41d7-ba33-87c7bfb5c0fb"  # Year 3
)

try {
    # Retrieve license details
    $LicenseInfo = cscript.exe /nologo "$env:SystemRoot\system32\slmgr.vbs" /dlv 2>&1

    # Check for Licensed status
    $IsLicensed = $LicenseInfo | Select-String "License Status:.*Licensed"
    # Check for ESU Activation ID
    $HasESU = $LicenseInfo | Select-String ($ActivationIDs -join "|")

    if ($IsLicensed -and $HasESU) {
        Write-Host "Compliant: ESU license is installed and activated."
        exit 0
    } else {
        Write-Host "Non-Compliant: ESU license missing or not activated."
        exit 1
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}
