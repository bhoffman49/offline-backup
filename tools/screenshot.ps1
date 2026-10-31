# Saves a PNG of a visible top-level window, found by its exact title. For checking the UI from scripts.
# Usage: powershell -File tools\screenshot.ps1 -Title "Offline Backup" -Out shot.png
param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public struct RECT { public int L, T, R, B; }
  // the app's hidden windows can share the title, so only visible ones count
  public static IntPtr FindVisible(string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var t = new StringBuilder(512); GetWindowText(h, t, 512);
      if (IsWindowVisible(h) && t.ToString() == title) { found = h; return false; } return true; }, IntPtr.Zero);
    return found; }
}
'@
[W]::SetProcessDPIAware() | Out-Null
$h = [W]::FindVisible($Title)
if ($h -eq [IntPtr]::Zero) { Write-Error "no visible window titled '$Title'"; exit 1 }
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"saved $Out ($($bmp.Width)x$($bmp.Height))"
