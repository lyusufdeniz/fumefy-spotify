# Builds the shortcut icon from the Spotify app installed on this PC, recolored to smoke gray.
# Spotify's logo is not shipped with Fumefy; it is read from your own Spotify install at setup time.
# Usage: .\make-icon.ps1 -Out <path.ico> [-Color "#64666b"]
param([Parameter(Mandatory)][string]$Out, [string]$Color = "#64666b", [string]$Preview)
Add-Type -AssemblyName System.Drawing

# 1) source image: the Microsoft Store package's app icon, or the classic Spotify.exe icon
$src = $null
$pkg = Get-AppxPackage -Name "SpotifyAB.SpotifyMusic" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) {
  $png = Get-ChildItem (Join-Path $pkg.InstallLocation "Assets") -Filter "Square44x44Logo.targetsize-256_altform-unplated.png" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($png) { $src = [System.Drawing.Bitmap]::new($png.FullName) }
}
if (-not $src) {
  $exe = Join-Path $env:APPDATA "Spotify\Spotify.exe"
  if (Test-Path $exe) { $src = [System.Drawing.Icon]::ExtractAssociatedIcon($exe).ToBitmap() }
}
if (-not $src) { Write-Host "Spotify icon not found; the shortcut keeps a default icon."; exit 1 }

# 2) recolor: the colored (green) parts become smoke gray, dark and transparent parts stay as they are
$c = [System.Drawing.ColorTranslator]::FromHtml($Color)
$bmp = [System.Drawing.Bitmap]::new($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $src.Height; $y++) {
  for ($x = 0; $x -lt $src.Width; $x++) {
    $p = $src.GetPixel($x, $y)
    if ($p.A -eq 0) { continue }
    $sat = $p.GetSaturation(); $max = [Math]::Max($p.R, [Math]::Max($p.G, $p.B)) / 255.0
    if ($sat -gt 0.25 -and $max -gt 0.2) {
      # keep the original shading: scale the smoke color by how bright this pixel was relative to the logo green
      $k = [Math]::Min(1.15, $max / 0.84)
      $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($p.A, [int][Math]::Min(255, $c.R * $k), [int][Math]::Min(255, $c.G * $k), [int][Math]::Min(255, $c.B * $k)))
    } else {
      $bmp.SetPixel($x, $y, $p)
    }
  }
}

if ($Preview) { $bmp.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png) }

# 3) write a multi-size .ico (PNG-compressed entries)
$sizes = 256, 64, 48, 32, 16
$pngs = foreach ($s in $sizes) {
  $r = [System.Drawing.Bitmap]::new($s, $s)
  $g = [System.Drawing.Graphics]::FromImage($r); $g.InterpolationMode = "HighQualityBicubic"; $g.SmoothingMode = "AntiAlias"
  $g.DrawImage($bmp, 0, 0, $s, $s); $g.Dispose()
  $ms = New-Object IO.MemoryStream; $r.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); , ($ms.ToArray())
}
New-Item -ItemType Directory -Path (Split-Path $Out) -Force | Out-Null
$fs = [IO.File]::Create($Out); $bw = New-Object IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $d = $pngs[$i]; $b = if ($s -ge 256) { 0 } else { $s }
  $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([UInt16]1); $bw.Write([UInt16]32); $bw.Write([UInt32]$d.Length); $bw.Write([UInt32]$offset); $offset += $d.Length
}
foreach ($d in $pngs) { $bw.Write($d) }
$bw.Close()
Write-Host "Icon written: $Out"
