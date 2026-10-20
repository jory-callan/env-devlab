# Install Scoop (no Administrator required)
# Usage: powershell -ExecutionPolicy Bypass -File .\install-scoop.ps1 [-Root D:\env] [-Yes]

param(
    [string]$Root = "D:\env",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$ScoopDir = Join-Path $Root "scoop"

# ---- Idempotency: skip if the install directory already exists ----
if (Test-Path $ScoopDir) {
    Write-Host @"

  Scoop is already installed. Skipped.

    Directory : $ScoopDir
    Command   : $(Join-Path $ScoopDir 'shims\scoop.cmd')

  If this installation is broken, remove the directory first:
    Remove-Item -Recurse -Force `"$ScoopDir`"

"@ -ForegroundColor Yellow
    exit 0
}

# ---- Print the install plan up front ----
$overridden = if ($Root -ne "D:\env") { "`n  [!] Root directory overridden from the default D:\env" } else { "" }
Write-Host @"

========================================
 Scoop Install Plan
========================================
  Install root : $Root
  Install dir  : $ScoopDir
  Global apps  : $(Join-Path $ScoopDir 'global')
  Command shim : $(Join-Path $ScoopDir 'shims')
  Scope        : Current user (no Administrator needed)
  Installer    : https://get.scoop.sh$overridden
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

# The installer needs the target directory to be missing or empty,
# so only the parent directory is created here.
New-Item -ItemType Directory -Path $Root -Force | Out-Null

Write-Host "Downloading the installer from https://get.scoop.sh ..."
try {
    Invoke-WebRequest "https://get.scoop.sh" -OutFile "$env:TEMP\scoop-install.ps1" -UseBasicParsing -TimeoutSec 60
} catch {
    Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Installing to $ScoopDir (this may take a few minutes)..."

# The Scoop installer refuses to run as Administrator unless -RunAsAdmin is passed.
$runAsAdmin = if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { "-RunAsAdmin" } else { "" }
& powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\scoop-install.ps1" `
    -ScoopDir $ScoopDir -ScoopGlobalDir (Join-Path $ScoopDir 'global') $runAsAdmin
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "  Installer exited with code $exitCode" -ForegroundColor Red
    exit $exitCode
}

# ---- Verify ----
if (Test-Path (Join-Path $ScoopDir 'shims\scoop.cmd')) {
    Write-Host @"

  Scoop installed: $ScoopDir

  Restart your terminal so PATH takes effect.

  In PowerShell use scoop.cmd, because scoop itself is a .ps1 shim
  blocked by the execution policy:
    scoop.cmd -v

  To use plain 'scoop' instead, relax the execution policy:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

"@ -ForegroundColor Green
} else {
    Write-Host @"

  The installer ran but scoop.cmd was not found.

    Expected at : $(Join-Path $ScoopDir 'shims\scoop.cmd')

  The directory now exists, so rerunning will skip. To retry, remove it first:
    Remove-Item -Recurse -Force `"$ScoopDir`"

"@ -ForegroundColor Yellow
    exit 1
}