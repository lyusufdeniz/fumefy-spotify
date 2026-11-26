# Fumefy taskbar mini player.
# Started by inject.mjs (--host). Reads "np {json}" lines on stdin (the current song) and writes
# "cmd prev|play|next|show|volup|voldown|mute|like|vol N" lines on stdout when its buttons are clicked. "quit" on stdin closes it.
# It sits on the taskbar, just left of the notification area, and hides when nothing is playing.
# -Snapshot <png>: (for screenshots / tests) render itself to a PNG after the first song and exit.
param([string]$Snapshot)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TB {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string name);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string name);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
  [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr parent);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public static string ClassOf(IntPtr h) { var sb = new System.Text.StringBuilder(64); GetClassName(h, sb, 64); return sb.ToString(); }
}
"@

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False"
        Topmost="True" ResizeMode="NoResize" Width="360" Height="38" ShowActivated="False"
        FontFamily="Segoe UI Variable Text, Segoe UI">
  <Border x:Name="Pill" CornerRadius="19" Background="#EB1C1D20" BorderBrush="#22FFFFFF" BorderThickness="1" ClipToBounds="True">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Border x:Name="CoverBox" Grid.Column="0" Width="26" Height="26" CornerRadius="13" Margin="5,0,8,0" Background="#33FFFFFF" Cursor="Hand">
        <Border.Clip><EllipseGeometry Center="13,13" RadiusX="13" RadiusY="13"/></Border.Clip>
        <Image x:Name="Cover" Stretch="UniformToFill"/>
      </Border>
      <StackPanel x:Name="Info" Grid.Column="1" VerticalAlignment="Center" Cursor="Hand" ClipToBounds="True">
        <TextBlock x:Name="Title" Foreground="White" FontSize="12" LineHeight="15" LineStackingStrategy="BlockLineHeight" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
        <TextBlock x:Name="Artist" Foreground="#A7A9B0" FontSize="11" LineHeight="14" LineStackingStrategy="BlockLineHeight" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
      <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="4,0,6,0">
        <Button x:Name="Like" Width="28" Height="28" ToolTip="Add to Liked Songs"/>
        <Button x:Name="Prev" Width="28" Height="28" ToolTip="Previous"/>
        <Button x:Name="Play" Width="30" Height="30" ToolTip="Play / Pause"/>
        <Button x:Name="Next" Width="28" Height="28" ToolTip="Next"/>
        <Button x:Name="Vol" Width="28" Height="28" ToolTip="Volume (scroll to change)"/>
      </StackPanel>
      <Rectangle x:Name="Progress" Grid.ColumnSpan="3" Height="2" HorizontalAlignment="Left" VerticalAlignment="Bottom" Fill="#CCFFFFFF" Width="0" Margin="16,0,0,1" RadiusX="1" RadiusY="1"/>
    </Grid>
  </Border>
  <Window.Resources>
    <!-- thin rounded volume slider in the theme's style: white fill on a faint track, small round thumb -->
    <Style x:Key="FumeSlider" TargetType="Slider">
      <Setter Property="Height" Value="18"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid VerticalAlignment="Center" Height="18">
              <Border Height="4" CornerRadius="2" Background="#33FFFFFF" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track" VerticalAlignment="Center">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="Slider.DecreaseLarge" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Height="4" CornerRadius="2" Background="White" VerticalAlignment="Center"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="Slider.IncreaseLarge" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Focusable="False">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb"><Ellipse Width="12" Height="12" Fill="White"/></ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Popup x:Key="VolPopup" x:Name="VolPopup" Placement="Top" StaysOpen="False" AllowsTransparency="True" VerticalOffset="-8" HorizontalOffset="-70">
      <Border CornerRadius="14" Background="#F21C1D20" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="10,8" TextElement.FontFamily="Segoe UI Variable Text, Segoe UI">
        <StackPanel Orientation="Horizontal">
          <Slider x:Name="VolSlider" Style="{StaticResource FumeSlider}" Width="140" Minimum="0" Maximum="100" VerticalAlignment="Center" IsMoveToPointEnabled="True"/>
          <TextBlock x:Name="VolText" Width="34" Margin="8,0,0,0" Foreground="White" FontSize="12" VerticalAlignment="Center" TextAlignment="Right"/>
        </StackPanel>
      </Border>
    </Popup>
  </Window.Resources>
</Window>
"@

