<#
.SYNOPSIS
  Links every Homunculus* add-on folder in this repo into the game's AddOns folder.

.DESCRIPTION
  Uses directory junctions (no admin rights needed), so edits in the repo show up
  in game after a /reload. Existing folders with the same name are left alone.

.EXAMPLE
  .\scripts\link-addons.ps1 -GameDir "C:\Program Files (x86)\World of Warcraft\_forever_"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir
)

$addOnsDir = Join-Path $GameDir "Interface\AddOns"
if (-not (Test-Path $addOnsDir)) {
    New-Item -ItemType Directory -Path $addOnsDir -Force | Out-Null
}

$repo = Split-Path $PSScriptRoot -Parent

# Links left behind by a renamed add-on (Homunculus_Notes -> Homunculus_Grimoire) or a
# moved repo (C:\dev\grimoire -> C:\dev\homunculus) point at folders that no longer
# exist. Directory.Delete removes only the link itself.
Get-ChildItem -Path $addOnsDir -Directory -Filter "Homunculus*" | ForEach-Object {
    if ($_.LinkType -eq "Junction" -and @($_.Target)[0] -ne (Join-Path $repo $_.Name)) {
        [IO.Directory]::Delete($_.FullName, $false)
        Write-Host "Removed stale link $($_.Name)"
    }
}

Get-ChildItem -Path $repo -Directory -Filter "Homunculus*" | ForEach-Object {
    $target = Join-Path $addOnsDir $_.Name
    if (Test-Path $target) {
        Write-Warning "$target already exists, skipping."
    } else {
        New-Item -ItemType Junction -Path $target -Target $_.FullName | Out-Null
        Write-Host "Linked $($_.Name) -> $target"
    }
}
