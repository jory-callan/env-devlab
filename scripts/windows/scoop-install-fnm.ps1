# fnm setup and Node.js mirrors.
# Usage: powershell -ExecutionPolicy Bypass -File .\install-fnm.ps1 [-Yes]
#        Menu: 1 = install fnm + configure mirrors, 2 = configure mirrors only, 0 = exit
#        -Yes runs both steps without asking.
#
# Why the shell hook matters:
#   `fnm use` fails with "We can't find the necessary environment variables"
#   unless FNM_MULTISHELL_PATH is set, and only `fnm env` can create it.
#   So this script installs a hook for PowerShell ($PROFILE) and for cmd
#   (an AutoRun .cmd file), because cmd.exe never reads $PROFILE.

param(
    [string]$NodeMirror = "https://npmmirror.com/mirrors/node/",
    [string]$NpmMirror = "https://npmmirror.com/mirrors/npm/",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$FnmExe = "D:\env\scoop\apps\fnm\current\fnm.exe"
$FnmDir = "D:\env\fnm"
$Npmrc = Join-Path $env:USERPROFILE ".npmrc"
$CmdHook = Join-Path $env:USERPROFILE "fnm-env.cmd"
$PsProfile = $PROFILE.CurrentUserAllHosts

# Pass the paths explicitly so the hook never depends on inherited environment
# variables, which a shell started before the change may not have picked up.
$FnmArgs = "env --fnm-dir `"$FnmDir`" --node-dist-mirror `"$NodeMirror`""
$PsHook = "& `"$FnmExe`" $FnmArgs --use-on-cd | Out-String | Invoke-Expression"
$CmdHookBody = "`"$FnmExe`" $FnmArgs --shell cmd --use-on-cd"

# ---- Pick an action ----
if ($Yes) {
    $step = "both"
} else {
    Write-Host @"

========================================
 fnm Setup
========================================
  fnm           : $FnmExe
  fnm directory : $FnmDir
  Node mirror   : $NodeMirror
  npm mirror    : $NpmMirror   (~/.npmrc)
========================================

"@ -ForegroundColor Cyan
    Write-Host "  [1] Install fnm and configure mirrors" -ForegroundColor Cyan
    Write-Host "  [2] Configure mirrors and shell hooks only" -ForegroundColor Cyan
    Write-Host "  [0] Exit" -ForegroundColor Cyan
    Write-Host ""
    # Both choices end up applying the mirrors, since fnm use only works once
    # the shell hooks are in place.
    $step = switch (Read-Host "Please select") {
        "1" { "both" }
        "2" { "mirror" }
        default { Write-Host "Exited."; exit 0 }
    }
}

# ---- Step 1: install fnm ----
if ($step -eq "install" -or $step -eq "both") {
    if (Test-Path $FnmExe) {
        Write-Host "`n  fnm is already installed. Skipped." -ForegroundColor Yellow
    } else {
        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path
        if (-not (Get-Command scoop.cmd -ErrorAction SilentlyContinue)) {
            Write-Host "`n  Scoop is not on PATH. Install it first: .\install-scoop.ps1" -ForegroundColor Red
            exit 1
        }
        Write-Host "`n  Installing fnm with Scoop..."
        & scoop.cmd install fnm
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $FnmExe)) {
            Write-Host "  Failed. Expected $FnmExe" -ForegroundColor Red
            Write-Host "  Check: scoop.cmd list" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  Installed: $FnmExe" -ForegroundColor Green
    }
    New-Item -ItemType Directory -Path $FnmDir -Force | Out-Null
}

# ---- Step 2: mirrors and shell hooks ----
if ($step -eq "mirror" -or $step -eq "both") {
    # Node.js download mirror, read by fnm
    [Environment]::SetEnvironmentVariable("FNM_DIR", $FnmDir, "User")
    [Environment]::SetEnvironmentVariable("FNM_NODE_DIST_MIRROR", $NodeMirror, "User")
    $env:FNM_DIR = $FnmDir
    $env:FNM_NODE_DIST_MIRROR = $NodeMirror

    # npm registry. The npm_config_registry env var is ignored by an already
    # installed node, so it must go into ~/.npmrc which npm always reads.
    $lines = if (Test-Path $Npmrc) { Get-Content $Npmrc } else { @() }
    $lines = @($lines | Where-Object { $_ -notmatch '^\s*registry\s*=' })
    Set-Content -Path $Npmrc -Value (@($lines) + "registry=$NpmMirror") -Encoding UTF8

    # PowerShell hook: drop any previous fnm lines, keep everything else.
    # Read as one string so wrapped long lines are still matched correctly.
    if (-not (Test-Path $PsProfile)) {
        New-Item -ItemType Directory -Path (Split-Path $PsProfile -Parent) -Force | Out-Null
    }
    $kept = ""
    if (Test-Path $PsProfile) {
        $raw = Get-Content $PsProfile -Raw
        # remove whole lines that invoke fnm, or that are the fnm banner comment
        $raw = [regex]::Replace($raw, '(?m)^[^\r\n]*fnm\.exe[^\r\n]*\r?\n?', '')
        $raw = [regex]::Replace($raw, '(?m)^# fnm:[^\r\n]*\r?\n?', '')
        $kept = $raw.TrimEnd()
    }
    $content = @("# fnm: create FNM_MULTISHELL_PATH so 'fnm use' works", $PsHook)
    if ($kept) { $content += "" ; $content += $kept }
    Set-Content -Path $PsProfile -Encoding UTF8 -Value $content

    # cmd.exe hook, since cmd never reads $PROFILE
    Set-Content -Path $CmdHook -Encoding ASCII -Value @(
        '@echo off',
        'rem Auto-generated by install-fnm.ps1. Creates FNM_MULTISHELL_PATH for cmd.exe.',
        $CmdHookBody,
        'exit /b 0'
    )
    $autoRunKey = "HKCU:\Software\Microsoft\Command Processor"
    if (-not (Test-Path $autoRunKey)) { New-Item -Path $autoRunKey -Force | Out-Null }
    New-ItemProperty -Path $autoRunKey -Name "AutoRun" -Value "call `"$CmdHook`"" -PropertyType String -Force | Out-Null

    Write-Host "`n  Configured:" -ForegroundColor Green
    Write-Host "    FNM_DIR              = $FnmDir   (User env)"
    Write-Host "    FNM_NODE_DIST_MIRROR = $NodeMirror   (User env)"
    Write-Host "    npm registry         = $NpmMirror   (~/.npmrc)"
    Write-Host "    PowerShell hook      = $PsProfile"
    Write-Host "    cmd hook             = $CmdHook  (via AutoRun)"
}

# ---- Warn about nvm, which also owns the node command ----
$nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME","Machine")
if (-not $nvmHome) { $nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME","User") }
if ($nvmHome) {
    Write-Host "`n  Warning: nvm is installed and also manages node." -ForegroundColor Yellow
    Write-Host "    NVM_HOME    = $nvmHome" -ForegroundColor Yellow
    Write-Host "    NVM_SYMLINK = $([Environment]::GetEnvironmentVariable('NVM_SYMLINK','Machine'))" -ForegroundColor Yellow
    Write-Host "  Whichever appears first in PATH wins, so fnm use may have no" -ForegroundColor Yellow
    Write-Host "  visible effect. If node -v shows the old version, remove nvm first." -ForegroundColor Yellow
}

Write-Host @"

  Open a NEW terminal, then verify:

    fnm list
    fnm use 24
    node -v

  If 'fnm use' still complains about environment variables, the hook did not
  run. In cmd.exe, run this by hand once:
    call `"$CmdHook`"

"@ -ForegroundColor Cyan