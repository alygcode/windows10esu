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
$PostSlmgrDelaySeconds = 15  # Increased from 8 to 15

# Maximum retries for checking license status
$MaxStatusCheckRetries = 3
$StatusCheckDelaySeconds = 5

# Enable verbose logging (set to $false in production if you want quieter remediation runs)
$VerboseLogging = $true

#endregion Configuration

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $logMessage = "[$ts][$Level] $Message"
    Write-Host $logMessage
    
    # Optional: Write to event log for better tracking in Intune
    try {
        $source = "ESURemediation"
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName Application -Source $source -ErrorAction SilentlyContinue
        }
        $eventType = switch ($Level) {
            'ERROR' { 'Error' }
            'WARN'  { 'Warning' }
            default { 'Information' }
        }
        Write-EventLog -LogName Application -Source $source -EntryType $eventType -EventId 1000 -Message $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Silently continue if event log write fails
    }
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
        try {
            return Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop
        }
        catch {
            Write-Log "Both CIM and WMI queries failed: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
}

function Get-EsuProducts {
    param(
        [object[]]$AllLicenses
    )
    if (-not $AllLicenses) {
        Write-Log "No licenses provided to Get-EsuProducts" "WARN"
        return @()
    }
    
    $esuProducts = $AllLicenses |
        Where-Object { $_.PartialProductKey } |
        Where-Object { 
            $_.ActivationID -and 
            ($ActivationIDs -contains $_.ActivationID.ToLower()) 
        }
    
    return $esuProducts
}

function Test-EsuCompliant {
    param([object[]]$EsuProducts)
    
    if (-not $EsuProducts) {
        return $false
    }
    
    # Check if we have at least one licensed ESU product
    $licensed = $EsuProducts | Where-Object { $_.LicenseStatus -eq 1 }
    return [bool]$licensed
}

function Test-ValidProductKey {
    param([string]$ProductKey)
    
    if ([string]::IsNullOrWhiteSpace($ProductKey)) {
        return $false
    }
    
    # Check if it's a placeholder pattern (various common placeholders)
    $placeholderPatterns = @(
        '^[A-Z]{5}-[A-Z]{5}-[A-Z]{5}-[A-Z]{5}-[A-Z]{5}$',  # Generic all-same-letter
        '^AAAAA-',                                           # Starts with AAAAA
        '^XXXXX-',                                           # Starts with XXXXX
        '^12345-',                                           # Starts with 12345
        'PLACEHOLDER',                                       # Contains PLACEHOLDER
        'EXAMPLE',                                           # Contains EXAMPLE
        'YOUR-KEY-HERE'                                      # Contains YOUR-KEY-HERE
    )
    
    foreach ($pattern in $placeholderPatterns) {
        if ($ProductKey -match $pattern) {
            return $false
        }
    }
    
    # Validate format: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
    if ($ProductKey -notmatch '^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$') {
        return $false
    }
    
    return $true
}

