# 🦊 KrsVim Wiki

Welcome to the **KrsVim** documentation! KrsVim is a fast, Windows-first, WSL-aware Neovim distribution built around a modular architecture and rounded floating UI modules (`lua/plugins/krs/`).

> 🦊 **Neovim Version:** Currently running on **NVIM v0.12.4** (requires Neovim >= 0.10).

> 🌱 **Never used Vim or Neovim before?** This wiki assumes you know what "buffer", "leader key", and "Normal mode" mean. If you don't, read **[Neovim Basics](neovim-basics.md)** first — 5 minutes, then everything below will make sense.

> 🔎 **Searching this wiki:** inside this modal, press `/` or `Ctrl+F` in either pane to search it (native Neovim search — `n`/`N` repeats). Left pane searches page titles, right pane searches the open page's text.

---

## 🏁 New User Quick Start (First 5 Minutes)

If you have just installed or launched KrsVim for the first time, follow these steps:

1. **Start Neovim**: Run `nvim` in your terminal. On first startup, `lazy.nvim` automatically downloads and installs all editor plugins.
2. **Open the Dashboard & Wiki**: If you land on the dashboard screen, press `w` to open this Wiki inside Neovim (or run `:KrsWiki` / `:NvimWiki` from anywhere, or `<C-S-d>`).
3. **Sync External Dependencies**: KrsVim relies on a few external CLI utilities (like `ripgrep`, `fd`, `gcc`, `chafa`, `node`, `bun`, `go`, `dotnet`). Run the automated setup script for your platform:
   - **Windows (PowerShell)**: `powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1`
   - **Linux / WSL / Git Bash**: `./scripts/setup.sh`
   *(These scripts are idempotent—safe to run at any time! If you haven't run them yet, KrsVim will still run with [graceful fallbacks](installation.md#⚡-what-if-you-havent-run-setupps1-or-setupsh).)*
4. **Discover Shortcuts**: Press `<C-S-p>` to launch the **Command Palette**, or press `?` / `<F1>` in any window to get instant, context-aware keyboard help.
5. **Want to change something?** Every feature here is meant to be edited by you, not just read about — [How-To & Customization Guide § Quick Answer](how-to-customize-editor.md#⚡-quick-answer-how-do-i-change-x) is the fastest path from "I don't like this" to "fixed it myself."

---

## 📌 Table of Contents

### 🌐 Supported Languages & Toolchain Guides
| Language / Tech | Wiki Page | Description |
| :--- | :--- | :--- |
| 🐘 **PHP & Laravel** | [**PHP & Laravel Guide**](languages/php.md) | Intelephense, Pint, PHP-CS-Fixer, blade-formatter, blade-nav.nvim, Xdebug |
| 🟨 **TypeScript / JS** | [**TypeScript / JS Guide**](languages/typescript.md) | tsc, eslint, biome, prettier/prettierd, js-debug-adapter, type-injector |
| 🎯 **C# / .NET / Blazor** | [**C# & Blazor Guide**](languages/csharp.md) | OmniSharp, csharp-ls, csharpier, netcoredbg, lemminx XML |
| 🟦 **Go** | [**Go Guide**](languages/go.md) | gopls, delve DAP, gofumpt, goimports |
| 🐍 **Python** | [**Python Guide**](languages/python.md) | pyright, debugpy DAP, black, isort, ruff |
| 🌙 **Lua & Scripts** | [**Lua & Scripts Guide**](languages/lua.md) | lua_ls, stylua, type_injector, krsnvimtranspiler |
| 🌐 **Web Frontend Vanilla** | [**Web Frontend Guide**](languages/web.md) | HTML, CSS, Tailwind CSS, Emmet, snippets |
| 🪐 **Web Frameworks** | [**Astro Guide**](languages/astro.md) | Astro LSP and Prettier |
| 🧩 **Web UI** | [**Web UI Guide**](languages/web-ui.md) | Svelte, Angular, React/TSX, TypeScript LSP |
| 🦀 **Rust** | [**Rust Guide**](languages/rust.md) | rust-analyzer, rustfmt, Cargo |
| 🐳 **Docker & Proto** | [**Docker & Proto Guide**](languages/docker-proto.md) | dockerls, dockerfmt, protolint |
| 🐚 **Shell / Bash** | [**Shell & Bash Guide**](languages/bash.md) | bashls, bash-debug-adapter, beautysh, shellcheck |

### 🏁 Getting Started & Setup
| Page | Contents |
| :--- | :--- |
| 🌱 [**Neovim Basics**](neovim-basics.md) | Modes, buffers/windows/tabs, VSCode-style shortcuts — start here if you're new to Vim/Neovim itself |
| ⚙️ [**Installation & Dependencies**](installation.md) | Setup scripts (`setup.ps1` / `setup.sh`), Scoop/APT commands, health checks & graceful fallbacks |
| 🎓 [**How-To & Customization Guide**](how-to-customize-editor.md) | Step-by-step guide for adding plugins, local modules, new languages, themes, and terminals |
| 🛠️ [**Languages, LSP & Formatting**](languages.md) | Mason servers, Conform formatters, Treesitter parsers & completion tuning |
| 🌐 [**Adding a Language / LSP**](adding-language.md) | Step-by-step guide for adding new language servers, formatters & debuggers |
| 📦 [**Plugin Inventory**](plugins.md) | Comprehensive listing of third-party plugins and custom `krs` modules |

### ⌨️ Daily Driving & Workflow
| Page | Contents |
| :--- | :--- |
| ⌨️ [**Keybinds Reference**](keybinds.md) | Full shortcut reference categorized by domain |
| 🧰 [**Command Palette**](command-palette.md) | `<C-S-p>` launcher, command registration & fuzzy action runner |
| 🗂️ [**Workspaces & Sessions**](workspaces.md) | Per-project session slots (`<C-S-w>`), tab persistence & buffer cleanups |
| 🐙 [**Git Control Center**](git-center.md) | Interactive Git staging, restore, commit form & submodules (`<C-S-g>`) |
| 🐙 [**Secondary Git Repos**](secondary-git.md) | Decoupled secondary Git repositories with Dotfiles pattern (`:SecondaryGitManager`) |
| 📁 [**File Explorers**](file-explorer.md) | Desktop & WSL explorers (`<C-S-f>`), project pickers & Neo-tree integration |
| 🙈 [**Neo-tree Custom Hidden**](neo-tree-hidden.md) | Visual file & folder hiding in Neo-tree (`H`/`gh`), theme-derived highlights & Command Palette |
| 🖥️ [**Multi-Terminal Manager**](terminals.md) | 9 independent terminal buffers (`<A-1>`..`<A-9>`), height memory & auto-WSL |
| 🎛️ [**Editor Quality of Life**](editor-qol.md) | Smart quit, context help (`?`/`<F1>`), colorscheme preview, image viewer (`:ImageViewer`), font sizing & PHP diagnostics |
| 🎨 [**Color Palette & Themes**](color-palette.md) | HSL palette architecture and live theme swapping (`:KrsThemePicker`) |

### 🚀 Building, Running & Debugging
| Page | Contents |
| :--- | :--- |
| 🛠️ [**Task Runner**](tasks.md) | Auto-discovery build tasks, custom command chains & 4 background output slots (`<C-1..4>`) |
| 🚀 [**Launch Profiles**](launch-profiles.md) | `.krsnvim/launch.json`, smart launch (`<C-S-s>`), profile manager (`<C-S-q>`) & dev-server bridge |
| 🐞 [**Debug Adapters (DAP)**](debug-adapters.md) | Full debugger guide, Bun adapter, repl completion & troubleshooting |
| 🔴 [**Breakpoints**](breakpoints.md) | Session breakpoint persistence (`.krsnvim/breakpoints.json`), conditional breakpoints & logpoints |

### 🧬 Code Helpers & Tooling
| Page | Contents |
| :--- | :--- |
| 🌬️ [**Tailwind Organizer**](tailwind-organizer.md) | Automatic multi-row class sorting on save (`:TailwindOrganize`) |
| 🧬 [**Type Injector**](type-injector.md) | Per-project Lua/TS type schemas and `@types` installer (`:TypeInjector`) |
| 📝 [**Input Modal Component**](input-modal.md) | Unified rounded floating input dialog replacing standard `vim.ui.input` |
| 📄 [**JSON Schemas**](schemas-json.md) / [**TOML Schemas**](schemas-toml.md) | Local schema catalogs, auto-completion & validation |

### 🏛️ Architecture & Extension
| Page | Contents |
| :--- | :--- |
| 🏛️ [**Architecture Overview**](architecture.md) | Four-layer architecture, startup sequence & dependency graph |
| 🧩 [**Module Architecture**](module-architecture.md) | How `lua/plugins/krs` modules self-register with `lazy.nvim` |
| 🔌 [**Creating Local Plugins**](how-to-create-local-plugin.md) | Step-by-step guide for creating custom local features in `lua/plugins/krs/` |
| 🧬 [**Managing Lua Type Schemas**](how-to-manage-lua-type-schemas.md) | Create/update/delete/register a [Type Injector](type-injector.md) Lua schema by hand, no picker needed |
| 🧬 [**Managing TypeScript Type Schemas**](how-to-manage-typescript-type-schemas.md) | Same, for TypeScript/JS — fetching real `.d.ts` files straight from the npm registry, no `npm install` |
| 📶 [**Dynamic Z-Index Manager**](z-index.md) | Centralized Z-index stack manager (`krs.core.z_index`) for floating windows |
| 🧪 [**Testing Suite**](testing.md) | Running unit & integration tests (`:KrsTest`, `tests/run.lua`) |

---

## ⚡ Essential Cheatsheet & Key Shortcuts

### 💡 LSP, Code Navigation & Symbol Help
| Shortcut | Action | Details |
| :--- | :--- | :--- |
| `<A-k>` / `<M-k>` | **Go to Definition** | Jump directly to symbol definition (`<C-o>` jumps back) |
| `<A-S-k>` / `<M-S-k>` | **Show Symbol Usages** | Open Telescope picker with all usages of symbol (or toast if 0 usages) |
| `K` / `<S-k>` | **Hover Documentation** | Show doc popup under cursor |
| `<C-j>` / `<C-k>` | **Signature / Parameter Help** | Show function parameter types & signature popup |
| `<C-.>` | **Code Actions / Quick Fix** | Open caret dropdown for fixes, refactors, and imports |
| `<F2>` | **Rename Symbol or File** | Rename symbol project-wide or file on disk |

### 🐙 Git Operations & Staging
| Shortcut | Action | Details |
| :--- | :--- | :--- |
| `<C-S-g>` | **Git Control Center** | Interactive staging, live diff, branch manager, commit & push |
| `<C-S-x>` | **Stage All Changed Files** | Quick global shortcut to stage all unstaged/untracked files |
| `<S-CR>` / `<S-Enter>` *(in Git Center)* | **Open File at First Change** | Open file in bufferline tab and position cursor on 1st changed line (`zz`) |
| `<CR>` *(in Git Center)* | **Side-by-Side Diff Modal** | Open full-screen dual-pane diff preview |
| `s` / `S` *(in Git Center)* | **Stage File / Stage All** | Stage file under cursor or visual selection / stage all |
| `u` / `U` *(in Git Center)* | **Unstage File / Unstage All** | Unstage file under cursor or selection / unstage all |
| `r` / `R` *(in Git Center)* | **Restore File / Restore Section** | Discard changes in selected file / discard entire section |
| `c` / `m` / `t` / `C` *(in Git Center)* | **Commit Form & Commit** | Edit title (`c`), description (`m`), tag (`t`), execute commit (`C`) |

### 🧭 Navigation & Tab Operations
| Shortcut | Action | Details |
| :--- | :--- | :--- |
| `<A-h>` / `<A-l>` | **Switch Tabs (Left / Right)** | Cycle to previous / next bufferline tab (`gt` / `gT`) |
| `<C-o>` / `<C-i>` | **Jump Back / Jump Forward** | Navigate backward and forward in line jump history |
| `<C-h>` / `<C-l>` | **Focus Left / Right Pane** | Switch window focus between split panes or float panels |
| `]c` / `[c` | **Next / Previous Git Hunk** | Jump directly to next or previous change hunk in active file |

### 🎛️ Floating Panels & General Tools
| Shortcut | Action | Details |
| :--- | :--- | :--- |
| `<leader>wm` | **Main Menu / Dashboard** | Open landing dashboard |
| `<C-S-p>` | **Command Palette** | Fuzzy-searchable action runner for all commands & tools |
| `<C-S-f>` | **File Explorer** | Floating desktop & WSL file explorer and project picker |
| `<C-S-w>` | **Workspaces & Sessions** | Manage per-project session slots and buffer states |
| `<C-S-t>` | **Task Runner** | Auto-discovered build, test, and package manager tasks |
| `<C-S-s>` / `<C-S-q>` | **Launch & Debug Profiles** | Run default profile / open launch profile manager |
| `<C-S-d>` / `:KrsWiki` | **Wiki & Documentation** | Dual-pane offline documentation modal |
| `?` / `<F1>` | **Context-Aware Help** | Display keyboard shortcuts for the focused panel |
| `<C-;>` | **Toggle Active Terminal** | Toggle floating terminal buffer |
| `<A-1>`..`<A-9>` | **Terminal Slots 1..9** | Switch between 9 independent background terminals |

---

## 🚀 Core Design Philosophy

1. **Everything is a Local Module**: All custom features live in `lua/plugins/krs/*.lua` as single-file lazy specs backed by pure testable modules in `lua/krs/`.
2. **Per-Project State (`.krsnvim/`)**: Tasks, launch profiles, breakpoints, and type definitions stay inside your project directory rather than polluting global editor state.
3. **First-Class Debugging**: Pre-configured DAP adapters for JS/TS, Bun, Python, Go, C#, PHP, C/C++, and Rust with persistent breakpoints and REPL integration.
4. **Unified Floating UI**: Input popups, file pickers, git controls, and terminals share a cohesive rounded design system managed by a centralized [Z-Index Manager](z-index.md).
5. **Multi-Layout Support**: Built-in compatibility for US Standard, US-International, Latam, and European keyboards.
