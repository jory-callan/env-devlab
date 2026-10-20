# Install Rust via Scoop and configure the rsproxy.cn mirrors.
# Usage: powershell -ExecutionPolicy Bypass -File .\scoop-install-rust.ps1 [-Yes]
#        Menu: 1 = install Rust and configure mirrors, 2 = configure mirrors only, 0 = exit
#
# Two separate mirrors are configured:
#   RUSTUP_DIST_SERVER / RUSTUP_UPDATE_ROOT  -> toolchain downloads
#   [source.crates-io] in ~/.cargo/config.toml -> crate dependencies

param(
    [string]$DistServer = "https://rsproxy.cn",
    [string]$UpdateRoot = "https://rsproxy.cn/rustup",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$ScoopShims = "D:\env\scoop\shims"
$CargoBin = "D:\env\scoop\apps\rustup\current\.cargo\bin"
$PersistRoot = "D:\env\scoop\persist\rustup"
$CargoHome = Join-Path $PersistRoot ".cargo"
$ConfigFile = Join-Path $CargoHome "config.toml"

# ---- Pick an action ----
if ($Yes) {
    $step = "both"
} else {
    Write-Host @"

========================================
 Rust Setup
========================================
  rustup      : $ScoopShims\rustup.exe
  rustc/cargo : $CargoBin
  Toolchain   : $DistServer
  Crates      : sparse+$DistServer/index/
  Config file : $ConfigFile
========================================

"@ -ForegroundColor Cyan
    Write-Host "  [1] Install Rust and configure mirrors" -ForegroundColor Cyan
    Write-Host "  [2] Configure mirrors only" -ForegroundColor Cyan
    Write-Host "  [0] Exit" -ForegroundColor Cyan
    Write-Host ""
    $step = switch (Read-Host "Please select") {
        "1" { "both" }
        "2" { "mirror" }
        default { Write-Host "Exited."; exit 0 }
    }
}

# ---- Step 1: install rustup ----
if ($step -eq "both") {
    if (Test-Path (Join-Path $CargoBin "rustup.exe")) {
        Write-Host "`n  Rust is already installed. Skipped." -ForegroundColor Yellow
    } else {
        if (-not (Get-Command scoop.cmd -ErrorAction SilentlyContinue)) {
            Write-Host "`n  Scoop is not on PATH. Install it first: .\install-scoop.ps1" -ForegroundColor Red
            exit 1
        }
        Write-Host "`n  Installing rustup with Scoop..."
        & scoop.cmd install rustup
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $CargoBin "rustup.exe"))) {
            Write-Host "  Failed. Expected $CargoBin\rustup.exe" -ForegroundColor Red
            exit 1
        }
        Write-Host "  Installed: $CargoBin\rustup.exe" -ForegroundColor Green
    }

    # Make the toolchain visible to this process
    $env:CARGO_HOME = $CargoHome
    $env:RUSTUP_HOME = Join-Path $PersistRoot ".rustup"
    $env:Path = "$CargoBin;" + [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
               [Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path

    # The mirror variables must exist before installing a toolchain, otherwise
    # rustup fetches from the official server.
    [Environment]::SetEnvironmentVariable("RUSTUP_DIST_SERVER", $DistServer, "User")
    [Environment]::SetEnvironmentVariable("RUSTUP_UPDATE_ROOT", $UpdateRoot, "User")
    $env:RUSTUP_DIST_SERVER = $DistServer
    $env:RUSTUP_UPDATE_ROOT = $UpdateRoot

    # Without a default toolchain rustc and cargo exist but refuse to run.
    Write-Host "`n  Setting the default toolchain (stable)..."
    & rustup default stable
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to set the default toolchain." -ForegroundColor Red
        Write-Host "  Try manually: rustup default stable" -ForegroundColor Yellow
        exit 1
    }
}

# ---- Step 2: mirrors ----
if ($step -eq "mirror" -or $step -eq "both") {
    # rustup downloads the toolchain from these.
    [Environment]::SetEnvironmentVariable("RUSTUP_DIST_SERVER", $DistServer, "User")
    [Environment]::SetEnvironmentVariable("RUSTUP_UPDATE_ROOT", $UpdateRoot, "User")

    # cargo downloads crates from here. The sparse protocol needs Rust 1.68+.
    New-Item -ItemType Directory -Path $CargoHome -Force | Out-Null
    Set-Content -Path $ConfigFile -Encoding UTF8 -Value @(
        "# Managed by scoop-install-rust.ps1",
        "[source.crates-io]",
        "replace-with = 'rsproxy-sparse'",
        "",
        "[source.rsproxy-sparse]",
        "registry = `"sparse+$DistServer/index/`"",
        "",
        "[net]",
        "git-fetch-with-cli = true"
    )

    Write-Host "`n  Configured:" -ForegroundColor Green
    Write-Host "    RUSTUP_DIST_SERVER = $DistServer   (User env)" -ForegroundColor Green
    Write-Host "    RUSTUP_UPDATE_ROOT = $UpdateRoot   (User env)" -ForegroundColor Green
    Write-Host "    crates.io mirror   = sparse+$DistServer/index/   ($ConfigFile)" -ForegroundColor Green
}

# ---- Check the MSVC build tools, which rustc links against ----
$linkerFound = $false
$vsCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
)
foreach ($vswhere in $vsCandidates) {
    if (Test-Path $vswhere) {
        $args = @(
            '-latest', '-products', '*',
            '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
            '-property', 'installationPath'
        )
        $result = & $vswhere @args 2>$null
        if ($result) { $linkerFound = $true; break }
    }
}
if (-not $linkerFound) {
    Write-Host @"

  Warning: the MSVC build tools were not found.

  rustup installs the MSVC toolchain, which needs the Visual C++ Build
  Tools to link binaries. cargo build will fail with "linker link.exe not
  found" until they are present.

  Install them from:
    https://visualstudio.microsoft.com/visual-cpp-build-tools/

  Select these two components:
    - MSVC - VS C++ x64/x86 build tools
    - Windows SDK

"@ -ForegroundColor Yellow
}

Write-Host @"

  Open a NEW terminal, then:

    rustc --version
    cargo --version
    rustup show                List installed toolchains
    rustup update              Update to the newest stable

    cargo new hello
    cd hello
    cargo add serde_json
    cargo run

"@ -ForegroundColor Cyan