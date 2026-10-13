<#
.SYNOPSIS
  Links every Grimoire* add-on folder in this repo into the game's AddOns folder.

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
Get-ChildItem -Path $repo -Directory -Filter "Grimoire*" | ForEach-Object {
    $target = Join-Path $addOnsDir $_.Name
    if (Test-Path $target) {
        Write-Warning "$target already exists, skipping."
    } else {
        New-Item -ItemType Junction -Path $target -Target $_.FullName | Out-Null
        Write-Host "Linked $($_.Name) -> $target"
    }
}
