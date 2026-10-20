# Install Go and configure the Qiniu Cloud module proxy.
# Usage: powershell -ExecutionPolicy Bypass -File .\scoop-install-go.ps1 [-Yes]
#        Menu: 1 = install Go and configure the proxy, 2 = configure the proxy only, 0 = exit
#
# Go needs no shell hook. Multi-version selection is handled by the toolchain
# directive in each project's go.mod, for example:  toolchain go1.22.0

param(
    [string]$Proxy = "https://goproxy.cn,direct",
    [string]$SumDb = "sum.golang.org",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$GoExe = "D:\env\scoop\apps\go\current\bin\go.exe"

function Get-Go {
    # Prefer the go on PATH; fall back to the Scoop shim.
    $g = Get-Command go.exe -ErrorAction SilentlyContinue
    if (-not $g -and (Test-Path $GoExe)) { return $GoExe }
    if ($g) { return $g.Source }
    return $null
}

# ---- Pick an action ----
if ($Yes) {
    $step = "both"
} else {
    Write-Host @"

========================================
 Go Setup
========================================
  go        : $GoExe
  GOPROXY   : $Proxy
  GOSUMDB   : $SumDb
  Toolchain : per-project, via the go.mod directive
========================================

"@ -ForegroundColor Cyan
    Write-Host "  [1] Install Go and configure the proxy" -ForegroundColor Cyan
    Write-Host "  [2] Configure the proxy only" -ForegroundColor Cyan
    Write-Host "  [0] Exit" -ForegroundColor Cyan
    Write-Host ""
    $step = switch (Read-Host "Please select") {
        "1" { "both" }
        "2" { "mirror" }
        default { Write-Host "Exited."; exit 0 }
    }
}

# ---- Step 1: install Go ----
if ($step -eq "both") {
    if (Get-Go) {
        Write-Host "`n  Go is already installed. Skipped." -ForegroundColor Yellow
    } else {
        if (-not (Get-Command scoop.cmd -ErrorAction SilentlyContinue)) {
            Write-Host "`n  Scoop is not on PATH. Install it first: .\install-scoop.ps1" -ForegroundColor Red
            exit 1
        }
        Write-Host "`n  Installing Go with Scoop..."
        & scoop.cmd install go
        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path
        if (-not (Get-Go)) {
            Write-Host "  Failed. Check: scoop.cmd list" -ForegroundColor Red
            exit 1
        }
        Write-Host "  Installed: $(Get-Go)" -ForegroundColor Green
    }
}

# ---- Step 2: module proxy ----
if ($step -eq "mirror" -or $step -eq "both") {
    $go = Get-Go
    if (-not $go) {
        Write-Host "`n  Go is not installed. Run option 1 first." -ForegroundColor Red
        exit 1
    }

    # go env -w writes to the GOENV file, which every Go tool reads. This
    # overrides the default proxy.golang.org without touching $env:GOPROXY.
    & $go env -w "GOPROXY=$Proxy"
    & $go env -w "GOSUMDB=$SumDb"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  go env -w failed." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n  Configured:" -ForegroundColor Green
    Write-Host "    GOPROXY = $Proxy" -ForegroundColor Green
    Write-Host "    GOSUMDB = $SumDb" -ForegroundColor Green
    Write-Host "    GOENV   = $(& $go env GOENV)" -ForegroundColor Green
    Write-Host "    Version = $(& $go version)" -ForegroundColor Green
}

Write-Host @"

  Open a NEW terminal, then:

    go version
    go env GOPROXY

    go mod init myproject
    go get github.com/gin-gonic/gin@latest
    go run .

  Pin a specific Go version per project by adding to go.mod:
    toolchain go1.22.0

"@ -ForegroundColor Cyan