function Install-EsuKey {
    param(
        [string]$KeyLabel,
        [string]$ProductKey
    )
    
    if (-not (Test-ValidProductKey -ProductKey $ProductKey)) {
        Write-Log "Invalid or placeholder key detected for $KeyLabel. Cannot proceed." "ERROR"
        return $false
    }

    Write-Log "Installing ESU key ($KeyLabel)..."

    # Install Product Key
    $ipkArgs = "/nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ipk $ProductKey"
    Write-Log "Executing: cscript.exe $($ipkArgs -replace $ProductKey, '***REDACTED***')"
    
    $ipk = Start-Process -FilePath cscript.exe -ArgumentList $ipkArgs -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput "$env:TEMP\slmgr_ipk.log" -RedirectStandardError "$env:TEMP\slmgr_ipk_err.log"
    Start-Sleep -Seconds $PostSlmgrDelaySeconds

    if ($ipk.ExitCode -ne 0) {
        Write-Log "slmgr /ipk returned exit code $($ipk.ExitCode)." "WARN"
        if (Test-Path "$env:TEMP\slmgr_ipk_err.log") {
            $errContent = Get-Content "$env:TEMP\slmgr_ipk_err.log" -Raw
            if ($errContent) {
                Write-Log "IPK Error output: $errContent" "ERROR"
            }
        }
        # Don't return false yet, try activation anyway
    } else {
        Write-Log "Key installation command completed successfully."
    }

    # Activate Online
    Write-Log "Attempting online activation (slmgr /ato)..."
    $atoArgs = "/nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ato"
    
    $ato = Start-Process -FilePath cscript.exe -ArgumentList $atoArgs -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput "$env:TEMP\slmgr_ato.log" -RedirectStandardError "$env:TEMP\slmgr_ato_err.log"
    Start-Sleep -Seconds $PostSlmgrDelaySeconds

    if ($ato.ExitCode -ne 0) {
        Write-Log "slmgr /ato returned exit code $($ato.ExitCode)." "WARN"
        if (Test-Path "$env:TEMP\slmgr_ato_err.log") {
            $errContent = Get-Content "$env:TEMP\slmgr_ato_err.log" -Raw
            if ($errContent) {
                Write-Log "ATO Error output: $errContent" "ERROR"
            }
        }
        return $false
    } else {
        Write-Log "Activation command completed successfully."
    }

    # Cleanup temp files
    Remove-Item "$env:TEMP\slmgr_*.log" -ErrorAction SilentlyContinue

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
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $version = [Version]$os.Version
        $buildNumber = [int]$os.BuildNumber
        
        Write-Log "Detected OS: $($os.Caption), Version: $($os.Version), Build: $buildNumber"
        
        # Windows 10 versions begin with 10.0.x
        # Windows 11 builds start at 22000
        if ($version.Major -ne 10) {
            Write-Log "OS version $($os.Version) is not Windows 10/11. Skipping remediation." "ERROR"
            return $false
        }
        
        # Optionally exclude Windows 11
        if ($buildNumber -ge 22000) {
            Write-Log "Detected Windows 11 (build $buildNumber). ESU is for Windows 10 only." "WARN"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to determine OS version: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-LicenseStatusWithRetry {
    param(
        [int]$MaxRetries = $MaxStatusCheckRetries,
        [int]$DelaySeconds = $StatusCheckDelaySeconds
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Log "Querying license status (attempt $i of $MaxRetries)..."
            $all = Get-SoftwareLicensingProducts
            $esu = Get-EsuProducts -AllLicenses $all
            
            if ($esu -or $i -eq $MaxRetries) {
                return @{
                    AllLicenses = $all
                    EsuProducts = $esu
                }
            }
            
            Write-Log "No ESU products found, waiting $DelaySeconds seconds before retry..." "WARN"
            Start-Sleep -Seconds $DelaySeconds
        }
        catch {
            Write-Log "Error querying licenses (attempt $i): $($_.Exception.Message)" "ERROR"
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw
            }
        }
    }
}

#endregion Helper Functions

#region Main Script

