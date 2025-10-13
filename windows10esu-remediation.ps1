<#
.SYNOPSIS
  Attempts to activate Windows 10 ESU license if not already activated.
  Designed for use as a remediation script in Intune Proactive Remediations.
#>

# Replace with your actual ESU product keys for each year
$ESUProductKeys = @{
    "<ESU_Year1_Product_Key>" = "<ESU_Year1_Product_Key>"
    "<ESU_Year2_Product_Key>" = "<ESU_Year2_Product_Key>"
    "<ESU_Year3_Product_Key>" = "<ESU_Year3_Product_Key>"
}

foreach ($ActivationID in $ESUProductKeys.Keys) {
    $ProductKey = $ESUProductKeys[$ActivationID]
    if ($ProductKey -and $ProductKey -ne "<ESU_Year1_Product_Key>" -and $ProductKey -ne "<ESU_Year2_Product_Key>" -and $ProductKey -ne "<ESU_Year3_Product_Key>") {
        try {
            # Install the ESU product key
            cscript.exe //nologo "$env:SystemRoot\system32\slmgr.vbs" /ipk $ProductKey
            # Attempt activation
            cscript.exe //nologo "$env:SystemRoot\system32\slmgr.vbs" /ato $ActivationID
            Write-Host "Attempted activation for ESU Activation ID $ActivationID."
        }
        catch {
            Write-Host "Error activating ESU for Activation ID $ActivationID: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "No valid product key provided for Activation ID $ActivationID."
    }
}

Write-Host "Remediation script completed."
exit 0
