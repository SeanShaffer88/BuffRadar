#Requires -Version 7.0
# Runs every BuffRadar check in one go. See tools\README.md.
#
#   .\tools\check.ps1            run all checks (nonzero exit if any fails)
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
# Native commands are checked explicitly below, including the compiler's exit code.
$PSNativeCommandUseErrorActionPreference = $false
$here = $PSScriptRoot                       # ...\tools
$project = Split-Path $here -Parent          # folder holding BuffRadar\ and .luacheckrc
$addon = Join-Path $project 'BuffRadar'
$lua = Join-Path $addon 'BuffRadar.lua'
$locales = Join-Path $addon 'Locales'
$toc = Join-Path $project 'editions\forever\BuffRadar.toc'
$py = Join-Path $ToolsDir 'Scripts\python.exe'
$luacheck = Join-Path $ToolsDir 'bin\luacheck.exe'

if ($Setup) {
  if (-not (Test-Path $py)) {
    Write-Host "Creating Python environment in $ToolsDir ..."
    py -3 -m venv $ToolsDir
  }
  Write-Host "Installing lupa (Python package bundling Lua 5.1) ..."
  & $py -m pip install --quiet --disable-pip-version-check --only-binary=:all: lupa==2.8
  if ($LASTEXITCODE -ne 0) { throw 'Lupa installation failed.' }
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
try {
  & $luacheck 'BuffRadar' --no-color --codes
  if ($LASTEXITCODE -ne 0) { $failed += 'luacheck' }
}
finally { Pop-Location }

# 2. Compile and check all shared modules, like the POSIX gate.
Section 'Lua 5.1 compile'
$luaFiles = @((Get-ChildItem -LiteralPath $addon -Filter '*.lua' -File).FullName)
$localeFiles = @((Get-ChildItem -LiteralPath $locales -Filter '*.lua' -File).FullName)
& $py -I (Join-Path $here 'luacheck51.py') @luaFiles @localeFiles
$compileExit = $LASTEXITCODE
if ($compileExit -ne 0) {
  Write-Host "FAILED: Lua 5.1 compile (exit $compileExit)"
  exit $compileExit
}

# 2b. Translations: keys BuffRadar doesn't use, mismatched %d / %s or color codes
Section 'Translations'
& $py -I (Join-Path $here 'localecheck.py') $lua $locales
if ($LASTEXITCODE -ne 0) { $failed += 'translations' }

Section 'Visible localization callsites'
& $py -I (Join-Path $here 'localization_callsites.py')
if ($LASTEXITCODE -ne 0) { $failed += 'visible localization callsites' }
& $py -I (Join-Path $here 'test_localization_callsites.py')
if ($LASTEXITCODE -ne 0) { $failed += 'visible localization fixtures' }

Section 'Lua pattern arguments'
& $py -I (Join-Path $here 'test_localecheck.py')
if ($LASTEXITCODE -ne 0) { $failed += 'locale regression fixtures' }
& $py -I (Join-Path $here 'locale_flows51.py')
if ($LASTEXITCODE -ne 0) { $failed += 'locale-first flows' }
& $py -I (Join-Path $here 'patterncheck.py') @luaFiles @localeFiles
if ($LASTEXITCODE -ne 0) { $failed += 'patterns' }

# 3. Advisory Lua 5.1 limits. Only the compiler decides whether Lua can load.
Section 'Lua 5.1 limits (estimates)'
foreach ($file in $luaFiles) {
  $out = & $py -I (Join-Path $here 'lualimits.py') $file 2>&1 | Out-String
  Write-Host $out.Trim()
  if ($out -match 'peak (\d+) active locals' -and [int]$Matches[1] -ge 195) {
    Write-Host "WARNING: Estimated $($Matches[1]) of 200 main-chunk locals used."
  }
  if ($out -match '(?m)^\s+(\d+)\s+line' -and [int]$Matches[1] -ge 55) {
    Write-Host "WARNING: A function uses an estimated $($Matches[1]) of 60 upvalues."
  }
}

# 4. Trial run against a fake game client, both editions
Section 'Trial run (fake game client)'
& $py -I (Join-Path $here 'smoke51.py') (Join-Path $here 'wowstub.lua') $lua
if ($LASTEXITCODE -ne 0) { $failed += 'trial run' }

Section 'Caster Coordination (two fake game clients)'
& $py -I (Join-Path $here 'coordination51.py') (Join-Path $here 'wowstub.lua') $lua
if ($LASTEXITCODE -ne 0) { $failed += 'two-client coordination' }

Section 'Offline relog (fresh fake game clients)'
& $py -I (Join-Path $here 'relog51.py') (Join-Path $here 'wowstub.lua') $lua
if ($LASTEXITCODE -ne 0) { $failed += 'offline relog' }

Section 'Theme preview (fake game client)'
& $py -I (Join-Path $here 'theme_preview51.py') --addon $lua
if ($LASTEXITCODE -ne 0) { $failed += 'theme preview' }

Section 'Actions search (fake game client)'
& $py -I (Join-Path $here 'actions51.py') --addon $lua
if ($LASTEXITCODE -ne 0) { $failed += 'actions search' }

Section 'Battleground and blessing diagnostics (fake game client)'
& $py -I (Join-Path $here 'diagnostics51.py') --addon $lua
if ($LASTEXITCODE -ne 0) { $failed += 'battleground and blessing diagnostics' }

Section 'Packaging regression tests'
& $py -I (Join-Path $here 'test_package.py')
if ($LASTEXITCODE -ne 0) { $failed += 'packaging regression tests' }

# 5. Validate the current Forever ZIP if it has been built.
$dist = Join-Path $project 'dist'
$versions = @(Select-String -LiteralPath $toc -Pattern '^## Version:\s*(\d+\.\d+\.\d+)\s*$')
if ($versions.Count -ne 1) { throw "Expected one valid Version in $toc" }
$version = $versions[0].Matches[0].Groups[1].Value
$zip = Join-Path $dist "BuffRadar-$version-Forever.zip"
if (Test-Path -LiteralPath $zip) {
  Section 'Forever package'
  & $py -I (Join-Path $here 'checkpackage.py') $zip $project
  if ($LASTEXITCODE -ne 0) { $failed += 'Forever package' }
}

Write-Host ''
if ($failed.Count) { Write-Host "FAILED: $($failed -join ', ')"; exit 1 }
Write-Host 'All checks passed.'
