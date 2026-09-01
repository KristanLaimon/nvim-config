# ⚙️ Installation & External Dependencies

[← Back to Wiki Index](index.md)

Welcome to **KrsVim**! Whether you just cloned the repository, ran `nvim` for the very first time, or are looking to ensure all external tools are properly installed, this guide covers everything you need to know.

---

## 🏁 Quick Start: Automated Setup Scripts (Recommended)

KrsVim includes idempotent setup scripts for both Windows and Unix-like environments. These scripts check for missing CLI dependencies and install them automatically. They are safe to run at any time—if a tool is already installed, the script simply skips it.

### 🪟 Windows (PowerShell)
Open PowerShell in your `%LOCALAPPDATA%\nvim` directory and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

*If Scoop is not installed, `setup.ps1` automatically installs Scoop for your user account, adds the `main` and `extras` buckets, and installs all required CLI tools.*

---

### 🐧 Linux / WSL / macOS / Git Bash
Open a terminal in `~/.config/nvim` (or your Windows config directory in Git Bash) and run:

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

*`setup.sh` detects your operating system and package manager (`apt`, `dnf`, `pacman`, `brew`, or `scoop` via Git Bash) and installs the required packages automatically.*

---

## ⚡ What if you haven't run `setup.ps1` or `setup.sh`?

**Don't worry! You can run Neovim immediately.**

When you launch `nvim` for the first time:
1. **`lazy.nvim` auto-bootstraps**: All Neovim plugins will automatically download and install.
2. **Mason auto-installs LSPs**: Language servers, formatters, and debug adapters configured in KrsVim will be managed in the background.

### 🛡️ Graceful Degradation Matrix
If you skip running `setup.ps1` or `setup.sh`, KrsVim handles missing external CLIs gracefully:

| Missing CLI | Affected Feature | Graceful Fallback Behavior |
| :--- | :--- | :--- |
| **`ripgrep` (`rg`)** | Telescope Live Grep (`<C-f>`) | Live grep notifies that `rg` is missing. Standard buffer searches still work. |
| **`fd` / `fdfind`** | Fast file finding (`<C-/>`) | Telescope falls back to native Neovim file scanner. |
| **`gcc` / `MinGW`** | Treesitter C compilation | Pre-compiled parsers load normally. Custom parser compilation notifies if a compiler is missing. |
| **`chafa`** | Image viewer popup (`:ImageViewer`) | Displays a fallback warning modal prompting you to install `chafa` or open via OS (`<C-S-Enter>`). |
| **`node` / `npm`** | JS/TS LSP, Prettier, HTML/CSS | Mason servers requiring Node.js wait until Node is installed on your `PATH`. |
| **`bun`** | Bun debug adapter & profiles | Bun launch profiles notify if `bun` binary is not found. |
| **`go`** | Go LSP (`gopls`) & Delve | Go features activate automatically once Go is present. |
| **`rustc` / `cargo` / `rustfmt`** | Rust LSP and formatting | The Rust bundle needs the Rust toolchain; install it with rustup before selecting the bundle. |
| **`dotnet`** | C# LSP & Nuget manager | Nuget manager (`:NugetManager`) notifies if `dotnet` CLI is missing. |

> 💡 **Tip:** You can run `setup.ps1` or `setup.sh` at any time after using Neovim to instantly fill in any missing dependencies!

---

## 🔍 In-Editor Health Checks & Diagnostics

KrsVim provides several built-in commands to inspect runtime dependencies from within Neovim:

- `:checkhealth` — Standard Neovim system and plugin health report.
- `:Mason` — Opens the Mason UI to view installed LSP servers, formatters, and debug adapters.
- `:Lazy` — Opens the Lazy plugin manager to verify plugin status and updates.
- `:PHPCheckTools` — Diagnostic modal probing host and WSL PHP, Composer, Intelephense, Pint, and Xdebug.
- `:NvimWiki` — Opens this interactive Wiki inside the editor.

---

## 📋 Dependency Reference Table

For manual installation or custom package managers, here is the complete tool checklist:

| Tool / CLI | Purpose in KrsVim | Windows (Scoop) | Linux / WSL Package |
|---|---|---|---|
| **Neovim** (v0.12.4 / >= 0.10) | Core editor runtime (Current setup: `NVIM v0.12.4`) | `scoop install neovim` | `neovim` |
| **Git** | Mason, Neogit, Lazy.nvim, Git Control Center | `scoop install git` | `git` |
| **ripgrep** (`rg`) | Telescope live grep (`<C-f>`) | `scoop install ripgrep` | `ripgrep` |
| **fd** | Fast file finder (`<C-/>`) | `scoop install fd` | `fd-find` (or `fd`) |
| **chafa** | Terminal pixel-art image previewer (`:ImageViewer`) | `scoop install chafa` | `chafa` |
| **GCC / MinGW** | Treesitter parser compilation | `scoop install gcc` | `gcc` / `build-essential` |
| **Node.js & npm** | JS/TS LSP, Prettier, JSON/HTML LSPs | `scoop install nodejs-lts` | `nodejs npm` |
| **Bun** *(optional)* | Bun launch profiles & fast JS runtime | `scoop install bun` | `curl -fsSL https://bun.sh/install \| bash` |
| **Go** *(optional)* | Go LSP (`gopls`), `gofumpt`, Delve debugger | `scoop install go` | `golang` |
| **Rust** *(optional)* | rust-analyzer, rustfmt, Cargo | `scoop install rustup` then `rustup default stable` | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| **.NET SDK** *(optional)*| C# LSP, Nuget manager (`:NugetManager`), `netcoredbg` | `scoop install dotnet-sdk` | `dotnet-sdk-8.0` |
| **WSL** *(optional)* | WSL file explorer (`:TelescopeFileBrowserWSL`), auto-WSL terminal | `wsl --install` | — |

---

## 📂 Per-Project Files (`.krsnvim/`)

KrsVim writes per-project configuration files under `.krsnvim/` at the root of your project directory only when you use specific features:

| File | Feature / Module | Description |
|---|---|---|
| `.krsnvim/tasks.json` | [Task Runner](tasks.md) | Project build tasks, custom commands, and chains. |
| `.krsnvim/launch.json` | [Launch Profiles](launch-profiles.md) | Debugger and runner configurations (`<C-S-q>`). |
| `.krsnvim/breakpoints.json` | [Breakpoints](breakpoints.md) | Persistent DAP breakpoints across sessions. |
| `.krsnvim/types.json` | [Type Injector](type-injector.md) | Custom Lua/TS type definitions and schemas. |

> 📁 **Alternative Directory Names:** If `.krslocal/` or `.nvimkrs/` already exist in your project root, KrsVim respects them as machine-local overrides. No files are created if a feature is unused.

---

## 🖋️ Font & GUI Preferences

KrsVim defaults to **JetBrainsMono Nerd Font** (14pt).
- Adjust font size dynamically in GUI builds (Neovide / Windows GUI) using `<C-+>`, `<C-->`, and `<C-0>`.
- Font size preferences are saved automatically to `font_config.json` in your global `nvim-data` directory (`stdpath("data")`).
- A **Nerd Font** (v3.0+) is strongly recommended for icons in the statusline, file explorer, dashboard, and DAP signs.
