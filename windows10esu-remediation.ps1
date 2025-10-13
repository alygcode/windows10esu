<#
.SYNOPSIS
  Remediation script for Windows 10 ESU activation.
  Installs and activates the appropriate ESU add-on license if not already present and licensed.

.DESCRIPTION
  Designed to be used as the Remediation script in an Intune Proactive Remediation pairing with a detection script
  that exits 0 when ESU is licensed and 1 when not.

  Exit Codes:
    0 = ESU is (now) compliant (already licensed or successfully remediated)
    1 = Failed to remediate (still not licensed, or an unrecoverable error occurred)

.NOTES
  - Do NOT hardcode production MAK keys in publicly accessible code.
  - Test in a lab first.
  - Script must run elevated.
  - Supports both CIM and legacy WMI.
#>

#region Configuration (EDIT THESE SAFELY)

# Provide ESU keys in order of application (Year 1, Year 2, Year 3, etc.)
# IMPORTANT: REPLACE THE PLACEHOLDER VALUES BELOW BEFORE USE
# For KMS scenario, you may only need to supply the GVLK for the current year.
$ESUKeys = [ordered]@{
    "Year1" = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE"  # Placeholder
    "Year2" = "FFFFF-GGGGG-HHHHH-IIIII-JJJJJ"  # Placeholder
    "Year3" = "KKKKK-LLLLL-MMMMM-NNNNN-OOOOO"  # Placeholder
}

# Known ESU Activation IDs (keep in sync with detection script)
$ActivationIDs = @(
  'f520e45e-7413-4a34-a497-d2765967d094', # Year 1
  '1043add5-23b1-4afb-9a0f-64343c8f3f8d', # Year 2
  '83d49986-add3-41d7-ba33-87c7bfb5c0fb'  # Year 3
)

# Map Activation ID to year label for readability (optional helper)
$ActivationIdToYear = @{
  'f520e45e-7413-4a34-a497-d2765967d094' = 'Year1'
  '1043add5-23b1-4afb-9a0f-64343c8f3f8d' = 'Year2'
  '83d49986-add3-41d7-ba33-87c7bfb5c0fb' = 'Year3'
}

# Delay (seconds) after slmgr operations to allow licensing service to update (tune if needed)
$PostSlmgrDelaySeconds = 8

# Enable verbose logging (set to $false in production if you want quieter remediation runs)
$VerboseLogging = $true

#endregion Configuration

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('s')
    Write-Host "[$ts][$Level] $Message"
}

function Get-LicenseStatusName {
    param([int]$code)
    switch ($code) {
        0 {'Unlicensed'}
        1 {'Licensed'}
        2 {'OOBGrace'}
        3 {'OOTGrace'}
        4 {'NonGenuineGrace'}
        5 {'Notification'}
        6 {'ExtendedGrace'}
        default {"Unknown($code)"}
    }
}

function Get-SoftwareLicensingProducts {
    try {
        return Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop
    }
    catch {
        Write-Log "Get-CimInstance failed: $($_.Exception.Message). Trying legacy WMI." "WARN"
        return Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop
    }
}

function Get-EsuProducts {
    param(
        [object[]]$AllLicenses
    )
    $AllLicenses |
        Where-Object { $_.PartialProductKey } |
        Where-Object { $_.ActivationID -and ($ActivationIDs -contains $_.ActivationID.ToLower()) }
}

function Test-EsuCompliant {
    param([object[]]$EsuProducts)
    return [bool]($EsuProducts | Where-Object { $_.LicenseStatus -eq 1 })
}

function Install-EsuKey {
    param(
        [string]$KeyLabel,
        [string]$ProductKey
    )
    # Basic validation
    if (-not $ProductKey -or $ProductKey -match '^[A-Z]{5}-B{5}-C{5}-D{5}-E{5}$') {
        # Still the placeholder? (very rough heuristic)
        Write-Log "Refusing to install placeholder or empty key for $KeyLabel. Update the script with a real key." "ERROR"
        return $false
    }

    Write-Log "Installing ESU key ($KeyLabel). Product key characters will NOT be echoed in logs."

    $ipk = Start-Process -FilePath cscript.exe -ArgumentList "/nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ipk $ProductKey" -Wait -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds $PostSlmgrDelaySeconds

    if ($ipk.ExitCode -ne 0) {
        Write-Log "slmgr /ipk returned exit code $($ipk.ExitCode). Continuing to attempt activation anyway." "WARN"
    } else {
        Write-Log "Key installation command executed."
    }

    Write-Log "Attempting online activation (slmgr /ato)."
    $ato = Start-Process -FilePath cscript.exe -ArgumentList "/nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ato" -Wait -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds $PostSlmgrDelaySeconds

    if ($ato.ExitCode -ne 0) {
        Write-Log "slmgr /ato returned exit code $($ato.ExitCode)." "WARN"
    } else {
        Write-Log "Activation command executed."
    }

    return $true
}

