<#
.SYNOPSIS
  Syntax-checks every .lua file and checks each .toc's file list against the disk.

.DESCRIPTION
  Runs `luac -p` on every .lua file in the Grimoire* folders. Then, for each .toc,
  reports files it lists that don't exist, and .lua/.xml files on disk that no .toc
  loads. It also flags a file-level local used above its declaration (that compiles
  as a nil global). Exits 1 if anything is wrong.

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

# A file-level local used above its declaration compiles as a global, which is nil at
# run time (seen 2026-10-16: Bags hooked Button_OnEnter before defining it, and the bag
# window broke). Flag a global read on a line above the `local` of the same name. Reads
# on the declaration line itself (`local Grimoire = Grimoire`, `local GetCVar = ... or
# GetCVar`) are intended and not flagged.
foreach ($file in $addons | Get-ChildItem -Recurse -Filter "*.lua") {
    $lines = @(Get-Content $file.FullName)
    $declared = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '^local\s+(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)')
        if ($m.Success -and -not $declared.ContainsKey($m.Groups[1].Value)) {
            $declared[$m.Groups[1].Value] = $i + 1
        }
    }
    foreach ($row in & $luac -l -p $file.FullName) {
        $m = [regex]::Match($row, '\[(\d+)\].*_ENV "([A-Za-z_][A-Za-z0-9_]*)"')
        if (-not $m.Success) { continue }
        $line = [int]$m.Groups[1].Value
        $name = $m.Groups[2].Value
        if ($declared.ContainsKey($name) -and $line -lt $declared[$name]) {
            Write-Host "$($file.Name):${line}: '$name' is used above its 'local' declaration (line $($declared[$name])), so it reads a nil global" -ForegroundColor Red
            $failed = $true
        }
    }
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
        # Bindings.xml is loaded by the game on its own and must not be listed.
        if (-not $listed[$file.FullName] -and $file.Name -ne "Bindings.xml") {
            Write-Host "$($addon.Name): $($file.Name) isn't in the .toc" -ForegroundColor Yellow
        }
    }
}

if ($failed) { exit 1 }
Write-Host "All Lua files parse and every .toc entry exists." -ForegroundColor Green
