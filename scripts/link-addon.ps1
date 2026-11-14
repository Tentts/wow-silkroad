# Links the SilkRoad addon folder into the WoW Forever AddOns folder with a
# directory junction, so the game always loads the code in this repository.
# Junctions don't need administrator rights. Type /reload in game after edits.
#
#   powershell -ExecutionPolicy Bypass -File scripts/link-addon.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/link-addon.ps1 -WowPath "D:\Games\World of Warcraft"

param(
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft"
)

$ErrorActionPreference = "Stop"
$source = Join-Path (Split-Path -Parent $PSScriptRoot) "SilkRoad"
$addons = Join-Path $WowPath "_forever_\Interface\AddOns"
$target = Join-Path $addons "SilkRoad"

if (-not (Test-Path $addons)) {
    throw "AddOns folder not found: $addons (pass -WowPath with your World of Warcraft folder)"
}

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.LinkType -eq "Junction" -and $item.Target -contains $source) {
        Write-Host "Already linked: $target -> $source"
        exit 0
    }
    throw "$target already exists. Remove or rename it first, then run this script again."
}

New-Item -ItemType Junction -Path $target -Target $source | Out-Null
Write-Host "Linked $target -> $source"