# Desktop widget: a bigger card that lives on the desktop (below other windows). Drag it anywhere;
# its position is remembered in widget.json next to this script.
$deskXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False"
        ResizeMode="NoResize" Width="400" Height="150" ShowActivated="False"
        FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <Style x:Key="FumeSlider" TargetType="Slider">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid VerticalAlignment="Center" Height="16">
              <Border Height="4" CornerRadius="2" Background="#33FFFFFF" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track" VerticalAlignment="Center">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="Slider.DecreaseLarge" Focusable="False">
                    <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Height="4" CornerRadius="2" Background="White" VerticalAlignment="Center"/></ControlTemplate></RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="Slider.IncreaseLarge" Focusable="False">
                    <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Focusable="False"><Thumb.Template><ControlTemplate TargetType="Thumb"><Ellipse Width="11" Height="11" Fill="White"/></ControlTemplate></Thumb.Template></Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="DCard" CornerRadius="22" Background="#E6141517" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Border x:Name="DCover" Width="120" Height="120" CornerRadius="14" Background="#26FFFFFF" Cursor="Hand"/>
      <Grid Grid.Column="1" Margin="14,2,0,0">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="DTitle" Foreground="White" FontSize="15" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" Cursor="Hand"/>
        <TextBlock x:Name="DArtist" Grid.Row="1" Foreground="#A7A9B0" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
        <Grid Grid.Row="3" Height="4" Margin="0,0,0,8">
          <Border CornerRadius="2" Background="#26FFFFFF"/>
          <Border x:Name="DProgress" CornerRadius="2" Background="White" HorizontalAlignment="Left" Width="0"/>
        </Grid>
        <Grid Grid.Row="4">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="DPrev" Width="30" Height="30" ToolTip="Previous"/>
            <Button x:Name="DPlay" Width="34" Height="34" ToolTip="Play / Pause" Margin="2,0"/>
            <Button x:Name="DNext" Width="30" Height="30" ToolTip="Next"/>
            <Button x:Name="DLike" Width="30" Height="30" ToolTip="Add to Liked Songs" Margin="4,0,0,0"/>
          </StackPanel>
          <Button x:Name="DVol" Grid.Column="2" Width="28" Height="28" ToolTip="Mute"/>
          <Slider x:Name="DVolSlider" Grid.Column="1" Style="{StaticResource FumeSlider}" Minimum="0" Maximum="100" Margin="10,0,4,0" VerticalAlignment="Center" IsMoveToPointEnabled="True"/>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$app = New-Object Windows.Application
$app.ShutdownMode = "OnExplicitShutdown"
$win = [Windows.Markup.XamlReader]::Parse($xaml)
$desk = [Windows.Markup.XamlReader]::Parse($deskXaml)
# Owners decide what survives "Show desktop" (Win+D / the taskbar corner) and Alt+Tab:
#  - the taskbar player is embedded in the taskbar as a child window (see SourceInitialized below)
#  - the desktop widget is owned by the desktop window (Program Manager): it stays on the desktop
$tbOwner = [TB]::FindWindow("Shell_TrayWnd", $null)
$deskOwner = [TB]::FindWindow("Progman", $null)
if ($deskOwner -ne [IntPtr]::Zero) { (New-Object Windows.Interop.WindowInteropHelper($desk)).Owner = $deskOwner }
$dget = { param($n) $desk.FindName($n) }
$get = { param($n) $win.FindName($n) }
$title = & $get "Title"; $artist = & $get "Artist"; $cover = & $get "Cover"; $progress = & $get "Progress"
$pill = & $get "Pill"

