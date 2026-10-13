<#
.SYNOPSIS
  Syntax-checks every .lua file and checks each .toc's file list against the disk.

.DESCRIPTION
  Runs `luac -p` on every .lua file in the Grimoire* folders. Then, for each .toc,
  reports files it lists that don't exist, and .lua/.xml files on disk that no .toc
  loads. Exits 1 if anything is wrong.

  Needs luac on PATH, or Lua from `winget install DEVCOM.Lua`. That's Lua 5.4, which
  is stricter than WoW's 5.1 only in ways this code doesn't use.

.EXAMPLE
  .\scripts\check-lua.ps1
#>

$repo = Split-Path $PSScriptRoot -Parent
$luac = (Get-Command luac -ErrorAction SilentlyContinue).Source
if (-not $luac) {
    $luac = Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\luac.exe"
}
if (-not (Test-Path $luac)) {
    Write-Error "luac not found. Install it with: winget install DEVCOM.Lua"
    exit 1
}

$failed = $false
$addons = Get-ChildItem -Path $repo -Directory -Filter "Grimoire*"

$scripts = Get-ChildItem -Path (Join-Path $repo "scripts") -Recurse -Filter "*.lua"
foreach ($file in @($addons | Get-ChildItem -Recurse -Filter "*.lua") + @($scripts)) {
    & $luac -p $file.FullName
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}

foreach ($addon in $addons) {
    $listed = @{}
    foreach ($toc in Get-ChildItem -Path $addon.FullName -Filter "*.toc") {
        foreach ($line in Get-Content $toc.FullName) {
            $entry = $line.Trim()
            if ($entry -eq "" -or $entry.StartsWith("#")) { continue }
            $path = Join-Path $addon.FullName $entry
            $listed[(Resolve-Path $path -ErrorAction SilentlyContinue).Path] = $true
            if (-not (Test-Path $path)) {
                Write-Host "$($toc.Name): lists missing file $entry" -ForegroundColor Red
                $failed = $true
            }
        }
    }
    foreach ($file in Get-ChildItem -Path $addon.FullName -Recurse -Include "*.lua", "*.xml") {
        if (-not $listed[$file.FullName]) {
            Write-Host "$($addon.Name): $($file.Name) isn't in the .toc" -ForegroundColor Yellow
        }
    }
}

if ($failed) { exit 1 }
Write-Host "All Lua files parse and every .toc entry exists." -ForegroundColor Green
