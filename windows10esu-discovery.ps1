<#
.SYNOPSIS
  Detects if a Windows 10 ESU (Year 1/2/3) add-on license is installed and activated.
  Exit 0 = Compliant (at least one ESU license has LicenseStatus = 1)
  Exit 1 = Non-compliant or error.
#>

$ActivationIDs = @(
  'f520e45e-7413-4a34-a497-d2765967d094', # Year 1
  '1043add5d-23b1-4afb-9a0f-64343c8f3f8d', # Year 2
  '83d49986-add3-41d7-ba33-87c7bfb5c0fb'  # Year 3
) | ForEach-Object { $_.ToLower() }  # normalize case

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

try {
    Write-Host "=== ESU Detection (WMI/CIM) ==="
    Write-Host "Activation IDs: $($ActivationIDs -join ', ')"

    try {
        $licenses = Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop
        Write-Host "Used Get-CimInstance"
    }
    catch {
        Write-Host "Get-CimInstance failed: $($_.Exception.Message) - falling back to Get-WmiObject"
        try {
            $licenses = Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop
            Write-Host "Used Get-WmiObject"
        }
        catch {
            Write-Host "Get-WmiObject also failed: $($_.Exception.Message)"
            exit 1
        }
    }

    if (-not $licenses) {
        Write-Host "No licenses returned from WMI/CIM query. Ensure you have permission and that the class exists on this system."
        exit 1
    }

    Write-Host "Total licenses found: $(@($licenses).Count)"

    # Find ESU products
    $esu = $licenses |
        Where-Object {
            if (-not $_.ActivationID) { return $false }
            $aid = $_.ActivationID.ToString().ToLower()
            return ($ActivationIDs -contains $aid)
        }

    if (-not $esu) {
        Write-Host "No ESU Activation IDs found among installed licenses."
        Write-Host "Checking all licenses with ActivationID set for debugging..."
        
        $licensesWithActivationID = $licenses | Where-Object { $_.ActivationID }
        Write-Host "Found $(@($licensesWithActivationID).Count) licenses with ActivationID"
        
        $licensesWithActivationID | Select-Object -First 10 | ForEach-Object {
            Write-Host ("  Name: {0}, ActivationID: {1}, LicenseStatus: {2}" -f $_.Name, $_.ActivationID, $_.LicenseStatus)
        }
    } else {
        Write-Host "Found $(@($esu).Count) ESU entries:"
        $esu | ForEach-Object {
            $aid = $_.ActivationID.ToString()
            Write-Host ("  Name: {0}" -f $_.Name)
            Write-Host ("  ActivationID: {0}" -f $aid)
            Write-Host ("  LicenseStatus: {0} ({1})" -f $_.LicenseStatus, (Get-LicenseStatusName $_.LicenseStatus))
            Write-Host ("  PartialProductKey: {0}" -f $_.PartialProductKey)
            Write-Host ("  ApplicationID: {0}" -f $_.ApplicationID)
            Write-Host ""
        }
    }

    $licensedESU = $esu | Where-Object { $_.LicenseStatus -eq 1 }

    if ($licensedESU) {
        Write-Host "Result: COMPLIANT (At least one ESU license is fully Licensed)."
        exit 0
    } else {
        Write-Host "Result: NON-COMPLIANT (No ESU license in Licensed state)."
        exit 1
    }
}
catch {
    Write-Host "Error during detection: $($_.Exception.Message)"
    Write-Host "Stack: $($_.ScriptStackTrace)"
    exit 1
}