# Round, flat icon buttons (Segoe Fluent Icons / Segoe MDL2 Assets glyphs)
$iconFont = New-Object Windows.Media.FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
$btnTemplate = [Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border x:Name="B" CornerRadius="15" Background="Transparent" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#22FFFFFF"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Background" Value="#33FFFFFF"/></Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
"@)
$GLYPH = @{ Prev = [char]0xE892; Next = [char]0xE893; Play = [char]0xE768; Pause = [char]0xE769; Heart = [char]0xEB51; HeartFill = [char]0xEB52 }
foreach ($n in "Like", "Prev", "Play", "Next", "Vol") {
  $b = & $get $n
  $b.Template = $btnTemplate
  $b.FontFamily = $iconFont
  $b.Foreground = [Windows.Media.Brushes]::White
  $b.FontSize = if ($n -eq "Play") { 14 } else { 12 }
  $b.Content = if ($n -eq "Vol") { [char]0xE995 } elseif ($n -eq "Like") { $GLYPH.Heart } else { $GLYPH[$n] }
  $b.Focusable = $false
}

$out = [Console]::Out
function Send-Cmd([string]$c) { $out.WriteLine("cmd $c"); $out.Flush() }
(& $get "Prev").Add_Click({ Send-Cmd "prev" })
(& $get "Play").Add_Click({ Send-Cmd "play" })
(& $get "Next").Add_Click({ Send-Cmd "next" })
# Like: not liked yet -> one click adds it to Liked Songs. Already liked -> Spotify opens its "add to playlist"
# menu on that button, so bring Spotify to the front first to show it.
$script:liked = $false
$onBrush = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(0x60, 0xCD, 0xFF))   # same "on" color as in the app
function Like-Click { if ($script:liked) { Send-Cmd "show" }; Send-Cmd "like" }
(& $get "Like").Add_Click({ Like-Click })
(& $get "CoverBox").Add_MouseLeftButtonUp({ Send-Cmd "show" })
(& $get "Info").Add_MouseLeftButtonUp({ Send-Cmd "show" })

# Volume: the speaker button opens a slider above it; scrolling anywhere on the player changes it in 5% steps
$volBtn = & $get "Vol"
$popup = $win.Resources["VolPopup"]
$popup.PlacementTarget = $volBtn
$slider = $popup.Child.Child.Children[0]
$volText = $popup.Child.Child.Children[1]
$script:volume = 0; $script:fromSpotify = $false; $script:volSend = -1
function Vol-Glyph([double]$v) { if ($v -le 0) { [char]0xE74F } elseif ($v -lt 34) { [char]0xE993 } elseif ($v -lt 67) { [char]0xE994 } else { [char]0xE995 } }
$volBtn.Add_Click({ $popup.IsOpen = -not $popup.IsOpen })
$volBtn.Add_MouseRightButtonUp({ Send-Cmd "mute" })
$slider.Add_ValueChanged({
  $volText.Text = "{0}%" -f [int]$slider.Value
  if (-not $script:fromSpotify) { $script:volSend = [int]$slider.Value }   # sent by the timer, not on every pixel
})
$win.Add_MouseWheel({ param($s, $e) if ($e.Delta -gt 0) { Send-Cmd "volup" } else { Send-Cmd "voldown" } })

# ---- desktop widget controls ----
foreach ($n in "DLike", "DPrev", "DPlay", "DNext", "DVol") {
  $b = & $dget $n
  $b.Template = $btnTemplate
  $b.FontFamily = $iconFont
  $b.Foreground = [Windows.Media.Brushes]::White
  $b.FontSize = if ($n -eq "DPlay") { 16 } else { 13 }
  $b.Focusable = $false
}
(& $dget "DPrev").Content = $GLYPH.Prev; (& $dget "DNext").Content = $GLYPH.Next; (& $dget "DPlay").Content = $GLYPH.Play
(& $dget "DPrev").Add_Click({ Send-Cmd "prev" })
(& $dget "DPlay").Add_Click({ Send-Cmd "play" })
(& $dget "DNext").Add_Click({ Send-Cmd "next" })
(& $dget "DVol").Add_Click({ Send-Cmd "mute" })
(& $dget "DLike").Content = $GLYPH.Heart
(& $dget "DLike").Add_Click({ Like-Click })
(& $dget "DCover").Add_MouseLeftButtonUp({ Send-Cmd "show" })
(& $dget "DTitle").Add_MouseLeftButtonUp({ Send-Cmd "show" })
$dSlider = & $dget "DVolSlider"
$dSlider.Add_ValueChanged({ if (-not $script:fromSpotify) { $script:volSend = [int]$dSlider.Value } })
$desk.Add_MouseWheel({ param($s, $e) if ($e.Delta -gt 0) { Send-Cmd "volup" } else { Send-Cmd "voldown" } })
# drag anywhere on the card (buttons and the slider keep their own clicks)
(& $dget "DCard").Add_MouseLeftButtonDown({ param($s, $e)
  if ($e.OriginalSource -is [Windows.Controls.Primitives.Thumb] -or $e.OriginalSource -is [Windows.Controls.Primitives.RepeatButton]) { return }
  try { $desk.DragMove(); Save-DeskPos } catch {}
})
$posFile = Join-Path $PSScriptRoot "widget.json"
function Save-DeskPos { try { @{ left = [int]$desk.Left; top = [int]$desk.Top } | ConvertTo-Json -Compress | Set-Content $posFile -Encoding ASCII } catch {} }
function Place-Desk {
  $wa = [Windows.SystemParameters]::WorkArea
  $pos = $null
  if (Test-Path $posFile) { try { $pos = Get-Content $posFile -Raw | ConvertFrom-Json } catch {} }
  if ($pos -and $pos.left -ge $wa.Left - 300 -and $pos.left -le $wa.Right - 60 -and $pos.top -ge $wa.Top -and $pos.top -le $wa.Bottom - 60) {
    $desk.Left = $pos.left; $desk.Top = $pos.top
  } else {
    $desk.Left = $wa.Right - $desk.Width - 24; $desk.Top = $wa.Bottom - $desk.Height - 24   # bottom right by default
  }
}
# stay on the desktop layer: below other windows, also after it was clicked
$script:dhwnd = [IntPtr]::Zero
function Send-DeskBack { if ($script:dhwnd -ne [IntPtr]::Zero) { [TB]::SetWindowPos($script:dhwnd, [IntPtr]1, 0, 0, 0, 0, 0x0013) | Out-Null } }   # HWND_BOTTOM
$desk.Add_SourceInitialized({
  $script:dhwnd = (New-Object Windows.Interop.WindowInteropHelper($desk)).Handle
  $ex = [TB]::GetWindowLong($script:dhwnd, -20)
  [TB]::SetWindowLong($script:dhwnd, -20, ($ex -bor 0x80 -bor 0x08000000)) | Out-Null   # tool window, never takes focus
})
$desk.Add_Deactivated({ Send-DeskBack })

