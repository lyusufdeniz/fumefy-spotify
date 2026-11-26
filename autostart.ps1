# Start with Windows: Fumefy takes the place of Spotify's own autostart.
#   .\autostart.ps1 -Enable    -> Fumefy starts Spotify (minimized, themed) at sign-in; Spotify's own autostart is turned off
#   .\autostart.ps1 -Disable   -> Fumefy's entry is removed and Spotify's own autostart is put back as it was
#   .\autostart.ps1            -> prints "on" or "off"
# Spotify's previous setting is saved in autostart-backup.json so -Disable can restore it exactly.
param([switch]$Enable, [switch]$Disable)
$ErrorActionPreference = "SilentlyContinue"
$here = $PSScriptRoot
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$backupFile = Join-Path $here "autostart-backup.json"

# Microsoft Store Spotify: a startup task. State 2 = on, 1 = turned off by the user, 0 = off
function Store-TaskKey {
  $base = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData"
  Get-ChildItem $base | Where-Object { $_.PSChildName -like "SpotifyAB.SpotifyMusic_*" } | ForEach-Object {
    Get-ChildItem $_.PSPath | Where-Object { $null -ne (Get-ItemProperty $_.PSPath).State } | Select-Object -First 1 -ExpandProperty PSPath
  } | Select-Object -First 1
}

if ($Enable) {
  $backup = [pscustomobject]@{}
  if (Test-Path $backupFile) { try { $backup = Get-Content $backupFile -Raw | ConvertFrom-Json } catch {} }
  $task = Store-TaskKey
  if ($task) {
    if ($null -eq $backup.storeState) { $backup | Add-Member -NotePropertyName storeState -NotePropertyValue ((Get-ItemProperty $task).State) -Force }
    Set-ItemProperty $task -Name State -Value 1 -Type DWord
  }
  $classic = (Get-ItemProperty $runKey).Spotify
  if ($classic) {
    if (-not $backup.classicRun) { $backup | Add-Member -NotePropertyName classicRun -NotePropertyValue $classic -Force }
    Remove-ItemProperty $runKey -Name Spotify
  }
  $backup | ConvertTo-Json -Compress | Set-Content $backupFile -Encoding ASCII
  $vbs = Join-Path $here "Fumefy.vbs"
  Set-ItemProperty $runKey -Name "Fumefy" -Value ("`"$env:WINDIR\System32\wscript.exe`" `"$vbs`" /startup")
  "on"
} elseif ($Disable) {
  Remove-ItemProperty $runKey -Name "Fumefy"
  if (Test-Path $backupFile) {
    try {
      $backup = Get-Content $backupFile -Raw | ConvertFrom-Json
      $task = Store-TaskKey
      if ($task -and $null -ne $backup.storeState) { Set-ItemProperty $task -Name State -Value ([int]$backup.storeState) -Type DWord }
      if ($backup.classicRun) { Set-ItemProperty $runKey -Name Spotify -Value $backup.classicRun }
    } catch {}
    Remove-Item $backupFile -Force
  }
  "off"
} else {
  if ((Get-ItemProperty $runKey).Fumefy) { "on" } else { "off" }
}
