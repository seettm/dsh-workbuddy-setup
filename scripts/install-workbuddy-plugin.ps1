# install-workbuddy-plugin.ps1
# Install (or swap) a WorkBuddy-connecting plugin inside a DeepSeek Harness profile.
# ASCII-only by design: safe on any console codepage.
#
# Examples:
#   pwsh -File .\install-workbuddy-plugin.ps1                 # default swap -> dsh-connect-workbuddy@3.6.0
#   pwsh -File .\install-workbuddy-plugin.ps1 -DryRun         # show the diff, change nothing
#   pwsh -File .\install-workbuddy-plugin.ps1 -Plugin dsh-workbuddy-connect -Version 0.7.1 -Remove @()

[CmdletBinding()]
param(
  [string]   $InstallDir,
  [string]   $Profile = 'desktop',
  [string]   $Plugin  = 'dsh-connect-workbuddy',
  [string]   $Version = '3.6.0',
  [string[]] $Remove  = @('dsh-workbuddy-connect'),
  [switch]   $DryRun
)

$ErrorActionPreference = 'Stop'

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
  # last resort: read it off the running host process
  $proc = Get-CimInstance Win32_Process -Filter "Name like '%DeepSeek%'" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($proc -and $proc.CommandLine -match '"([A-Za-z]:\\[^"]+DeepSeek[^"]*\.exe)"') {
    $dir = Split-Path $Matches[1] -Parent
    if (Test-Path (Join-Path $dir 'resources\runtime\primary-runtime\runtime.json')) { return $dir }
  }
  throw 'DSH install directory not found. Pass -InstallDir <path>.'
}

$install    = Resolve-DshInstallDir -Explicit $InstallDir
$runtimeDir = Join-Path $install 'resources\runtime\primary-runtime'
$runtime    = Get-Content (Join-Path $runtimeDir 'runtime.json') -Raw | ConvertFrom-Json
$node       = Join-Path $runtimeDir 'dependencies\node\bin\node.exe'
$pnpm       = Join-Path $install 'resources\runtime\pnpm\bin\pnpm.mjs'

$dshHome    = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$profileDir = Join-Path $dshHome "profiles\$Profile"
$pkgPath    = Join-Path $profileDir 'package.json'

if (-not (Test-Path $pkgPath)) { throw "Profile package.json not found: $pkgPath" }
if (-not (Test-Path $node))    { throw "Bundled node not found: $node" }
if (-not (Test-Path $pnpm))    { throw "Bundled pnpm not found: $pnpm" }

Write-Host "DSH install     : $install"
Write-Host "DSH core version: $($runtime.desktopVersion)"
Write-Host "Profile         : $profileDir"
Write-Host "Action          : install $Plugin@$Version ; remove [$($Remove -join ', ')]"
Write-Host ''

$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -AsHashtable
if (-not $pkg.ContainsKey('dependencies')) { $pkg['dependencies'] = [ordered]@{} }
if (-not $pkg.ContainsKey('dsh'))          { $pkg['dsh'] = [ordered]@{} }
if (-not $pkg.dsh.ContainsKey('profile'))  { $pkg.dsh['profile'] = [ordered]@{} }
if (-not $pkg.dsh.profile.ContainsKey('bundles')) { $pkg.dsh.profile['bundles'] = @() }

$pkg.dependencies[$Plugin] = $Version
foreach ($r in $Remove) {
  if ($pkg.dependencies.ContainsKey($r)) { $pkg.dependencies.Remove($r) }
}

$bundles = [System.Collections.Generic.List[string]]::new()
foreach ($b in $pkg.dsh.profile.bundles) { $bundles.Add([string]$b) }
foreach ($r in $Remove)   { $bundles.Remove($r) | Out-Null }
if (-not $bundles.Contains($Plugin)) { $bundles.Add($Plugin) }
$pkg.dsh.profile['bundles'] = $bundles.ToArray()

$json = $pkg | ConvertTo-Json -Depth 12

if ($DryRun) {
  Write-Host '--- resulting package.json (dry run, nothing written) ---'
  Write-Host $json
  exit 0
}

$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$pkgPath.bak-$stamp"
Copy-Item $pkgPath $backup -Force
Write-Host "Backup written  : $backup"
Set-Content -Path $pkgPath -Value $json -Encoding UTF8

Write-Host 'Running pnpm install (bundled node/pnpm)...'
& $node $pnpm install --reporter=append-only
if ($LASTEXITCODE -ne 0) {
  Write-Warning "pnpm install exited with $LASTEXITCODE. Restore from $backup if the profile is broken."
  exit $LASTEXITCODE
}

Write-Host ''
Write-Host 'Done. Verify:'
Write-Host "  pwsh -File .\verify-workbuddy-plugin.ps1"
Write-Host "  heartbeat: $(Join-Path $dshHome '.workbuddy-host-heartbeat.json')"
Write-Host 'Restart DeepSeek Harness so the new bundle list is mounted.'