# Which widgets are on (sent by the mod's menu as "cfg {json}")
$script:cfg = @{ taskbar = $true; desktop = $false }
$script:lastNp = $null

# Place on the taskbar, just left of the notification area (clock, tray icons)
$script:hwnd = [IntPtr]::Zero
$script:embedded = $false
function Place {
  $tray = [TB]::FindWindow("Shell_TrayWnd", $null)
  if ($tray -eq [IntPtr]::Zero) { return }
  $r = New-Object TB+RECT; [TB]::GetWindowRect($tray, [ref]$r) | Out-Null
  $scale = [TB]::GetDpiForSystem() / 96.0
  $notify = [TB]::FindWindowEx($tray, [IntPtr]::Zero, "TrayNotifyWnd", $null)
  $right = $r.Right
  if ($notify -ne [IntPtr]::Zero) { $n = New-Object TB+RECT; [TB]::GetWindowRect($notify, [ref]$n) | Out-Null; if ($n.Left -gt $r.Left) { $right = $n.Left } }
  $tbH = ($r.Bottom - $r.Top) / $scale
  $h = [Math]::Max(36, [Math]::Min(42, $tbH - 8))
  $win.Height = $h
  if ($script:embedded) {
    # a child of the taskbar: position relative to the taskbar, in physical pixels; HWND_TOP keeps it above the taskbar's own content
    $wpx = [int]($win.Width * $scale); $hpx = [int]($h * $scale)
    $x = ($right - $r.Left) - $wpx - [int](10 * $scale); $y = [int](($r.Bottom - $r.Top - $hpx) / 2)
    [TB]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $x, $y, $wpx, $hpx, 0x0010) | Out-Null   # SWP_NOACTIVATE
  } else {
    $win.Left = ($right / $scale) - $win.Width - 10
    $win.Top = ($r.Top / $scale) + ($tbH - $h) / 2
  }
}

# Keep it above the taskbar (the taskbar is topmost too and wins when clicked)
function Keep-OnTop {
  if ($script:embedded) { return }   # part of the taskbar: nothing to keep on top
  if ($script:hwnd -ne [IntPtr]::Zero) { [TB]::SetWindowPos($script:hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0013) | Out-Null }   # HWND_TOPMOST, NOSIZE|NOMOVE|NOACTIVATE
}

