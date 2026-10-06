# verify-workbuddy-plugin.ps1
# Report whether a WorkBuddy-connecting plugin is actually mounted in DSH.
# ASCII-only by design.

[CmdletBinding()]
param(
  [string] $InstallDir,
  [string] $Profile = 'desktop',
  [int]    $Port = 19387,
  [string[]] $Candidates = @('dsh-connect-workbuddy', 'dsh-workbuddy-connect', 'dsh-workbuddy-bridge', 'dsh-workbuddy-console', 'dsh-workbuddy-xdpool')
)

$ErrorActionPreference = 'Continue'

function Resolve-DshInstallDir {
  param([string] $Explicit)
  $candidates = @()
  if ($Explicit) { $candidates += $Explicit }
  if ($env:DSH_INSTALL_DIR) { $candidates += $env:DSH_INSTALL_DIR }
  $candidates += 'D:\DeepSeekHarness'
  $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness')
  foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c 'resources\runtime\primary-runtime\runtime.json'))) { return (Resolve-Path $c).Path }
  }
  $proc = Get-CimInstance Win32_Process -Filter "Name like '%DeepSeek%'" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($proc -and $proc.CommandLine -match '"([A-Za-z]:\\[^"]+DeepSeek[^"]*\.exe)"') {
    $dir = Split-Path $Matches[1] -Parent
    if (Test-Path (Join-Path $dir 'resources\runtime\primary-runtime\runtime.json')) { return $dir }
  }
  return $null
}

$dshHome    = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$profileDir = Join-Path $dshHome "profiles\$Profile"
$pkgPath    = Join-Path $profileDir 'package.json'
$lockPath   = Join-Path $profileDir 'pnpm-lock.yaml'

Write-Host '== DSH host =='
$install = Resolve-DshInstallDir -Explicit $InstallDir
if ($install) {
  $runtime = Get-Content (Join-Path $install 'resources\runtime\primary-runtime\runtime.json') -Raw | ConvertFrom-Json
  Write-Host "install dir  : $install"
  Write-Host "core version : $($runtime.desktopVersion)"
} else {
  Write-Host 'install dir  : NOT FOUND (pass -InstallDir)'
}
Write-Host "profile dir  : $profileDir"

Write-Host ''
Write-Host '== profile package.json =='
if (Test-Path $pkgPath) {
  $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -AsHashtable
  $bundles = @($pkg.dsh.profile.bundles)
  foreach ($c in $Candidates) {
    $dep = if ($pkg.dependencies.ContainsKey($c)) { $pkg.dependencies[$c] } else { '-' }
    $inBundle = if ($bundles -contains $c) { 'bundle=yes' } else { 'bundle=NO' }
    if ($dep -ne '-' -or $inBundle -eq 'bundle=yes') { Write-Host ("  {0,-32} dep={1,-10} {2}" -f $c, $dep, $inBundle) }
  }
} else {
  Write-Host "  missing: $pkgPath"
}

Write-Host ''
Write-Host '== resolved in node_modules =='
foreach ($c in $Candidates) {
  $p = Join-Path $profileDir "node_modules\$c\package.json"
  if (Test-Path $p) {
    $j = Get-Content $p -Raw | ConvertFrom-Json
    Write-Host ("  {0} = {1}" -f $c, $j.version)
  }
}
$leftover = @()
foreach ($c in $Candidates) {
  if (Test-Path (Join-Path $profileDir "node_modules\$c")) { $leftover += $c }
}
if ($leftover.Count -gt 1) { Write-Warning "More than one WorkBuddy plugin is present ($($leftover -join ', ')) - they collide on provider id 'workbuddy'. Keep exactly one." }

Write-Host ''
Write-Host '== heartbeat (proves the host-side bundle was mounted) =='
$hb = Join-Path $dshHome '.workbuddy-host-heartbeat.json'
if (Test-Path $hb) {
  Get-Content $hb -Raw
  Write-Host ("  written: {0}" -f (Get-Item $hb).LastWriteTime)
} else {
  Write-Host "  missing: $hb  (plugin did not register - check for skippedBundles)"
}

Write-Host ''
Write-Host '== HTTP routes =='
foreach ($c in $Candidates) {
  foreach ($sub in @('status')) {
    $u = "http://127.0.0.1:$Port/plugins/$c/$sub"
    try {
      $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 5
      Write-Host "  [OK  $($r.StatusCode)] $u"
      $body = $r.Content
      if ($body.Length -gt 400) { $body = $body.Substring(0, 400) + '...' }
      Write-Host "        $body"
    } catch {
      $code = $_.Exception.Response.StatusCode.value__
      Write-Host "  [--  $code] $u"
    }
  }
}
Write-Host ''
Write-Host 'Note: DSH /api/* requires GUI authentication (401 without it); plugin routes do not.'
