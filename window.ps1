# Windows helper for the Spotify window. Started by inject.mjs --host; reads commands from stdin:
#   round <radius>              round the corners (0 = off)
#   alpha <30-100>              window opacity
#   islands x,y,w,h,r ...       island mode: clip the window to just these rounded rectangles
#   islands                     turn island mode off
#   min | max | close | drag    window buttons and window dragging
#   quit                        exit (restores the window)
$ErrorActionPreference = "Stop"
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
  [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int x1, int y1, int x2, int y2);
  [DllImport("gdi32.dll")] public static extern int CombineRgn(IntPtr dst, IntPtr a, IntPtr b, int mode);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
  [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public int dwFlags; }
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, int flags);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT { public int length; public int flags; public int showCmd; public POINT ptMin; public POINT ptMax; public RECT rcNormal; }
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
  public delegate bool EnumCb(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumCb cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, int cmd);
  // Returns the largest visible, unowned window of the given processes (the main window, not the mini player)
  public static IntPtr Largest(uint[] pids) {
    IntPtr best = IntPtr.Zero; long bestArea = -1;
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (Array.IndexOf(pids, p) < 0 || !IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero) return true;
      WINDOWPLACEMENT wp = new WINDOWPLACEMENT(); wp.length = Marshal.SizeOf(wp); GetWindowPlacement(h, ref wp);
      RECT r = wp.rcNormal;   // compare by normal size, even when minimized
      long a = (long)(r.R - r.L) * (r.B - r.T);
      if (a > bestArea) { bestArea = a; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
"@
[W]::SetProcessDPIAware() | Out-Null

function Get-SpotifyWindow {
  # MainWindowHandle can point to the mini player; pick the largest visible window instead
  $pids = [uint32[]]@((Get-Process Spotify -ErrorAction SilentlyContinue).Id)
  if (-not $pids.Count) { return [IntPtr]::Zero }
  return [W]::Largest($pids)
}

$hwnd = Get-SpotifyWindow
$radius = 0
$islands = ""    # "x,y,w,h,r x,y,w,h,r ..." (relative to the client area, physical pixels)
$wholeCut = 0    # Whole shape: strip to cut from the top (physical pixels), 0 = off
$wholeR = 0      # corner radius in Whole shape
$applied = ""    # key of the last applied state; if unchanged, the region is not rebuilt

function Update-Region {
  if ($script:hwnd -eq [IntPtr]::Zero -or -not [W]::IsWindow($script:hwnd)) {
    $script:hwnd = Get-SpotifyWindow; $script:applied = ""
    if ($script:hwnd -ne [IntPtr]::Zero) {   # also apply opacity and the shadow setting to the new window
      Set-Alpha; $script:shadowOff = $false
      if ($script:islands -or $script:wholeCut -gt 0) { Set-Shadow $true }
    }
  }
  if ($script:hwnd -eq [IntPtr]::Zero) { return }
  $r = New-Object W+RECT
  [W]::GetWindowRect($script:hwnd, [ref]$r) | Out-Null
  $w = $r.R - $r.L; $h = $r.B - $r.T
  # position of the client area inside the window (when maximized the window edge can extend off-screen)
  $o = New-Object W+POINT
  [W]::ClientToScreen($script:hwnd, [ref]$o) | Out-Null
  $ox = $o.X - $r.L; $oy = $o.Y - $r.T

  if ($script:wholeCut -gt 0) {
    # Whole shape: the top strip (Spotify's buttons) is cut off. Since Windows pins the window in real
    # maximized state, we use a "pseudo-maximize": the window stays normal but covers the work area
    # and extends upward by the strip height, so no gap is left at the top of the screen.
    if ([W]::IsZoomed($script:hwnd)) {
      $wp = New-Object W+WINDOWPLACEMENT; $wp.length = [Runtime.InteropServices.Marshal]::SizeOf($wp)
      [W]::GetWindowPlacement($script:hwnd, [ref]$wp) | Out-Null
      $script:savedNormal = $wp.rcNormal        # position to return to on restore
      [W]::ShowWindow($script:hwnd, 9) | Out-Null   # SW_RESTORE
      Enter-PseudoMax
      [W]::GetWindowRect($script:hwnd, [ref]$r) | Out-Null
      $w = $r.R - $r.L; $h = $r.B - $r.T
      $o = New-Object W+POINT; [W]::ClientToScreen($script:hwnd, [ref]$o) | Out-Null
      $ox = $o.X - $r.L; $oy = $o.Y - $r.T
    }
    elseif ($script:pseudoMax) {
      # if the user dragged the maximized window: restore it to its previous size like Windows does,
      # keeping the cursor at the same relative spot (otherwise the screen-sized window slides off-screen)
      $p = $script:pmRect
      if ($r.L -ne $p.L -or $r.T -ne $p.T -or $r.R -ne $p.R -or $r.B -ne $p.B) {
        $script:pseudoMax = $false
        $n = $script:savedNormal
        # if the size is unchanged (only moved), this is a drag: restore the previous size
        if ($n -and ($w -eq ($p.R - $p.L)) -and ($h -eq ($p.B - $p.T))) {
          $nw = $n.R - $n.L; $nh = $n.B - $n.T
          $c = New-Object W+POINT; [W]::GetCursorPos([ref]$c) | Out-Null
          $nx = [int]($c.X - ($c.X - $r.L) * $nw / [Math]::Max(1, $w))
          $ny = [int]($r.T)
          [W]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $nx, $ny, $nw, $nh, 0x14) | Out-Null
          [W]::GetWindowRect($script:hwnd, [ref]$r) | Out-Null
          $w = $r.R - $r.L; $h = $r.B - $r.T
          $o = New-Object W+POINT; [W]::ClientToScreen($script:hwnd, [ref]$o) | Out-Null
          $ox = $o.X - $r.L; $oy = $o.Y - $r.T
        }
      }
    }
    $zoomed = $script:pseudoMax   # square corners when maximized
    # how far the window top is off-screen when maximized: if less than the cut strip, show the difference too
    $visTop = $script:wholeCut
    if ($zoomed) {
      $mi = New-Object W+MONITORINFO; $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
      [W]::GetMonitorInfo([W]::MonitorFromWindow($script:hwnd, 2), [ref]$mi) | Out-Null
      $visTop = [Math]::Max(0, [Math]::Min($script:wholeCut, $mi.rcWork.T - $o.Y))
    }
    $want = "whole $w $h $ox $oy $($script:wholeCut) $($script:wholeR) $zoomed $visTop"
  }
  elseif ($script:islands) { $want = "isl $w $h $ox $oy $($script:islands)" }
  elseif ($script:radius -le 0 -or [W]::IsZoomed($script:hwnd)) { $want = "none" }
  else { $want = "$w x $h x $($script:radius)" }
  if ($want -eq $script:applied) { return }

  if ($want -eq "none") { [W]::SetWindowRgn($script:hwnd, [IntPtr]::Zero, $true) | Out-Null }
  elseif ($script:wholeCut -gt 0) {
    $cr = New-Object W+RECT; [W]::GetClientRect($script:hwnd, [ref]$cr) | Out-Null
    $d = if ($zoomed) { 0 } else { $script:wholeR * 2 }
    $rgn = [W]::CreateRoundRectRgn($ox, $oy + $script:wholeCut, $ox + $cr.R + 1, $oy + $cr.B + 1, $d, $d)
    if ($visTop -lt $script:wholeCut) {
      # when maximized, also fill the small gap at the very top of the screen; leave out the
      # top-right corner where Spotify's buttons sit (~140 px from the right)
      $extra = [W]::CreateRectRgn($ox, $oy + $visTop, $ox + $cr.R - 140, $oy + $script:wholeCut + 1)
      [W]::CombineRgn($rgn, $rgn, $extra, 2) | Out-Null
      [W]::DeleteObject($extra) | Out-Null
    }
    [W]::SetWindowRgn($script:hwnd, $rgn, $true) | Out-Null
  }
  elseif ($script:islands) {
    $rgn = [W]::CreateRectRgn(0, 0, 0, 0)
    foreach ($isl in $script:islands.Split(" ")) {
      $v = $isl.Split(",") | ForEach-Object { [int]$_ }
      $x = $v[0] + $ox; $y = $v[1] + $oy; $d = [Math]::Max(0, $v[4] * 2)
      $piece = [W]::CreateRoundRectRgn($x, $y, $x + $v[2] + 1, $y + $v[3] + 1, $d, $d)
      [W]::CombineRgn($rgn, $rgn, $piece, 2) | Out-Null    # RGN_OR
      [W]::DeleteObject($piece) | Out-Null
    }
    [W]::SetWindowRgn($script:hwnd, $rgn, $true) | Out-Null   # the window now owns the region
  }
  else {
    $d = $script:radius * 2
    $rgn = [W]::CreateRoundRectRgn(0, 0, $w + 1, $h + 1, $d, $d)
    [W]::SetWindowRgn($script:hwnd, $rgn, $true) | Out-Null
  }
  $script:applied = $want
}

# Window opacity (30-100%). At 100% the layered window style is removed entirely.
$alpha = 100
function Set-Alpha {
  if ($script:hwnd -eq [IntPtr]::Zero) { return }
  $ex = [W]::GetWindowLongPtr($script:hwnd, -20).ToInt64()   # GWL_EXSTYLE
  if ($script:alpha -ge 100) {
    if ($ex -band 0x80000) { [W]::SetWindowLongPtr($script:hwnd, -20, [IntPtr]($ex -band (-bnot 0x80000))) | Out-Null }
  } else {
    if (-not ($ex -band 0x80000)) { [W]::SetWindowLongPtr($script:hwnd, -20, [IntPtr]($ex -bor 0x80000)) | Out-Null }   # WS_EX_LAYERED
    [W]::SetLayeredWindowAttributes($script:hwnd, 0, [byte][Math]::Round($script:alpha * 2.55), 2) | Out-Null       # LWA_ALPHA
  }
}

# Pseudo-maximize (for Whole shape): covers the work area, with the top off-screen by the cut strip height
$pseudoMax = $false
$savedNormal = $null
function Get-PseudoMaxRect {
  $mi = New-Object W+MONITORINFO; $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
  [W]::GetMonitorInfo([W]::MonitorFromWindow($script:hwnd, 2), [ref]$mi) | Out-Null
  $wa = $mi.rcWork
  return @($wa.L, ($wa.T - $script:wholeCut), ($wa.R - $wa.L), ($wa.B - $wa.T + $script:wholeCut))
}
$pmRect = $null   # position/size Windows actually gave in pseudo-maximize
function Enter-PseudoMax {
  $t = Get-PseudoMaxRect
  # SWP_NOSENDCHANGING (0x400): skip Windows' "can't be much larger than the screen" limit, so the window
  # can be tall enough to push Spotify's buttons fully off-screen (otherwise a thin strip remains at the top)
  [W]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $t[0], $t[1], $t[2], $t[3], 0x14 -bor 0x400) | Out-Null   # NOZORDER | NOACTIVATE | NOSENDCHANGING
  # Windows won't make the window much larger than the screen (at most ~screen+20 px). If it ends up shorter
  # than requested, align it to the bottom so no gap is left above the taskbar; the small top gap is shown in Update-Region.
  $r = New-Object W+RECT; [W]::GetWindowRect($script:hwnd, [ref]$r) | Out-Null
  $waB = $t[1] + $t[3]
  if ($r.B -lt $waB) {
    [W]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $r.L, ($waB - ($r.B - $r.T)), 0, 0, 0x15) | Out-Null   # NOSIZE
    [W]::GetWindowRect($script:hwnd, [ref]$r) | Out-Null
  }
  $script:pmRect = $r
  $script:pseudoMax = $true; $script:applied = ""
}
function Exit-PseudoMax {
  $n = $script:savedNormal
  if ($n) { [W]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $n.L, $n.T, ($n.R - $n.L), ($n.B - $n.T), 0x14) | Out-Null }
  $script:pseudoMax = $false; $script:applied = ""
}

