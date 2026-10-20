# Windows Environment Bootstrap

Minimal, idempotent, install-on-demand. One script per tool.

Each script prints its install locations first, then waits for you to press
`1` to install or `0` to exit.

## Scripts

| File | Installs | Administrator | Scope |
| --- | --- | --- | --- |
| `install-choco.ps1` / `.bat` | Chocolatey | yes | Machine-wide |
| `install-scoop.ps1` / `.bat` | Scoop | no | Current user |
| `scoop-install-fnm.ps1` | fnm + Node.js mirrors | no | Current user |
| `scoop-install-uv.ps1` | uv + Python mirrors | no | Current user |
| `scoop-install-rust.ps1` | rustup + crates.io mirror | no | Current user |
| `scoop-install-go.ps1` | Go + Qiniu module proxy | no | Current user |

The `scoop-install-*` scripts require Scoop to be installed first.

## Usage

```powershell
# Interactive (the .bat auto-elevates for Chocolatey)
.\install-choco.bat
.\install-choco.bat D:\myenv
.\install-scoop.bat
.\install-scoop.bat D:\myenv

# PowerShell
powershell -ExecutionPolicy Bypass -File .\install-choco.ps1 -Root "D:\myenv"

# Automation / CI: -Yes skips the menu
powershell -ExecutionPolicy Bypass -File .\install-scoop.ps1 -Root "D:\myenv" -Yes
```

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-Root` | `D:\env` | Install root. Actual paths are printed on startup; overriding it prints an extra note. |
| `-Yes` | off | Skip the menu and install immediately. |

## Default install locations (Root = `D:\env`)

**Chocolatey**

| Path | Purpose |
| --- | --- |
| `D:\env\chocolatey` | Install root |
| `D:\env\chocolatey\bin` | `choco.exe` and command shims |
| `D:\env\chocolatey\lib` | Package cache |

**Scoop**

| Path | Purpose |
| --- | --- |
| `D:\env\scoop` | Install root |
| `D:\env\scoop\global` | Global apps |
| `D:\env\scoop\shims` | Command shims |
| `D:\env\scoop\apps` | Installed apps |

## Official installers

Both scripts download and run the official installer, nothing else:

| Tool | Installer URL |
| --- | --- |
| Chocolatey | `https://community.chocolatey.org/install.ps1` |
| Scoop | `https://get.scoop.sh` |

Notes:

- The Chocolatey installer has **no `-InstallDir` parameter**. It reads the
  install location from `$env:ChocolateyInstall`, which the script sets.
- The Scoop installer requires the target directory to be missing or empty,
  so only the parent directory is created beforehand.
- The Scoop installer refuses to run as Administrator unless `-RunAsAdmin`
  is passed, so the script adds it when it detects an elevated session.

## Idempotency

Rerunning is safe: if the install directory exists, the script reports it as
already installed and exits. If that installation is broken, remove the
directory first — the script prints the exact command.

## Notes

- **Use `scoop.cmd` in PowerShell**, not `scoop`. The Scoop shim is a `.ps1`
  file and gets blocked by the execution policy. To use plain `scoop`:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```
- **Prefer a normal-privilege session for Scoop.** If you run it elevated the
  script adds `-RunAsAdmin` automatically, but day-to-day use is better
  unelevated.
- **Script files must be UTF-8 with BOM.** Windows PowerShell 5.1 and cmd
  decode BOM-less UTF-8 as GBK, which corrupts quotes in non-ASCII text and
  causes `ParserError`. Keep the BOM when editing (first 3 bytes:
  `EF BB BF`). `chcp 65001` does **not** replace the BOM, it only affects
  console display.

## fnm and Node.js mirrors

`scoop-install-fnm.ps1` menu:

| Choice | Action |
| --- | --- |
| `1` | Install fnm via Scoop, then configure mirrors and shell hooks |
| `2` | Configure mirrors and shell hooks only |
| `0` | Exit |

`-Yes` runs both steps without asking.

**fnm does not read nvm's `settings.txt`.** The mapping:

| nvm `settings.txt` | fnm equivalent |
| --- | --- |
| `node_mirror` | `FNM_NODE_DIST_MIRROR` environment variable |
| `npm_mirror` | `registry=` in `~/.npmrc` |
| `path` | managed automatically by fnm |
| `arch` | `FNM_ARCH` (auto-detected, usually unset) |

| Setting | Where | Value | Read by |
| --- | --- | --- | --- |
| `FNM_DIR` | User env var | `D:\env\fnm` | fnm |
| `FNM_NODE_DIST_MIRROR` | User env var | `https://npmmirror.com/mirrors/node/` | fnm (node downloads) |
| `registry=` | `~/.npmrc` | `https://npmmirror.com/mirrors/npm/` | npm (`npm install`) |

### Why the shell hooks are required