$win.Add_SourceInitialized({
  $script:hwnd = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle
  # tool window (not in Alt+Tab) that never takes focus
  $ex = [TB]::GetWindowLong($script:hwnd, -20)
  [TB]::SetWindowLong($script:hwnd, -20, ($ex -bor 0x80 -bor 0x08000000)) | Out-Null   # WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
  # Embed into the taskbar like a real taskbar toolbar: a child window of Shell_TrayWnd moves and hides
  # with the taskbar and is untouched by "Show desktop" and Alt+Tab.
  $taskbar = [TB]::FindWindow("Shell_TrayWnd", $null)
  if ($taskbar -ne [IntPtr]::Zero -and -not $Snapshot) {
    $style = [TB]::GetWindowLong($script:hwnd, -16)
    [TB]::SetWindowLong($script:hwnd, -16, (($style -band (-bnot 0x80000000)) -bor 0x40000000)) | Out-Null   # WS_POPUP -> WS_CHILD
    if ([TB]::SetParent($script:hwnd, $taskbar) -ne [IntPtr]::Zero -or $true) { $script:embedded = $true }
  }
})

$script:lastCover = ""
function Apply-NowPlaying($np) {
  $script:lastNp = $np
  if (-not $np -or -not $np.title) { $win.Hide(); $desk.Hide(); return }
  $playGlyph = if ($np.playing) { $GLYPH.Pause } else { $GLYPH.Play }
  $script:liked = [bool]$np.liked
  $likeGlyph = if ($script:liked) { $GLYPH.HeartFill } else { $GLYPH.Heart }
  $likeBrush = if ($script:liked) { $onBrush } else { [Windows.Media.Brushes]::White }
  $script:volume = [double]$np.volume
  if ($script:volSend -lt 0 -and -not $slider.IsMouseCaptureWithin -and -not $dSlider.IsMouseCaptureWithin) {
    $script:fromSpotify = $true; $slider.Value = $script:volume; $dSlider.Value = $script:volume; $script:fromSpotify = $false
  }
  if ($np.cover -and $np.cover -ne $script:lastCover) {
    $script:lastCover = $np.cover
    try {
      $bmp = New-Object Windows.Media.Imaging.BitmapImage
      $bmp.BeginInit(); $bmp.UriSource = [Uri]$np.cover; $bmp.DecodePixelWidth = 240; $bmp.EndInit()
      $cover.Source = $bmp
      $brush = New-Object Windows.Media.ImageBrush($bmp); $brush.Stretch = "UniformToFill"
      (& $dget "DCover").Background = $brush
    } catch { $cover.Source = $null }
  }

  # taskbar player
  if ($script:cfg.taskbar) {
    $title.Text = $np.title
    $artist.Text = $np.artist
    (& $get "Play").Content = $playGlyph
    (& $get "Like").Content = $likeGlyph
    (& $get "Like").Foreground = $likeBrush
    $volBtn.Content = Vol-Glyph $script:volume
    if (-not $win.IsVisible) { Place; $win.Show(); Place; Keep-OnTop }
    $win.UpdateLayout()
    $progress.Width = [Math]::Max(0, ($pill.ActualWidth - 32) * [double]$np.progress / 100)
  } elseif ($win.IsVisible) { $win.Hide() }

  # desktop widget
  if ($script:cfg.desktop) {
    (& $dget "DTitle").Text = $np.title
    (& $dget "DArtist").Text = $np.artist
    (& $dget "DPlay").Content = $playGlyph
    (& $dget "DLike").Content = $likeGlyph
    (& $dget "DLike").Foreground = $likeBrush
    (& $dget "DVol").Content = Vol-Glyph $script:volume
    if (-not $desk.IsVisible) { Place-Desk; $desk.Show(); Send-DeskBack }
    $desk.UpdateLayout()
    $pb = & $dget "DProgress"
    $pb.Width = [Math]::Max(0, $pb.Parent.ActualWidth * [double]$np.progress / 100)
  } elseif ($desk.IsVisible) { $desk.Hide() }

  if ($Snapshot) { Save-Snapshot }
}