# Windows draws the window shadow around the full rectangle, so in island mode it shows behind the cut-out areas.
# While island mode is on we disable the window's DWM frame rendering (shadow included) and re-enable it afterwards.
$shadowOff = $false
function Set-Shadow([bool]$off) {
  if ($script:hwnd -eq [IntPtr]::Zero -or $off -eq $script:shadowOff) { return }
  $v = if ($off) { 1 } else { 0 }   # DWMNCRP_DISABLED / DWMNCRP_USEWINDOWSTYLE
  [W]::DwmSetWindowAttribute($script:hwnd, 2, [ref]$v, 4) | Out-Null   # DWMWA_NCRENDERING_POLICY
  [W]::SetWindowPos($script:hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x37) | Out-Null   # redraw the frame
  $script:shadowOff = $off
}

# Dragging / resizing. Sending Windows a "border clicked" message doesn't work: Spotify (Chromium)
# captures the mouse on press and ignores that external message. So while the left mouse button
# is held, we move / resize the window ourselves following the cursor.
#   2 = move, 12 = top edge, 13 = top-left corner, 14 = top-right corner
$MIN_W = 800; $MIN_H = 500
function Start-NcDrag([int]$hit) {
  if ($script:hwnd -eq [IntPtr]::Zero) { return }
  $p0 = New-Object W+POINT; [W]::GetCursorPos([ref]$p0) | Out-Null
  $r0 = New-Object W+RECT; [W]::GetWindowRect($script:hwnd, [ref]$r0) | Out-Null
  $script:pseudoMax = $false
  $last = ""
  $deadline = [DateTime]::Now.AddSeconds(60)   # safety: don't get stuck
  while (([W]::GetAsyncKeyState(0x01) -band 0x8000) -and [DateTime]::Now -lt $deadline) {   # VK_LBUTTON held
    $p = New-Object W+POINT; [W]::GetCursorPos([ref]$p) | Out-Null
    $dx = $p.X - $p0.X; $dy = $p.Y - $p0.Y
    $L = $r0.L; $T = $r0.T; $R = $r0.R; $B = $r0.B
    if ($hit -eq 2) { $L += $dx; $R += $dx; $T += $dy; $B += $dy }
    else {
      $T = [Math]::Min($r0.T + $dy, $B - $MIN_H)                          # top edge
      if ($hit -eq 13) { $L = [Math]::Min($r0.L + $dx, $R - $MIN_W) }     # top-left
      if ($hit -eq 14) { $R = [Math]::Max($r0.R + $dx, $L + $MIN_W) }     # top-right
    }
    $key = "$L $T $R $B"
    if ($key -ne $last) {
      [W]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $L, $T, ($R - $L), ($B - $T), 0x14) | Out-Null   # NOZORDER | NOACTIVATE
      Update-Region   # rebuild the shape for the new size right away
      $last = $key
    }
    Start-Sleep -Milliseconds 15
  }
}
function Start-Drag { Start-NcDrag 2 }