try {
    Write-Log "=== Windows 10 ESU Remediation Script Started ==="
    
    # Pre-flight checks
    Assert-Admin
    
    if (-not (Test-Windows10)) {
        Write-Log "OS check failed. Exiting." "ERROR"
        exit 1
    }

    Write-Log "Starting ESU remediation..."

    if ($VerboseLogging) {
        Write-Log "Configured Activation IDs: $($ActivationIDs -join ', ')" "DEBUG"
        Write-Log "Configured ESU Keys (labels only): $((($ESUKeys.GetEnumerator() | ForEach-Object { $_.Key }) -join ', '))" "DEBUG"
    }

    # Initial license check
    $licenseData = Get-LicenseStatusWithRetry
    $all = $licenseData.AllLicenses
    $esu = $licenseData.EsuProducts

    if ($VerboseLogging) {
        if ($esu) {
            Write-Log "Current ESU license objects:" "DEBUG"
            foreach ($p in $esu) {
                $yearLabel = if ($ActivationIdToYear.ContainsKey($p.ActivationID)) { 
                    " [$($ActivationIdToYear[$p.ActivationID])]" 
                } else { 
                    "" 
                }
                Write-Log ("  {0}{1} | ActivationID={2} | Status={3}({4}) | PartialKey={5}" -f `
                    $p.Name, $yearLabel, $p.ActivationID, $p.LicenseStatus, (Get-LicenseStatusName $p.LicenseStatus), $p.PartialProductKey) "DEBUG"
            }
        } else {
            Write-Log "No ESU license objects detected before remediation." "DEBUG"
        }
    }

    # Check if already compliant
    if (Test-EsuCompliant -EsuProducts $esu) {
        Write-Log "Already compliant. No remediation needed."
        Write-Log "=== ESU Remediation Script Completed Successfully ==="
        exit 0
    }

    # Determine which years need installation (ESU licenses are cumulative)
    Write-Log "ESU not compliant. Determining which keys to install..."
    
    $keysToInstall = @()
    foreach ($kv in $ESUKeys.GetEnumerator()) {
        $yearLabel = $kv.Key
        $keyValue  = $kv.Value

        # Map label to activation ID
        $activationId = ($ActivationIdToYear.GetEnumerator() | Where-Object { $_.Value -eq $yearLabel }).Name

        $existingYearProduct = $null
        if ($activationId) {
            $existingYearProduct = $esu | Where-Object { $_.ActivationID -eq $activationId }
        }

        $isLicensed = $existingYearProduct -and ($existingYearProduct.LicenseStatus -eq 1)

        if (-not $isLicensed) {
            Write-Log "$yearLabel is not licensed. Adding to installation queue."
            $keysToInstall += @{
                Label = $yearLabel
                Key = $keyValue
                ActivationID = $activationId
            }
        }
        else {
            Write-Log "$yearLabel is already licensed."
        }
    }

    if ($keysToInstall.Count -eq 0) {
        Write-Log "No keys identified for installation, but compliance check failed. This is unexpected." "WARN"
        Write-Log "=== ESU Remediation Script Completed with Warning ==="
        exit 1
    }

    Write-Log "Will attempt to install $($keysToInstall.Count) key(s): $($keysToInstall.Label -join ', ')"

    # Install keys in sequence (ESU requires Year 1 before Year 2, etc.)
    $installSuccess = $true
    foreach ($keyInfo in $keysToInstall) {
        Write-Log "Processing: $($keyInfo.Label)"
        
        if (-not (Test-ValidProductKey -ProductKey $keyInfo.Key)) {
            Write-Log "Skipping $($keyInfo.Label) - invalid or placeholder key." "ERROR"
            $installSuccess = $false
            continue
        }
        
        if (-not (Install-EsuKey -KeyLabel $keyInfo.Label -ProductKey $keyInfo.Key)) {
            Write-Log "Failed to install/activate key for $($keyInfo.Label)." "ERROR"
            $installSuccess = $false
            # For ESU, if one year fails, subsequent years will likely fail too
            break
        }
        
        Write-Log "$($keyInfo.Label) installation attempt completed."
    }

    if (-not $installSuccess) {
        Write-Log "One or more key installations failed." "ERROR"
        Write-Log "=== ESU Remediation Script Failed ==="
        exit 1
    }

    # Re-evaluate after installation attempts
    Write-Log "Re-checking ESU compliance after remediation..."
    $licenseDataPost = Get-LicenseStatusWithRetry
    $allPost = $licenseDataPost.AllLicenses
    $esuPost = $licenseDataPost.EsuProducts

    if ($VerboseLogging) {
        Write-Log "Post-remediation ESU license objects:" "DEBUG"
        if ($esuPost) {
            foreach ($p in $esuPost) {
                $yearLabel = if ($ActivationIdToYear.ContainsKey($p.ActivationID)) { 
                    " [$($ActivationIdToYear[$p.ActivationID])]" 
                } else { 
                    "" 
                }
                Write-Log ("  {0}{1} | ActivationID={2} | Status={3}({4}) | PartialKey={5}" -f `
                    $p.Name, $yearLabel, $p.ActivationID, $p.LicenseStatus, (Get-LicenseStatusName $p.LicenseStatus), $p.PartialProductKey) "DEBUG"
            }
        }
        else {
            Write-Log "No ESU license objects found after remediation." "WARN"
        }
    }

    if (Test-EsuCompliant -EsuProducts $esuPost) {
        Write-Log "Remediation succeeded. ESU is now licensed."
        Write-Log "=== ESU Remediation Script Completed Successfully ==="
        exit 0
    } else {
        Write-Log "Remediation failed: ESU still not licensed after installation attempts." "ERROR"
        Write-Log "=== ESU Remediation Script Failed ==="
        exit 1
    }
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" "ERROR"
    if ($_.ScriptStackTrace) {
        Write-Log "Stack: $($_.ScriptStackTrace)" "ERROR"
    }
    Write-Log "=== ESU Remediation Script Failed with Exception ==="
    exit 1
}

#endregion Main Script