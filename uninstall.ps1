# Removes Fumefy: stops it, deletes the shortcuts and %LOCALAPPDATA%\Fumefy.
# Spotify itself is not touched; it simply starts without the theme afterwards.
$ErrorActionPreference = "SilentlyContinue"
$dest = Join-Path $env:LOCALAPPDATA "Fumefy"

# stop the injector, the window helper and the widgets
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'Fumefy|fumefy' -and $_.CommandLine -match 'inject\.mjs|window\.ps1|tray\.ps1' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item (Join-Path ([Environment]::GetFolderPath("Programs")) "Spotify (Fumefy).lnk") -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath("Desktop")) "Spotify (Fumefy).lnk") -Force

# this script may be running from that folder: delete it a moment after we exit
Start-Process cmd.exe -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$dest`"" -WindowStyle Hidden
Write-Host "Fumefy was removed. Restart Spotify to see it without the theme."