$in = New-Object System.IO.StreamReader([Console]::OpenStandardInput())
$pending = $in.ReadLineAsync()
while ($true) {
  if ($pending.IsCompleted) {
    $line = $pending.Result
    if ($null -eq $line) { break }      # node exited
    $parts = $line.Trim().Split(" ", 2)
    switch ($parts[0]) {
      "round"   { $radius = [int]$parts[1]; $applied = "" }
      "alpha"   { $alpha = [Math]::Max(30, [Math]::Min(100, [int]$parts[1])); Set-Alpha }
      "islands" { $islands = if ($parts.Length -gt 1) { $parts[1].Trim() } else { "" }; Set-Shadow ([bool]$islands -or $wholeCut -gt 0) }
      "whole"   {
        if ($parts.Length -gt 1) { $v = $parts[1].Trim().Split(" "); $wholeCut = [int]$v[0]; $wholeR = [int]$v[1] }
        else {
          # Whole is turning off: if pseudo-maximized, switch to real maximize
          if ($pseudoMax) { $pseudoMax = $false; [W]::ShowWindow($hwnd, 3) | Out-Null }
          $wholeCut = 0
        }
        $applied = ""; Set-Shadow ([bool]$islands -or $wholeCut -gt 0)
      }
      "min"     { [W]::ShowWindow($hwnd, 6) | Out-Null }                                            # SW_MINIMIZE
      "max"     {
        if ($wholeCut -gt 0) {   # toggle pseudo-maximize in Whole shape
          if ($pseudoMax) { Exit-PseudoMax }
          else { $cur = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$cur) | Out-Null; $savedNormal = $cur; Enter-PseudoMax }
        }
        elseif ([W]::IsZoomed($hwnd)) { [W]::ShowWindow($hwnd, 9) | Out-Null } else { [W]::ShowWindow($hwnd, 3) | Out-Null }   # RESTORE / MAXIMIZE
      }
      "show"    { if ([W]::IsIconic($hwnd)) { [W]::ShowWindow($hwnd, 9) | Out-Null }; [W]::SetForegroundWindow($hwnd) | Out-Null }   # bring Spotify to the front (taskbar player)
      "close"   { [W]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }       # WM_CLOSE
      "drag"    { Start-Drag }
      "size"    { $hit = [int]$parts[1]; if (@(12, 13, 14) -contains $hit) { Start-NcDrag $hit } }
    }
    if ($parts[0] -eq "quit") { break }
    $pending = $in.ReadLineAsync()
  }
  Update-Region
  Start-Sleep -Milliseconds 60
}
# restore the window on exit
if ($hwnd -ne [IntPtr]::Zero -and [W]::IsWindow($hwnd)) {
  [W]::SetWindowRgn($hwnd, [IntPtr]::Zero, $true) | Out-Null
  $alpha = 100; Set-Alpha
  Set-Shadow $false
}
