# Builds both BuffRadar editions from one source.
#
#   BuffRadar\            shared addon files (BuffRadar.lua, Bindings.xml, LICENSE,
#                         Media\) plus the retail edition's .toc / README /
#                         CHANGELOG / DESCRIPTION / FEATURES
#   editions\forever\     the Forever edition's .toc / README / CHANGELOG /
#                         DESCRIPTION / FEATURES
#
# Output: dist\BuffRadar-<version>-Retail.zip and dist\BuffRadar-<version>-Forever.zip,
# each holding a BuffRadar\ folder ready for Interface\AddOns. The version comes
# from each edition's .toc. Existing zips in dist\ with the same name are replaced.
#
# Usage (PowerShell):  .\build.ps1

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src = Join-Path $here 'BuffRadar'
$dist = Join-Path $here 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

$editions = @(
  @{ Name = 'Retail';  Docs = $src },
  @{ Name = 'Forever'; Docs = (Join-Path $here 'editions\forever') }
)
$docFiles = 'BuffRadar.toc', 'README.md', 'CHANGELOG.md', 'DESCRIPTION.md', 'FEATURES.md'

foreach ($ed in $editions) {
  $toc = Get-Content (Join-Path $ed.Docs 'BuffRadar.toc')
  $version = ($toc | Where-Object { $_ -match '^## Version:\s*(\S+)' } | Select-Object -First 1) -replace '^## Version:\s*', ''
  if (-not $version) { throw "No '## Version:' line in $($ed.Name) .toc" }

  $stage = Join-Path ([IO.Path]::GetTempPath()) ("BuffRadar-build-" + [guid]::NewGuid())
  $addon = Join-Path $stage 'BuffRadar'
  New-Item -ItemType Directory -Force $addon | Out-Null
  try {
    # shared files: everything in BuffRadar\ except the per-edition docs
    Get-ChildItem $src | Where-Object { $docFiles -notcontains $_.Name } |
      Copy-Item -Destination $addon -Recurse
    foreach ($f in $docFiles) { Copy-Item (Join-Path $ed.Docs $f) $addon }

    $zip = Join-Path $dist ("BuffRadar-$version-$($ed.Name).zip")
    Compress-Archive -Path $addon -DestinationPath $zip -Force
    $count = (Get-ChildItem -Recurse -File $addon).Count
    Write-Host ("{0,-8} {1}  ({2} files)" -f $ed.Name, $zip, $count)
  }
  finally {
    Remove-Item -Recurse -Force $stage
  }
}
