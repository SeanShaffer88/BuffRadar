# Runs every BuffRadar check in one go. See tools\README.md.
#
#   .\tools\check.ps1            run all checks (exit code 1 if any fails)
#   .\tools\check.ps1 -Setup     first create the tools folder (Python + Lua 5.1, luacheck)
#
# The tools live outside the project, in -ToolsDir (default
# %LOCALAPPDATA%\Temp\brlua). Windows may clean Temp folders; if the check
# says the tools are missing, run it again with -Setup.

param(
  [switch]$Setup,
  [string]$ToolsDir = (Join-Path $env:LOCALAPPDATA 'Temp\brlua')
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot                       # ...\tools
$project = Split-Path $here -Parent          # folder holding BuffRadar\ and .luacheckrc
$lua = Join-Path $project 'BuffRadar\BuffRadar.lua'
$locales = Join-Path $project 'BuffRadar\Locales'
$localeFiles = @(Get-ChildItem $locales -Filter '*.lua' -ErrorAction SilentlyContinue | ForEach-Object FullName)
$py = Join-Path $ToolsDir 'Scripts\python.exe'
$luacheck = Join-Path $ToolsDir 'bin\luacheck.exe'

if ($Setup) {
  if (-not (Test-Path $py)) {
    Write-Host "Creating Python environment in $ToolsDir ..."
    py -3 -m venv $ToolsDir
  }
  Write-Host "Installing lupa (Python package bundling Lua 5.1) ..."
  & $py -m pip install --quiet --disable-pip-version-check --only-binary=:all: lupa
  if (-not (Test-Path $luacheck)) {
    $bin = Join-Path $ToolsDir 'bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $base = 'https://github.com/lunarmodules/luacheck/releases/download/v1.2.0'
    Write-Host "Downloading luacheck 1.2.0 (official lunarmodules release) ..."
    Invoke-WebRequest "$base/luacheck.exe" -OutFile $luacheck
    Invoke-WebRequest "$base/luacheck.exe.asc" -OutFile "$luacheck.asc"
    # SHA-256 of the file whose signature was verified when the tools were first set up
    $expected = '0F1C69C4D09F1EBB4D8DF14C215E4553E2E639BD4CB7BF3C639B0DAA6198317B'
    $actual = (Get-FileHash $luacheck -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
      Remove-Item $luacheck, "$luacheck.asc" -Force
      throw "luacheck.exe checksum mismatch ($actual); download removed."
    }
  }
  Write-Host "Setup done.`n"
}

foreach ($t in @($py, $luacheck)) {
  if (-not (Test-Path $t)) { Write-Host "Missing $t - run: .\tools\check.ps1 -Setup"; exit 1 }
}

$failed = @()
function Section($name) { Write-Host "`n== $name" }

# 1. luacheck: accidental globals, unused or shadowed variables, unreachable code
Section 'luacheck'
Push-Location $project
try { & $luacheck 'BuffRadar\BuffRadar.lua' 'BuffRadar\Locales' --no-color --codes; if ($LASTEXITCODE -ne 0) { $failed += 'luacheck' } }
finally { Pop-Location }

# 2. Compile with real Lua 5.1 (the language WoW runs)
Section 'Lua 5.1 compile'
$out = & $py -I (Join-Path $here 'luacheck51.py') $lua @localeFiles 2>&1 | Out-String
Write-Host $out.Trim()
if ($out -notmatch 'BuffRadar\.lua: OK' -or $out -match ': FAIL') { $failed += 'compile' }

# 2b. Translations: keys BuffRadar doesn't use, mismatched %d / %s or color codes
if ($localeFiles.Count) {
  Section 'Translations'
  & $py -I (Join-Path $here 'localecheck.py') $lua $locales
  if ($LASTEXITCODE -ne 0) { $failed += 'translations' }
}

# 3. Lua 5.1 limits: 200 main-chunk locals, 60 upvalues per function
Section 'Lua 5.1 limits'
$out = & $py -I (Join-Path $here 'lualimits.py') $lua 2>&1 | Out-String
Write-Host $out.Trim()
if ($out -match 'peak (\d+) active locals') {
  $peak = [int]$Matches[1]
  if ($peak -ge 200) { $failed += 'local limit' }
  elseif ($peak -ge 195) { Write-Host "WARNING: $peak of 200 main-chunk locals used - put new helpers in a do-block or a table." }
}
if ($out -match '(?m)^\s+(\d+)\s+line') {
  $up = [int]$Matches[1]
  if ($up -gt 60) { $failed += 'upvalue limit' }
  elseif ($up -ge 55) { Write-Host "WARNING: a function uses $up of 60 upvalues." }
}

# 4. Trial run against a fake game client, both editions
Section 'Trial run (fake game client)'
$out = & $py -I (Join-Path $here 'smoke51.py') (Join-Path $here 'wowstub.lua') $lua 2>&1 | Out-String
Write-Host $out.Trim()
if ($out -match '[1-9]\d* with errors' -or $out -notmatch '0 with errors') { $failed += 'trial run' }

# 5. Built zips up to date? (only if build.ps1 has been run)
$dist = Join-Path $project 'dist'
if (Test-Path $dist) {
  Section 'Built zips'
  $srcHash = (Get-FileHash $lua).Hash
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  foreach ($zip in Get-ChildItem $dist -Filter '*.zip') {
    $z = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
    try {
      $entry = $z.Entries | Where-Object FullName -eq 'BuffRadar/BuffRadar.lua'
      $tmp = [IO.Path]::GetTempFileName()
      [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tmp, $true)
      $state = if ((Get-FileHash $tmp).Hash -eq $srcHash) { 'up to date' } else { 'OUT OF DATE - run .\build.ps1' }
      Remove-Item $tmp
    } finally { $z.Dispose() }
    Write-Host ("{0}: {1}" -f $zip.Name, $state)
  }
}

Write-Host ''
if ($failed.Count) { Write-Host "FAILED: $($failed -join ', ')"; exit 1 }
Write-Host 'All checks passed.'
