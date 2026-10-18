<#
.SYNOPSIS
  One-time move of Grimoire's saved data and add-on links to the Homunculus names (ADR 0010).

.DESCRIPTION
  Run once, with the game closed, after pulling the rename:
    - SavedVariables\Grimoire*.lua -> Homunculus*.lua, with the variables inside renamed
      (GrimoireDB -> HomunculusDB, GrimoireTempoDB -> HomunculusTempoDB, ...)
    - AddOns.txt: each character's on/off state for every Grimoire_* add-on
    - bindings-cache.wtf: the emote wheel key (GRIMOIRE_EMOTE_WHEEL)
    - Interface\AddOns: removes the old Grimoire* junctions and links the Homunculus* folders
  Existing Homunculus files are never overwritten. The old files are left in place, renamed
  to *.grimoire-backup.

.EXAMPLE
  .\scripts\migrate-to-homunculus.ps1 -GameDir "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir
)

$ErrorActionPreference = "Stop"

if (Get-Process -Name "Wow*" -ErrorAction SilentlyContinue) {
    throw "Close the game first: it rewrites SavedVariables when it exits."
}

$wtf = Join-Path $GameDir "WTF\Account"
if (-not (Test-Path $wtf)) {
    throw "No WTF\Account folder under $GameDir."
}

function Rewrite($path, [scriptblock]$change) {
    $text = [IO.File]::ReadAllText($path)
    $new = & $change $text
    if ($new -ne $text) {
        [IO.File]::WriteAllText($path, $new)
        Write-Host "Updated $path"
    }
}

# SavedVariables: account-wide (Account\<ACCOUNT>\SavedVariables) and per character
# (Account\<ACCOUNT>\<realm>\<character>\SavedVariables).
Get-ChildItem -Path $wtf -Recurse -File -Filter "Grimoire*.lua" |
    Where-Object { $_.Directory.Name -eq "SavedVariables" } |
    ForEach-Object {
        $newName = "Homunculus" + $_.Name.Substring("Grimoire".Length)
        $target = Join-Path $_.DirectoryName $newName
        if (Test-Path $target) {
            Write-Warning "$target already exists, left $($_.Name) alone."
            return
        }
        $text = [IO.File]::ReadAllText($_.FullName)
        $text = [regex]::Replace($text, "(?m)^Grimoire(\w*)(\s*=)", 'Homunculus$1$2')
        [IO.File]::WriteAllText($target, $text)
        Rename-Item -Path $_.FullName -NewName ($_.Name + ".grimoire-backup")
        Write-Host "Migrated $($_.FullName) -> $newName"
    }

Get-ChildItem -Path $wtf -Recurse -File -Filter "AddOns.txt" | ForEach-Object {
    Rewrite $_.FullName { param($t) [regex]::Replace($t, "(?m)^Grimoire", "Homunculus") }
}

Get-ChildItem -Path $wtf -Recurse -File -Filter "bindings-cache.wtf" | ForEach-Object {
    Rewrite $_.FullName { param($t) $t.Replace("GRIMOIRE_EMOTE_WHEEL", "HOMUNCULUS_EMOTE_WHEEL") }
}

# Old junctions point at folders that no longer exist. Directory.Delete on a junction
# removes the link only, never the folder it points to.
$addOnsDir = Join-Path $GameDir "Interface\AddOns"
if (Test-Path $addOnsDir) {
    Get-ChildItem -Path $addOnsDir -Directory -Filter "Grimoire*" | ForEach-Object {
        if ($_.LinkType -eq "Junction") {
            [IO.Directory]::Delete($_.FullName, $false)
            Write-Host "Removed old link $($_.Name)"
        } else {
            Write-Warning "$($_.FullName) is a real folder, not a link; left it alone."
        }
    }
}

& (Join-Path $PSScriptRoot "link-addons.ps1") -GameDir $GameDir
Write-Host "Done. Start the game."
