# Install Chocolatey (requires Administrator)
# Usage: powershell -ExecutionPolicy Bypass -File .\install-choco.ps1 [-Root D:\env] [-Yes]

param(
    [string]$Root = "D:\env",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$ChocoDir = Join-Path $Root "chocolatey"

# ---- Idempotency: skip if the install directory already exists ----
if (Test-Path $ChocoDir) {
    Write-Host @"

  Chocolatey is already installed. Skipped.

    Directory : $ChocoDir
    Executable: $(Join-Path $ChocoDir 'bin\choco.exe')

  If this installation is broken, remove the directory first:
    Remove-Item -Recurse -Force `"$ChocoDir`"

"@ -ForegroundColor Yellow
    exit 0
}

# ---- Administrator check ----
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host @"

  Administrator privileges are required.

  Or just run install-choco.bat, which auto-elevates.

"@ -ForegroundColor Red
    exit 1
}

# ---- Print the install plan up front ----
$overridden = if ($Root -ne "D:\env") { "`n  [!] Root directory overridden from the default D:\env" } else { "" }
Write-Host @"

========================================
 Chocolatey Install Plan
========================================
  Install root  : $Root
  Install dir   : $ChocoDir
  Executable    : $(Join-Path $ChocoDir 'bin\choco.exe')
  Package cache : $(Join-Path $ChocoDir 'lib')
  Scope         : Machine-wide (all users)
  Requires      : Administrator
  Installer     : https://community.chocolatey.org/install.ps1$overridden
========================================

"@ -ForegroundColor Cyan

# ---- Menu: 0 exit, 1 install ----
if (-not $Yes) {
    Write-Host "  [1] Install to the location above" -ForegroundColor Cyan
    Write-Host "  [0] Exit" -ForegroundColor Cyan
    Write-Host ""
    if ((Read-Host "Please select") -ne "1") {
        Write-Host "Exited."
        exit 0
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# The official installer has no -InstallDir parameter; it reads the install
# location from $env:ChocolateyInstall. Set it before launching the child process.
$env:ChocolateyInstall = $ChocoDir

Write-Host "Downloading the installer from https://community.chocolatey.org/install.ps1 ..."
try {
    Invoke-WebRequest "https://community.chocolatey.org/install.ps1" -OutFile "$env:TEMP\choco-install.ps1" -UseBasicParsing -TimeoutSec 60
} catch {
    Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Installing to $ChocoDir (this may take a few minutes)..."
& powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\choco-install.ps1"
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "  Installer exited with code $exitCode" -ForegroundColor Red
    exit $exitCode
}

# ---- Verify ----
if (Test-Path (Join-Path $ChocoDir 'bin\choco.exe')) {
    Write-Host @"

  Chocolatey installed: $ChocoDir

  Restart your terminal so PATH takes effect, then verify:
    choco -v

"@ -ForegroundColor Green
} else {
    Write-Host @"

  The installer ran but choco.exe was not found.

    Expected at : $(Join-Path $ChocoDir 'bin\choco.exe')
    Check logs  : $env:TEMP\chocolatey\*.log

  The directory now exists, so rerunning will skip. To retry, remove it first:
    Remove-Item -Recurse -Force `"$ChocoDir`"

"@ -ForegroundColor Yellow
    exit 1
}