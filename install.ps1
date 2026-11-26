# Fumefy installer.
# Run from a downloaded copy:   powershell -ExecutionPolicy Bypass -File install.ps1
# or straight from GitHub:      irm https://raw.githubusercontent.com/lyusufdeniz/fumefy-spotify/main/install.ps1 | iex
#
# What it does:
#   1. copies Fumefy to %LOCALAPPDATA%\Fumefy (downloads the latest release if not run from a copy)
#   2. makes sure Node.js 22+ is installed (offers to install it with winget)
#   3. adds "Spotify (Fumefy)" shortcuts to the Start menu and the desktop
# Nothing is changed in Spotify's own files; uninstall.ps1 removes everything again.

$ErrorActionPreference = "Stop"
$Repo = "lyusufdeniz/fumefy-spotify"
$dest = Join-Path $env:LOCALAPPDATA "Fumefy"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($m) { Write-Host "  > $m" -ForegroundColor Gray }
Write-Host ""
Write-Host "  Fumefy installer" -ForegroundColor White
Write-Host ""

# 1) Spotify must be installed
$spotify = @(
  (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Spotify.exe"),
  (Join-Path $env:APPDATA "Spotify\Spotify.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $spotify) { Write-Host "  Spotify was not found. Install it from the Microsoft Store or spotify.com first." -ForegroundColor Yellow; return }
Step "Spotify found"

# 2) Files: from this folder if it is a full copy, otherwise the latest GitHub release
$here = if ($PSScriptRoot) { $PSScriptRoot } else { "" }
New-Item -ItemType Directory -Path $dest -Force | Out-Null
if ($here -and (Test-Path (Join-Path $here "inject.mjs")) -and ($here -ne $dest)) {
  Step "Copying files to $dest"
  if (Test-Path (Join-Path $dest "theme")) { Remove-Item (Join-Path $dest "theme") -Recurse -Force }
  Get-ChildItem $here -Force | Where-Object { $_.Name -notin @(".git", ".github", "docs") } | ForEach-Object { Copy-Item $_.FullName -Destination $dest -Recurse -Force }
} elseif (-not (Test-Path (Join-Path $dest "inject.mjs"))) {
  Step "Downloading the latest release"
  $tmp = Join-Path $env:TEMP ("fumefy-install-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $headers = @{ "User-Agent" = "fumefy-installer" }
  $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
  $asset = $rel.assets | Where-Object { $_.name -eq "fumefy-spotify.zip" } | Select-Object -First 1
  $url = if ($asset) { $asset.browser_download_url } else { $rel.zipball_url }
  Invoke-WebRequest $url -Headers $headers -OutFile (Join-Path $tmp "f.zip") -UseBasicParsing
  Expand-Archive (Join-Path $tmp "f.zip") -DestinationPath (Join-Path $tmp "x") -Force
  $src = Get-ChildItem (Join-Path $tmp "x") -Recurse -Filter "inject.mjs" | Select-Object -First 1 | ForEach-Object { $_.DirectoryName }
  Get-ChildItem $src -Force | ForEach-Object { Copy-Item $_.FullName -Destination $dest -Recurse -Force }
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Step "Fumefy is already in $dest (start.ps1 keeps it up to date)"
}

# 3) Node.js 22+ (runs the injector)
function Node-Major { try { [int](((& node --version) -replace '^v', '').Split('.')[0]) } catch { 0 } }
$major = if (Get-Command node -ErrorAction SilentlyContinue) { Node-Major } else { 0 }
if ($major -lt 22) {
  Write-Host "  Node.js 22 or newer is needed (found: $(if ($major) { $major } else { 'none' }))." -ForegroundColor Yellow
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    $a = Read-Host "  Install Node.js LTS with winget now? [Y/n]"
    if ($a -eq "" -or $a -match '^[yY]') {
      winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
      $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    }
  } else {
    Write-Host "  Install it from https://nodejs.org and run this installer again." -ForegroundColor Yellow
  }
} else { Step "Node.js $major found" }

# 4) Shortcut icon: Spotify's own icon from this PC, recolored smoke gray (not shipped in the repo)
$icon = Join-Path $dest "assets\spotify-fume.ico"
# run it in its own process with -ExecutionPolicy Bypass: when this installer is piped into "iex", the
# default policy would block calling a .ps1 file from disk and the shortcut would fall back to a stock icon
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest "make-icon.ps1") -Out $icon | Out-Null } catch {}
if (Test-Path $icon) { & ie4uinit.exe -show 2>$null }   # refresh the icon cache so the new icon shows right away
$iconLoc = if (Test-Path $icon) { "$icon,0" } else { "$env:WINDIR\System32\imageres.dll,103" }
Step "Shortcut icon ready"

# 5) Shortcuts (they run Fumefy.vbs, which starts start.ps1 without a console window)
$shell = New-Object -ComObject WScript.Shell
$targets = @(
  (Join-Path ([Environment]::GetFolderPath("Programs")) "Spotify (Fumefy).lnk"),
  (Join-Path ([Environment]::GetFolderPath("Desktop")) "Spotify (Fumefy).lnk")
)
foreach ($t in $targets) {
  $lnk = $shell.CreateShortcut($t)
  $lnk.TargetPath = Join-Path $env:WINDIR "System32\wscript.exe"
  $lnk.Arguments = '"' + (Join-Path $dest "Fumefy.vbs") + '"'
  $lnk.WorkingDirectory = $dest
  $lnk.IconLocation = $iconLoc
  $lnk.Description = "Spotify with the Fumefy theme"
  $lnk.Save()
}
Step "Shortcuts added: Start menu and desktop -> 'Spotify (Fumefy)'"

# 6) Start with Windows instead of plain Spotify (can be changed later in the Fumefy menu)
$auto = Read-Host "  Start Spotify with Fumefy when Windows starts (replaces Spotify's own autostart)? [Y/n]"
if ($auto -eq "" -or $auto -match '^[yY]') { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest "autostart.ps1") -Enable | Out-Null; Step "Starts with Windows" }

Write-Host ""
Write-Host "  Done. Open Spotify with the 'Spotify (Fumefy)' shortcut." -ForegroundColor White
Write-Host "  Updates install themselves when you start it. To remove: run uninstall.ps1 in $dest" -ForegroundColor Gray
Write-Host ""
$go = Read-Host "  Start it now? [Y/n]"
if ($go -eq "" -or $go -match '^[yY]') { Start-Process (Join-Path $env:WINDIR "System32\wscript.exe") -ArgumentList ('"' + (Join-Path $dest "Fumefy.vbs") + '"') }
