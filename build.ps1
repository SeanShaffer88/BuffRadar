#Requires -Version 7.0
# Windows wrapper for the shared deterministic Forever packager.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script = Join-Path $PSScriptRoot 'tools/package.py'
if (Get-Command py -ErrorAction SilentlyContinue) {
  & py -3 -I $script @args
} else {
  & python -I $script @args
}
if ($LASTEXITCODE -ne 0) { throw "Forever package failed (exit $LASTEXITCODE)." }
