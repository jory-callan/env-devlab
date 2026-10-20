# Install uv (Python package and version manager) and configure mirrors.
# Usage: powershell -ExecutionPolicy Bypass -File .\scoop-install-uv.ps1 [-Yes]
#        Menu: 1 = install uv + configure mirrors, 2 = configure mirrors only, 0 = exit
#        -Yes runs both steps without asking.
#
# Unlike fnm, uv needs no shell hook: it resolves Python versions itself and
# you invoke it with `uv run`, `uv venv` or `uv pip`. So nothing has to be
# added to $PROFILE here.

param(
    [string]$PythonMirror = "https://registry.npmmirror.com/-/binary/python-build-standalone",
    [string]$PypiMirror = "https://mirrors.aliyun.com/pypi/simple/",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$ScoopDir = "D:\env\scoop"
$UvExe = Join-Path $ScoopDir "shims\uv.exe"
$UvRoot = Join-Path $ScoopDir "persist\uv"
$ConfigDir = Join-Path $env:APPDATA "uv"
$ConfigFile = Join-Path $ConfigDir "uv.toml"

# ---- Pick an action ----
if ($Yes) {
    $step = "both"
} else {
    Write-Host @"

========================================
 uv Setup
========================================
  uv           : $UvExe
  uv data      : $UvRoot
  Python mirror: $PythonMirror
  PyPI mirror  : $PypiMirror
  Config file  : $ConfigFile
========================================

"@ -ForegroundColor Cyan
    Write-Host "  [1] Install uv and configure mirrors" -ForegroundColor Cyan
    Write-Host "  [2] Configure mirrors only" -ForegroundColor Cyan
    Write-Host "  [0] Exit" -ForegroundColor Cyan
    Write-Host ""
    $step = switch (Read-Host "Please select") {
        "1" { "both" }
        "2" { "mirror" }
        default { Write-Host "Exited."; exit 0 }
    }
}

# ---- Step 1: install uv ----
if ($step -eq "both") {
    if (Test-Path $UvExe) {
        Write-Host "`n  uv is already installed. Skipped." -ForegroundColor Yellow
    } else {
        if (-not (Test-Path (Join-Path $ScoopDir "shims\scoop.cmd")) -and
            -not (Get-Command scoop.cmd -ErrorAction SilentlyContinue)) {
            Write-Host "`n  Scoop is not on PATH. Install it first: .\install-scoop.ps1" -ForegroundColor Red
            exit 1
        }
        Write-Host "`n  Installing uv with Scoop..."
        & scoop.cmd install uv
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $UvExe)) {
            Write-Host "  Failed. Expected $UvExe" -ForegroundColor Red
            Write-Host "  Check: scoop.cmd list" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  Installed: $UvExe" -ForegroundColor Green
    }
}

# ---- Step 2: mirrors ----
if ($step -eq "mirror" -or $step -eq "both") {
    # uv reads these from its own config file. The defaults point at GitHub
    # releases and pypi.org, which are slow from mainland China.
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    Set-Content -Path $ConfigFile -Encoding UTF8 -Value @(
        "# Managed by scoop-install-uv.ps1. Mirrors for mainland China.",
        "python-install-mirror = `"$PythonMirror`"",
        "",
        "[[index]]",
        "url = `"$PypiMirror`"",
        "default = true",
        "",
        "[pip]",
        "index-url = `"$PypiMirror`""
    )

    # Keep uv's own data under the Scoop root instead of %APPDATA%, so it
    # travels with the install. Scoop also sets these on install, but they are
    # written here so option 2 works on its own.
    foreach ($pair in @(
        @("UV_CACHE_DIR",(Join-Path $UvRoot "cache")),
        @("UV_PYTHON_INSTALL_DIR",(Join-Path $UvRoot "python\versions")),
        @("UV_PYTHON_BIN_DIR",(Join-Path $UvRoot "python\shims")),
        @("UV_TOOL_DIR",(Join-Path $UvRoot "tools\versions")),
        @("UV_TOOL_BIN_DIR",(Join-Path $UvRoot "tools\shims"))
    )) {
        [Environment]::SetEnvironmentVariable($pair[0], $pair[1], "User")
        New-Item -ItemType Directory -Path $pair[1] -Force | Out-Null
    }

    Write-Host "`n  Configured:" -ForegroundColor Green
    Write-Host "    Python mirror  = $PythonMirror" -ForegroundColor Green
    Write-Host "    PyPI mirror    = $PypiMirror" -ForegroundColor Green
    Write-Host "    Config file    = $ConfigFile" -ForegroundColor Green
    Write-Host "    uv data root   = $UvRoot   (User env)" -ForegroundColor Green
}

Write-Host @"

  Open a NEW terminal, then:

    uv --version           Check uv is on PATH
    uv python list         List available Python versions
    uv python install 3.12 Install a Python version (uses the mirror)
    uv python list --only-installed

    uv init                Create a project
    uv venv                Create a virtual environment
    uv add requests        Add a dependency (uses the PyPI mirror)
    uv run python          Run Python inside the project environment

"@ -ForegroundColor Cyan