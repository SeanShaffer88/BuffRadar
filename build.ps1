#Requires -Version 7.0
# Packages the supported Forever edition into dist\BuffRadar-<version>-Forever.zip.

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'BuffRadar'
$forever = Join-Path $PSScriptRoot 'editions\forever'
$dist = Join-Path $PSScriptRoot 'dist'
$editionFiles = 'BuffRadar.toc', 'README.md', 'CHANGELOG.md', 'DESCRIPTION.md', 'FEATURES.md'
$versionLine = Select-String -LiteralPath (Join-Path $forever 'BuffRadar.toc') -Pattern '^## Version:\s*(\d+\.\d+\.\d+)\s*$'
if (@($versionLine).Count -ne 1) { throw 'Expected one numeric Version in the Forever TOC.' }
$version = $versionLine.Matches.Groups[1].Value
$zipName = "BuffRadar-$version-Forever.zip"
$zipPath = Join-Path $dist $zipName
$temporary = Join-Path $dist ([guid]::NewGuid().ToString() + '.tmp')

New-Item -ItemType Directory -Force $dist | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
  $archive = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
  try {
    $payload = Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object {
      $_.DirectoryName -ne $source -or $_.Name -notin $editionFiles
    }
    foreach ($file in $payload) {
      $relative = [IO.Path]::GetRelativePath($source, $file.FullName).Replace('\', '/')
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, "BuffRadar/$relative") | Out-Null
    }
    foreach ($file in $editionFiles) {
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $forever $file), "BuffRadar/$file") | Out-Null
    }
  } finally {
    $archive.Dispose()
  }
  Move-Item -LiteralPath $temporary -Destination $zipPath -Force
  $digest = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  "$digest  $zipName" | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
  Write-Host "Forever  $zipPath"
} finally {
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
