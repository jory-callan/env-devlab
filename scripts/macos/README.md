# macOS Environment Bootstrap

Idempotent, install-on-demand. One script per step, mirrors the Windows
scripts (`../windows`).

## Scripts

| File | Installs | Scope |
| --- | --- | --- |
| `install-brew.sh` | Homebrew | `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel) |
| `brew-install-tools.sh` | Common CLI tools | via Homebrew |
| `fnm-install.sh` | fnm (Fast Node Manager) + mirrors | current user |
| `node-install-globals.sh` | Global npm packages | via fnm-installed node |
| `uv-install.sh` | uv + PyPI/Python mirrors | current user |

`brew-install-tools.sh` requires Homebrew. Run `install-brew.sh` first.

## Usage

```bash
# Interactive (prints the plan, then 1 = install / 0 = exit)
./install-brew.sh

# Automation / CI: -y skips the menu
./install-brew.sh -y

# Optional mirror: Aliyun (git clones + API + bottles)
./install-brew.sh --mirror aliyun -y

# Common tools
./brew-install-tools.sh
./brew-install-tools.sh -y
```

## Global npm packages

`node-install-globals.sh` installs Node tools globally with `npm install -g`.
The list lives in the `GLOBALS=()` array — just add names to install more.

| Package | Purpose |
| --- | --- |
| `serve` | Static file server |
| `pnpm` | Fast package manager |

Idempotent: packages already in `npm list -g` are skipped; one failure does
not stop the rest.

## fnm (Node.js) mirrors

`fnm-install.sh` menu: `1` install + configure, `2` configure only, `0` exit.

**fnm does not read nvm's `settings.txt`.** The mapping:

| nvm `settings.txt` | fnm equivalent |
| --- | --- |
| `node_mirror` | `FNM_NODE_DIST_MIRROR` environment variable |
| `npm_mirror` | `registry=` in `~/.npmrc` |
| `path` | managed automatically by fnm (default `~/.local/share/fnm`) |

| Setting | Where | Value | Read by |
| --- | --- | --- | --- |
| `FNM_NODE_DIST_MIRROR` | `~/.zprofile` / `~/.bashrc` | `https://npmmirror.com/mirrors/node/` | fnm (node downloads) |
| `registry=` | `~/.npmrc` | `https://registry.npmmirror.com/` | npm (`npm install`) |

### Why the shell hook is required

`fnm use` fails with *"We can't find the necessary environment variables to
replace the Node version"* unless `FNM_MULTISHELL_PATH` is set, and **only
`fnm env` can create that variable**. So every login shell must evaluate
`eval "$(fnm env --use-on-cd)"`:

| Shell | Written to |
| --- | --- |
| zsh (macOS default) | `~/.zprofile` (export + hook) |
| bash | `~/.bashrc` (export + hook) |

Re-running the script skips profiles that already contain its marker.
Open a **new** terminal afterwards:

```bash
fnm install 24      # or: fnm install --lts
fnm list
fnm use 24
node -v
```

fnm is installed via Homebrew (`brew install fnm`) when brew is available,
otherwise via the official installer (`https://fnm.vercel.app/install`).

## uv (Python) mirrors

`uv-install.sh` menu: `1` install + configure, `2` configure only, `0` exit.

**uv needs no shell hook.** Unlike fnm, uv resolves Python versions itself and
you call it through `uv run` / `uv venv` / `uv pip`.

| Setting | Where | Value |
| --- | --- | --- |
| `python-install-mirror` | `~/.config/uv/uv.toml` | `https://registry.npmmirror.com/-/binary/python-build-standalone` |
| `[[index]] url` (default) | `~/.config/uv/uv.toml` | `https://mirrors.aliyun.com/pypi/simple/` |
| `[pip] index-url` | `~/.config/uv/uv.toml` | `https://mirrors.aliyun.com/pypi/simple/` |

If `~/.config/uv/uv.toml` already exists but was **not** written by this
script, the script prints its content and does not touch it. Cache and
Python data stay in the default locations (`uv cache dir`, `uv python dir`)
on `~/.cache/uv`.

uv is installed via Homebrew (`brew install uv`) when brew is available,
otherwise via the official installer (`https://astral.sh/uv/install.sh`).

```bash
uv python install 3.12    # download a Python version (uses the mirror)
uv init && uv add requests && uv run python
```

## Aliyun mirror (install-brew.sh)

`--mirror aliyun` sets, for the install session only:

| Env var | Value |
| --- | --- |
| `HOMEBREW_API_DOMAIN` | `https://mirrors.aliyun.com/homebrew-bottles/api` |
| `HOMEBREW_BOTTLE_DOMAIN` | `https://mirrors.aliyun.com/homebrew-bottles` |

It also re-points the git remotes of `Homebrew`, `homebrew-core` and
`homebrew-cask` to `mirrors.aliyun.com` so `brew update` keeps using the
mirror. To make it permanent, the script prints the `export` lines to add
to `~/.zprofile`.

Without `--mirror`, everything comes from official sources.

## Tools installed by brew-install-tools.sh

The list lives in the `FORMULAE=()` array at the top of the script — edit it
to suit your needs:

| Package | Purpose |
| --- | --- |
| `wget` | HTTP downloads |
| `p7zip` | 7z archives |
| `iproute2mac` | `ip` command (iproute2 style) |
| `tree` | Directory trees |
| `jq` / `yq` | JSON / YAML parsing |
| `ripgrep` / `fd` | Fast grep / find |
| `fzf` | Fuzzy finder |
| `tmux` | Terminal multiplexer |
| `htop` | Process monitor |
| `bat` / `lsd` | `cat` / `ls` with color |
| `duf` / `procs` | `df` / `ps` alternatives |
| `httpie` | HTTP client |
| `cloc` | Line counter |
| `lazygit` | Git TUI |

Menu option `2` installs packages one by one so you can pick each one.

## Idempotency

Both scripts are safe to rerun:

- `install-brew.sh` exits early if `brew` is already on PATH.
- `brew-install-tools.sh` skips packages that `brew list` already reports.

## Apple Silicon notes

Homebrew installs to `/opt/homebrew`, which is not on PATH by default. The
script prints the two commands to add `brew shellenv` to `~/.zprofile`.