function Assert-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Log "Script must run elevated. Aborting." "ERROR"
        exit 1
    }
}

function Test-Windows10 {
    $os = Get-CimInstance Win32_OperatingSystem
    $version = [Version]$os.Version
    # Windows 10 versions begin with 10.0.x; Windows 11 is also 10.0 but we can differentiate by build if needed.
    # Optional: Exclude Windows 11 builds (22000+). Adjust logic as needed.
    if ($version.Major -ne 10) {
        Write-Log "OS version $($os.Version) is not Windows 10. Skipping remediation." "ERROR"
        exit 1
    }
}

#endregion Helper Functions

try {
    Assert-Admin
    Test-Windows10

    Write-Log "Starting ESU remediation..."

    if ($VerboseLogging) {
        Write-Log "Configured Activation IDs: $($ActivationIDs -join ', ')" "DEBUG"
        Write-Log "Configured ESU Keys (labels only): $((($ESUKeys.GetEnumerator() | ForEach-Object { $_.Key }) -join ', '))" "DEBUG"
    }

    $all = Get-SoftwareLicensingProducts
    $esu = Get-EsuProducts -AllLicenses $all

    if ($VerboseLogging) {
        if ($esu) {
            Write-Log "Current ESU license objects:" "DEBUG"
            foreach ($p in $esu) {
                Write-Log ("  {0} | ActivationID={1} | Status={2}({3}) | PartialKey={4}" -f `
                    $p.Name, $p.ActivationID, $p.LicenseStatus, (Get-LicenseStatusName $p.LicenseStatus), $p.PartialProductKey) "DEBUG"
            }
        } else {
            Write-Log "No ESU license objects detected before remediation." "DEBUG"
        }
    }

    if (Test-EsuCompliant -EsuProducts $esu) {
        Write-Log "Already compliant. No remediation needed."
        exit 0
    }

    # Determine which year(s) are missing or not licensed
    $neededYear = $null
    foreach ($kv in $ESUKeys.GetEnumerator()) {
        $yearLabel = $kv.Key
        $keyValue  = $kv.Value

        # Map label to activation ID if known
        $activationId = ($ActivationIdToYear.GetEnumerator() | Where-Object { $_.Value -eq $yearLabel }).Name

        $existingYearProduct = $null
        if ($activationId) {
            $existingYearProduct = $esu | Where-Object { $_.ActivationID -eq $activationId }
        }

        $isLicensed = $existingYearProduct -and ($existingYearProduct.LicenseStatus -eq 1)

        if (-not $isLicensed) {
            $neededYear = $yearLabel
            break
        }
    }

    if (-not $neededYear) {
        # We found ESU entries but none licensed? (Edge case)
        Write-Log "ESU entries exist but none licensed; proceeding with first key reinstall attempt."
        $neededYear = ($ESUKeys.Keys | Select-Object -First 1)
    }

    Write-Log "Attempting to install/activate ESU key for: $neededYear"
    $targetKey = $ESUKeys[$neededYear]

    if (-not $targetKey) {
        Write-Log "No product key configured for $neededYear. Cannot remediate." "ERROR"
        exit 1
    }

    if (-not (Install-EsuKey -KeyLabel $neededYear -ProductKey $targetKey)) {
        Write-Log "Key installation routine returned failure." "ERROR"
        exit 1
    }

    # Re-evaluate after attempt
    $allPost = Get-SoftwareLicensingProducts
    $esuPost = Get-EsuProducts -AllLicenses $allPost

    if ($VerboseLogging) {
        Write-Log "Post-remediation ESU license objects:" "DEBUG"
        foreach ($p in $esuPost) {
            Write-Log ("  {0} | ActivationID={1} | Status={2}({3}) | PartialKey={4}" -f `
                $p.Name, $p.ActivationID, $p.LicenseStatus, (Get-LicenseStatusName $p.LicenseStatus), $p.PartialProductKey) "DEBUG"
        }
    }

    if (Test-EsuCompliant -EsuProducts $esuPost) {
        Write-Log "Remediation succeeded. ESU is now licensed."
        exit 0
    } else {
        Write-Log "Remediation failed: ESU still not licensed." "ERROR"
        exit 1
    }
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" "ERROR"
    if ($_.ScriptStackTrace) {
        Write-Log "Stack: $($_.ScriptStackTrace)" "ERROR"
    }
    exit 1
}
