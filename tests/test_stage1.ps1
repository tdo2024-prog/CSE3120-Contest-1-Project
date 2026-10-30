# test_stage1.ps1 - black-box test of stage1.exe. A test tool only; no part of
# the game uses it. It moves the real cursor for about 30 seconds, so don't touch
# the mouse while it runs. It reads results from screen pixels, with no hooks in
# the game. Run from the project folder:
#   powershell -ExecutionPolicy Bypass -File tests\test_stage1.ps1
param([string]$Exe = "$PSScriptRoot\..\stage1\stage1.exe",
      [string]$Shots = "$PSScriptRoot\..\docs\screenshots\stage1")

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public struct PT { public int X, Y; }
public struct RC { public int L, T, R, B; }
public static class W {
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out PT p);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, IntPtr e);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, IntPtr e);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RC r);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RC r);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(PT p);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr p, uint f);
}
'@
if (Get-Process stage1 -ErrorAction SilentlyContinue) { throw 'stage1.exe is already running; close it first' }
[W]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $Shots | Out-Null
$script:fails = 0; $script:passes = 0; $script:hwnd = [IntPtr]::Zero; $script:proc = $null
$saved = New-Object PT; [W]::GetCursorPos([ref]$saved) | Out-Null

function Check($name, $ok, $detail = '') {
  if ($ok) { $script:passes++; "PASS  $name $detail" } else { $script:fails++; "FAIL  $name $detail" }
}
function Launch {
  # Always bind to the window of the process started here, never a look-alike.
  if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill(); $script:proc.WaitForExit() }
  $script:proc = Start-Process $Exe -PassThru
  for ($i = 0; $i -lt 100; $i++) { Start-Sleep -Milliseconds 50
    $script:proc.Refresh(); $script:hwnd = $script:proc.MainWindowHandle
    if ($script:hwnd -ne [IntPtr]::Zero) { break } }
  if ($script:hwnd -eq [IntPtr]::Zero) { throw 'window did not appear' }
  [W]::SetWindowPos($script:hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x43) | Out-Null  # topmost, no move/size
  [W]::SetForegroundWindow($script:hwnd) | Out-Null
  Start-Sleep -Milliseconds 300
  $script:org = New-Object PT; [W]::ClientToScreen($script:hwnd, [ref]$script:org) | Out-Null
}
function MoveTo($x, $y) { [W]::SetCursorPos($script:org.X + $x, $script:org.Y + $y) | Out-Null; Start-Sleep -Milliseconds 40 }
function Walk($x0, $y0, $x1, $y1) {  # slow, small-step movement
  $n = [Math]::Max([Math]::Abs($x1 - $x0), [Math]::Abs($y1 - $y0)) / 8
  for ($i = 1; $i -le $n; $i++) { [W]::SetCursorPos($script:org.X + $x0 + ($x1 - $x0) * $i / $n, $script:org.Y + $y0 + ($y1 - $y0) * $i / $n) | Out-Null; Start-Sleep -Milliseconds 6 }
  MoveTo $x1 $y1
}
function Click($x, $y) {
  MoveTo $x $y
  $p = New-Object PT; $p.X = $script:org.X + $x; $p.Y = $script:org.Y + $y
  if ([W]::WindowFromPoint($p) -ne $script:hwnd) { throw "refusing to click: another window is at $x,$y" }
  [W]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 30
  [W]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 120
}
function Esc { [W]::keybd_event(0x1B, 0, 0, [IntPtr]::Zero); [W]::keybd_event(0x1B, 0, 2, [IntPtr]::Zero); Start-Sleep -Milliseconds 150 }
function Grab { # copy of the client area as the screen shows it
  Start-Sleep -Milliseconds 120
  $b = New-Object Drawing.Bitmap 800, 600
  $g = [Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen($script:org.X, $script:org.Y, 0, 0, (New-Object Drawing.Size 800, 600)); $g.Dispose(); $b
}
function Shot($name) { $b = Grab; $b.Save("$Shots\$name.png"); $b.Dispose() }
function Screen {   # READY/PLAY look alike here; panels are told apart by color
  $b = Grab; $c = $b.GetPixel(120, 200); $d = $b.GetPixel(120, 95); $b.Dispose()
  if ($d.R -eq 120 -and $d.G -eq 0 -and $d.B -eq 0) { return 'CRASH' }
  if ($c.R -eq 0 -and $c.G -eq 70 -and $c.B -eq 40) { return 'WON' }
  'MAZE'
}
function ExitedCleanly { if (-not $script:proc.WaitForExit(3000)) { return $false }
  $script:hwnd = [IntPtr]::Zero; $script:proc.ExitCode -eq 0 }

$RETRY = 280, 457; $EXITBTN = 520, 457; $START = 90, 110
try {
  # --- Window ---
  Launch
  $r = New-Object RC; [W]::GetClientRect($script:hwnd, [ref]$r) | Out-Null
  Check 'client area is 800x600' ($r.R -eq 800 -and $r.B -eq 600) "($($r.R)x$($r.B))"
  Shot '01_ready'

  # --- Rendering agrees with the collision map: compare every pixel to the map ---
  $rows = Select-String -Path "$PSScriptRoot\..\stage1\stage1.asm" -Pattern '^\s*BYTE "([#.SF]{40})"' | ForEach-Object { $_.Matches[0].Groups[1].Value }
  Check 'map has 28 rows of 40' ($rows.Count -eq 28)
  $b = Grab; $bad = 0
  for ($y = 40; $y -lt 600; $y++) { for ($x = 0; $x -lt 800; $x++) {
    $t = $rows[[int][Math]::Floor(($y - 40) / 20)][[int][Math]::Floor($x / 20)]
    $p = $b.GetPixel($x, $y); $isPath = ($p.R -eq 0 -and $p.G -eq 150 -and $p.B -eq 80)
    if ($t -eq '.' -and -not $isPath) { $bad++ }
    if ($t -eq '#' -and $isPath) { $bad++ } } }
  $b.Dispose()
  Check 'every drawn pixel matches the map' ($bad -eq 0) "($bad mismatches of 448000)"

  # --- READY: mouse is harmless and only START begins a run ---
  Walk 400 300 400 150; Walk 400 150 300 60
  Check 'READY: touching walls does nothing' ((Screen) -eq 'MAZE')
  Click 400 160; Walk 400 160 400 300
  Check 'READY: clicking a wall does not start' ((Screen) -eq 'MAZE')

  # --- Full valid path to FINISH ---
  Click @START
  Walk 90 110 690 110; Shot '02_playing'
  Walk 690 110 690 250; Walk 690 250 130 250; Walk 130 250 130 390; Walk 130 390 690 390
  Walk 690 390 690 530; Walk 690 530 130 530
  Check 'valid path stays alive' ((Screen) -eq 'MAZE')
  Walk 130 530 90 530
  Check 'reaching FINISH completes the level' ((Screen) -eq 'WON')
  Shot '03_level_complete'
  Click @RETRY
  Check 'PLAY AGAIN returns to the maze' ((Screen) -eq 'MAZE')

  # --- Exact wall boundary: row 5 starts at y = 40 + 5*20 = 140 ---
  Click @START; Walk 90 110 90 139
  Check 'y=139 (last floor pixel) is safe' ((Screen) -eq 'MAZE')
  MoveTo 90 140
  Check 'y=140 (first wall pixel) crashes' ((Screen) -eq 'CRASH')
  Shot '04_crash_wall'
  Click @RETRY
  Check 'RETRY returns to the maze' ((Screen) -eq 'MAZE')

  # --- Swept path: one big jump whose endpoint is safe floor ---
  Click @START; MoveTo 90 250      # (90,250) is corridor, walls lie between
  Check 'fast flick across a wall crashes' ((Screen) -eq 'CRASH')
  Shot '05_crash_flick_fault_at_y140'
  Click @RETRY

  Click @START; MoveTo 90 530      # flick straight onto FINISH
  Check 'flick onto FINISH is a crash, not a win' ((Screen) -eq 'CRASH')
  Click @RETRY

  Click @START; MoveTo 690 120     # long flick that stays inside the corridor
  Check 'fast flick inside a corridor is safe' ((Screen) -eq 'MAZE')
  Esc
  Check 'Esc mid-run cancels without a panel' ((Screen) -eq 'MAZE')

  # --- Leaving the window ---
  Click @START; MoveTo 90 -80; Start-Sleep -Milliseconds 200
  Check 'leaving the window crashes' ((Screen) -eq 'CRASH')
  Shot '06_crash_left_window'
  MoveTo 280 457; Click @RETRY

  # --- Losing focus cancels a run ---
  Click @START
  [W]::PostMessage($script:hwnd, 0x1C, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null  # WM_ACTIVATEAPP(FALSE)
  Start-Sleep -Milliseconds 100; MoveTo 90 200
  Check 'after focus loss, walls are harmless' ((Screen) -eq 'MAZE')

  # --- GDI leak check over many redraws ---
  $h = $script:proc.Handle; $before = [W]::GetGuiResources($h, 0)
  for ($i = 0; $i -lt 20; $i++) { Click @START; MoveTo 90 200; Click @RETRY }
  $after = [W]::GetGuiResources($h, 0)
  Check 'GDI objects stable over 20 crash cycles' ($after -le $before + 2) "($before -> $after)"

  # --- All the ways out ---
  Esc
  Check 'Esc on the maze exits with code 0' (ExitedCleanly)

  Launch; Click @START; MoveTo 90 200; Click @EXITBTN
  Check 'EXIT button exits with code 0' (ExitedCleanly)

  Launch; Click @START
  $wr = New-Object RC; [W]::GetWindowRect($script:hwnd, [ref]$wr) | Out-Null
  [W]::SetCursorPos($wr.R - 20, $wr.T + 12) | Out-Null; Start-Sleep -Milliseconds 300
  $cr = Screen
  [W]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 30; [W]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
  Check 'title-bar X closes the game during a run' (ExitedCleanly) "(screen when pressed: $cr)"
}
finally {
  if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() }
  [W]::SetCursorPos($saved.X, $saved.Y) | Out-Null
}
"`n$($script:passes) passed, $($script:fails) failed"
exit $script:fails
