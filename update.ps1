# Fumefy updater: compares the local VERSION with the latest GitHub release and, if newer,
# downloads it and replaces the mod files in this folder. start.ps1 runs it on every launch.
# Usage:  .\update.ps1          -> check and update, with messages
#         .\update.ps1 -Quiet   -> same, silent (used by start.ps1)
#         .\update.ps1 -Force   -> reinstall the latest release even if the version is the same
param([switch]$Quiet, [switch]$Force)

$ErrorActionPreference = "Stop"
$Repo = "lyusufdeniz/fumefy-spotify"
$here = $PSScriptRoot
function Say($m) { if (-not $Quiet) { Write-Host $m } }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ "User-Agent" = "fumefy-updater"; "Accept" = "application/vnd.github+json" }

$localFile = Join-Path $here "VERSION"
$local = if (Test-Path $localFile) { (Get-Content $localFile -Raw).Trim() } else { "0.0.0" }

try {
  $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -TimeoutSec 5
} catch {
  Say "Could not reach GitHub, skipping the update check."
  return
}
$latest = ($rel.tag_name -replace '^v', '').Trim()
if (-not $Force -and [version]$latest -le [version]$local) { Say "Fumefy $local is up to date."; return }

Say "Updating Fumefy $local -> $latest ..."
$asset = $rel.assets | Where-Object { $_.name -eq "fumefy-spotify.zip" } | Select-Object -First 1
$url = if ($asset) { $asset.browser_download_url } else { $rel.zipball_url }

$tmp = Join-Path $env:TEMP ("fumefy-update-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $zip = Join-Path $tmp "update.zip"
  Invoke-WebRequest $url -Headers $headers -OutFile $zip -UseBasicParsing -TimeoutSec 60
  Expand-Archive $zip -DestinationPath (Join-Path $tmp "x") -Force
  # the release zip has the files at its root; GitHub's source zip has them in one sub-folder
  $src = Get-ChildItem (Join-Path $tmp "x") -Recurse -Filter "inject.mjs" | Select-Object -First 1 | ForEach-Object { $_.DirectoryName }
  if (-not $src -or -not (Test-Path (Join-Path $src "theme\mod.js"))) { throw "The downloaded release does not look like Fumefy." }

  # theme/ is replaced as a whole (designs can be removed between versions); other files are overwritten
  $themeDst = Join-Path $here "theme"
  if (Test-Path $themeDst) { Remove-Item $themeDst -Recurse -Force }
  Get-ChildItem $src -Force | Where-Object { $_.Name -notin @(".git", ".github") } | ForEach-Object {
    Copy-Item $_.FullName -Destination $here -Recurse -Force
  }
  Set-Content -Path $localFile -Value $latest -Encoding ASCII
  # tell the mod what changed; inject.mjs shows it as a toast inside Spotify and deletes the file
  $note = (($rel.body -split "`n") | ForEach-Object { ($_ -replace '^\s*[-*]\s*', '').Trim() } | Where-Object { $_ -and $_ -notmatch '^(#|Install)' } | Select-Object -First 1)
  @{ from = $local; to = $latest; note = "$note" } | ConvertTo-Json -Compress | Set-Content (Join-Path $here "updated.json") -Encoding UTF8
  Say "Fumefy updated to $latest."
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