function Save-Snapshot {
  # wait for the cover to download, then render the pill to a PNG
  $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(2)
  $t.Add_Tick({
    $t.Stop()
    $w = [int]$pill.ActualWidth; $h = [int]$pill.ActualHeight
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap(($w * 2), ($h * 2), 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($pill)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close()
    if ($env:FUMEFY_SNAP_VOL) {
      # also render the volume popup (for screenshots)
      $popup.IsOpen = $true; $popup.Child.UpdateLayout()
      $c = $popup.Child; $rtb2 = New-Object Windows.Media.Imaging.RenderTargetBitmap(([int]$c.ActualWidth * 2), ([int]$c.ActualHeight * 2), 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
      $rtb2.Render($c); $enc2 = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc2.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb2))
      $fs2 = [IO.File]::Create($env:FUMEFY_SNAP_VOL); $enc2.Save($fs2); $fs2.Close()
    }
    if ($env:FUMEFY_SNAP_DESK -and $desk.IsVisible) {
      # also render the desktop widget (for screenshots)
      $c = & $dget "DCard"; $rtb3 = New-Object Windows.Media.Imaging.RenderTargetBitmap(([int]$c.ActualWidth * 2), ([int]$c.ActualHeight * 2), 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
      $rtb3.Render($c); $enc3 = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc3.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb3))
      $fs3 = [IO.File]::Create($env:FUMEFY_SNAP_DESK); $enc3.Save($fs3); $fs3.Close()
    }
    $app.Shutdown()
  }.GetNewClosure())
  $t.Start()
}

# "Show desktop" (Win+D, the taskbar corner) and Alt+Tab to the desktop hide or minimize ordinary windows.
# Bring the widgets back right away, and while the desktop itself is in front, lift the desktop widget
# above it (topmost); as soon as another window is active it goes back down to the desktop layer.
$script:deskLifted = $false
function Guard-Widgets {
  $has = $script:lastNp -and $script:lastNp.title
  $fgClass = [TB]::ClassOf([TB]::GetForegroundWindow())
  $desktopInFront = $fgClass -eq "WorkerW" -or $fgClass -eq "Progman"
  if ($has -and $script:cfg.taskbar -and $script:hwnd -ne [IntPtr]::Zero) {
    if (-not [TB]::IsWindowVisible($script:hwnd) -or [TB]::IsIconic($script:hwnd)) { [TB]::ShowWindow($script:hwnd, 4) | Out-Null }   # SW_SHOWNOACTIVATE
    if ($desktopInFront) { Keep-OnTop }
  }
  if ($has -and $script:cfg.desktop -and $script:dhwnd -ne [IntPtr]::Zero) {
    if (-not [TB]::IsWindowVisible($script:dhwnd) -or [TB]::IsIconic($script:dhwnd)) { [TB]::ShowWindow($script:dhwnd, 4) | Out-Null }
    if ($desktopInFront -and -not $script:deskLifted) {
      [TB]::SetWindowPos($script:dhwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0013) | Out-Null; $script:deskLifted = $true      # HWND_TOPMOST
    } elseif (-not $desktopInFront -and $script:deskLifted) {
      [TB]::SetWindowPos($script:dhwnd, [IntPtr](-2), 0, 0, 0, 0, 0x0013) | Out-Null; $script:deskLifted = $false     # HWND_NOTOPMOST
      Send-DeskBack
    }
  }
}

$parentPid = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId } catch { 0 }
if ($Snapshot) { $parentPid = 0 }

# Read stdin without blocking the UI: poll an async ReadLine from a timer
$reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
$script:pending = $reader.ReadLineAsync()
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$script:ticks = 0
$timer.Add_Tick({
  while ($script:pending.IsCompleted) {
    $line = $script:pending.Result
    if ($null -eq $line -or $line -eq "quit") { $timer.Stop(); $app.Shutdown(); return }
    if ($line.StartsWith("np ")) {
      try { Apply-NowPlaying ($line.Substring(3) | ConvertFrom-Json) } catch {}
    } elseif ($line.StartsWith("cfg ")) {
      try {
        $c = $line.Substring(4) | ConvertFrom-Json
        $script:cfg = @{ taskbar = [bool]$c.taskbar; desktop = [bool]$c.desktop }
        Apply-NowPlaying $script:lastNp
      } catch {}
    }
    $script:pending = $reader.ReadLineAsync()
  }
  if ($script:volSend -ge 0) { Send-Cmd ("vol " + $script:volSend); $script:volSend = -1 }
  $script:ticks++
  # exit with the injector, even if stdin is never closed (so restarts never leave old players behind)
  if ($script:ticks % 16 -eq 0 -and $parentPid -and -not (Get-Process -Id $parentPid -ErrorAction SilentlyContinue)) { $timer.Stop(); $app.Shutdown(); return }
  if ($script:ticks % 10 -eq 0 -and $win.IsVisible) { Place; Keep-OnTop }   # every ~1.2 s
  Guard-Widgets
})
$timer.Start()

[void]$app.Run()