`fnm use` fails with *"We can't find the necessary environment variables to
replace the Node version"* unless `FNM_MULTISHELL_PATH` is set, and **only
`fnm env` can create that variable**. So simply setting environment variables is
not enough — every new shell must evaluate `fnm env`:

| Shell | Mechanism | Written to |
| --- | --- | --- |
| PowerShell | profile script | `$PROFILE` |
| cmd.exe | `AutoRun` registry value | `~\fnm-env.cmd` |

cmd.exe never reads `$PROFILE`, which is why it needs its own hook. The hooks
pass `--fnm-dir` and `--node-dist-mirror` explicitly so they also work in shells
that started before the environment variables were written.

Open a **new** terminal afterwards, then:

```powershell
fnm install 24      # or: fnm install --lts
fnm list
fnm use 24
node -v
```

**nvm conflict:** if nvm is installed, both tools claim the `node` command and
whichever appears first in PATH wins. The script warns but does not modify nvm.

## uv and Python mirrors

`scoop-install-uv.ps1` menu:

| Choice | Action |
| --- | --- |
| `1` | Install uv via Scoop, then configure mirrors |
| `2` | Configure mirrors only |
| `0` | Exit |

`-Yes` runs both steps without asking.

**uv needs no shell hook.** Unlike fnm, uv resolves Python versions itself and
you call it through `uv run` / `uv venv` / `uv pip`, so nothing is added to
`$PROFILE`.

| Setting | Where | Value |
| --- | --- | --- |
| `python-install-mirror` | `%APPDATA%\uv\uv.toml` | `https://registry.npmmirror.com/-/binary/python-build-standalone` |
| `[[index]] url` | `%APPDATA%\uv\uv.toml` | `https://mirrors.aliyun.com/pypi/simple/` |
| `[pip] index-url` | `%APPDATA%\uv\uv.toml` | `https://mirrors.aliyun.com/pypi/simple/` |
| `UV_CACHE_DIR` | User env var | `D:\env\scoop\persist\uv\cache` |
| `UV_PYTHON_INSTALL_DIR` | User env var | `D:\env\scoop\persist\uv\python\versions` |
| `UV_TOOL_DIR` | User env var | `D:\env\scoop\persist\uv\tools\versions` |

uv's data is kept under the Scoop root rather than `%APPDATA%`, so it travels
with the Scoop install.

Open a **new** terminal afterwards, then:

```powershell
uv python install 3.12    # download a Python version (uses the mirror)
uv python list --only-installed
uv init                   # create a project
uv add requests            # add a dependency (uses the PyPI mirror)
    uv run python             # run Python in the project environment
```

## Rust

`scoop-install-rust.ps1` menu: `1` install + configure, `2` configure only, `0` exit.

Rust has **two** separate mirrors, because rustup and cargo download from
different places:

| What | Where | Value |
| --- | --- | --- |
| Toolchain | `RUSTUP_DIST_SERVER` env var | `https://rsproxy.cn` |
| Toolchain updates | `RUSTUP_UPDATE_ROOT` env var | `https://rsproxy.cn/rustup` |
| Crate dependencies | `~/.cargo/config.toml` | `sparse+https://rsproxy.cn/index/` |

The script also runs `rustup default stable`. Without it rustc and cargo exist
but refuse to run with *"rustup could not choose a version of rustc to run"*.

The sparse index protocol requires Rust 1.68 or newer.

```powershell
rustc --version
cargo --version
rustup show            # installed toolchains
rustup update          # newest stable
```

**MSVC build tools required.** rustup installs the MSVC toolchain, which needs
the Visual C++ Build Tools to link binaries. Without them `cargo build` fails
with `linker link.exe not found`. The script checks for them via `vswhere` and
warns if missing. Install from
<https://visualstudio.microsoft.com/visual-cpp-build-tools/> selecting
**MSVC - VS C++ x64/x86 build tools** and **Windows SDK**.

## Go

`scoop-install-go.ps1` menu: `1` install + configure, `2` configure only, `0` exit.

Go needs no shell hook. Version selection is per project via `go.mod`:

```toml
toolchain go1.22.0
```

| Setting | Where | Value |
| --- | --- | --- |
| `GOPROXY` | `go env -w` → `%APPDATA%\go\env` | `https://goproxy.cn,direct` (Qiniu) |
| `GOSUMDB` | `go env -w` → `%APPDATA%\go\env` | `sum.golang.org` |

The script uses `go env -w` rather than setting `$env:GOPROXY`, so the value
persists in the Go environment file and every tool reads it.

```powershell
go version
go env GOPROXY
go mod init myproject
go get github.com/gin-gonic/gin@latest
```

## Java

Not covered. SDKMAN! does not support native Windows — it needs WSL, Cygwin or
Git Bash with MinGW. On native Windows use `scoop install temurin17` (or another
JDK) and switch with `scoop reset <package>`.