# Fumefy launcher: checks for an update, starts Spotify with the local DevTools port and loads the mod.
# Usage:  .\start.ps1            -> normal start (what the "Spotify (Fumefy)" shortcut runs)
#         .\start.ps1 -Watch     -> developer mode: watch theme/ and live-reload on save, runs in this window
#         .\start.ps1 -NoUpdate  -> skip the update check
#         .\start.ps1 -Startup   -> used at Windows sign-in (see autostart.ps1): Spotify opens minimized
param([switch]$Watch, [switch]$NoUpdate, [switch]$Startup)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

# 1) Update (quick; never blocks the start for long, never fails the start)
if (-not $NoUpdate -and -not $Watch) {
  try { & (Join-Path $here "update.ps1") -Quiet } catch {}
}

# 2) Find Spotify: Microsoft Store version first, then the classic installer version
$candidates = @(
  (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\Spotify.exe"),
  (Join-Path $env:APPDATA "Spotify\Spotify.exe")
)
$spotify = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $spotify) {
  Add-Type -AssemblyName PresentationFramework
  [void][Windows.MessageBox]::Show("Spotify was not found. Install Spotify from the Microsoft Store or spotify.com, then try again.", "Fumefy")
  exit 1
}

# 3) Node.js runs the injector
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) {
  Add-Type -AssemblyName PresentationFramework
  [void][Windows.MessageBox]::Show("Node.js 22 or newer is needed. Run install.ps1 again, or install it with:  winget install OpenJS.NodeJS.LTS", "Fumefy")
  & $spotify
  exit 1
}

# 4) Restart Spotify with the debug port. The port only listens on 127.0.0.1, and since
#    --remote-allow-origins is not passed, web pages in a browser cannot connect to it.
Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$spArgs = @("--remote-debugging-port=9222")
if ($Startup) { $spArgs += "--autostart", "--minimized" }   # same flags Spotify uses for its own autostart
Start-Process $spotify -ArgumentList $spArgs

$inject = Join-Path $here "inject.mjs"
if ($Watch) {
  & $node $inject --host --watch
} else {
  # exits on its own when Spotify closes
  Start-Process $node -ArgumentList "`"$inject`"", "--host" -WindowStyle Hidden
}
