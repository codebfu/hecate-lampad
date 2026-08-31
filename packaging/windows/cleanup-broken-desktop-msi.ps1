# Remove a Hecate Lampad Desktop Helper MSI registration without running its
# uninstall CustomActions (needed when those CAs raise MSI 2762).
# Run elevated: powershell -ExecutionPolicy Bypass -File cleanup-broken-desktop-msi.ps1

$ErrorActionPreference = "Stop"

function Compress-MsiGuid([string]$Guid) {
    $g = ([guid]$Guid).ToString("N").ToUpperInvariant()
    $chars = $g.ToCharArray()
    $out = New-Object char[] 32
    $i = 0
    for ($j = 7; $j -ge 0; $j--) { $out[$i++] = $chars[$j] }
    for ($j = 11; $j -ge 8; $j--) { $out[$i++] = $chars[$j] }
    for ($j = 15; $j -ge 12; $j--) { $out[$i++] = $chars[$j] }
    for ($k = 16; $k -lt 32; $k += 2) {
        $out[$i++] = $chars[$k + 1]
        $out[$i++] = $chars[$k]
    }
    return -join $out
}

$displayName = "Hecate Lampad Desktop Helper"
$uninstallRoot = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
$products = Get-ChildItem $uninstallRoot -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p.DisplayName -eq $displayName) {
        [PSCustomObject]@{
            ProductCode = $_.PSChildName
            DisplayVersion = $p.DisplayVersion
        }
    }
}

if (-not $products) {
    Write-Host "No '$displayName' ARP entry found."
} else {
    foreach ($prod in $products) {
        Write-Host "Scrubbing $($prod.ProductCode) ($($prod.DisplayVersion))"
        $compressed = Compress-MsiGuid $prod.ProductCode
        Write-Host "  Compressed product id: $compressed"

        $paths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($prod.ProductCode)",
            "HKLM:\Software\Classes\Installer\Products\$compressed",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\$compressed"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
                Write-Host "  Removed $path"
            }
        }

        $upgradeRoot = "HKLM:\SOFTWARE\Classes\Installer\UpgradeCodes"
        if (Test-Path $upgradeRoot) {
            Get-ChildItem $upgradeRoot | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath
                foreach ($name in $props.PSObject.Properties.Name) {
                    if ($name -eq $compressed -or $name -eq $prod.ProductCode.Trim("{}")) {
                        Remove-ItemProperty -LiteralPath $_.PSPath -Name $name -ErrorAction SilentlyContinue
                        Write-Host "  Cleared upgrade value $name under $($_.PSChildName)"
                    }
                }
            }
        }
    }
}

$taskNames = @("Hecate Lampad Desktop", "hecate-lampad-desktop")
foreach ($tn in $taskNames) {
    cmd.exe /c "schtasks /Delete /TN `"$tn`" /F >nul 2>nul" | Out-Null
}

$installDir = "${env:ProgramFiles}\hecate-lampad-desktop"
if (Test-Path $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
    Write-Host "Removed $installDir"
}

Write-Host "Done. Reinstall the current desktop MSI."
