```

            /\   /\
           ( ..   .. )      _  __ ____  ____
            \  Y  /        | |/ /|  _ \/ ___|
         /\_/\   /\_/\     | ' / | |_) \___ \
        (  o o     o o)    | . \ |  _ < ___) |
         \  ~   ~  /       |_|\_\|_| \_\____/
          \___^___/

```

# 🦊 KrsVim - An orange-fox nvim tailored for fox coders

![krsnv-cover](./.github/cover.png)
![krsnv-editor](./.github/editor-example.png)
![krsnv-editor-v2](./.github/cover-with-transparency.png)

My personal Neovim setup — a mini-distro, if you like. Fork it, use it, break it. Windows is first-class, WSL is layered on top, plain Linux should mostly hold up (open an issue if it doesn't 🦊).

> 🦊 **Neovim Version:** Currently running on **NVIM v0.12.4** (requires Neovim >= 0.10).

Expect sharp edges and highly opinionated wiring.

---

## 🖥️ Dashboard shortcuts

The start screen. One letter per entry:

| Key | Opens |
|---|---|
| `f` | File Explorer (Desktop) |
| `p` | Recent projects |
| `l` | File Explorer (WSL) — Windows only, shown when WSL is installed |
| `w` | Wiki / documentation (`:NvimWiki`) |
| `e` | Plugins & extensions (`:Lazy`) |
| `m` | LSPs & languages (`:Mason`) |
| `q` | Quit |

Return to the dashboard from anywhere with `<leader>wm`; closing the last open buffer also lands here.

---

## ⚡ Quick Setup

After cloning into `%LOCALAPPDATA%\nvim` (Windows) or `~/.config/nvim` (Linux/macOS):

- **Windows (PowerShell)**: `powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1`
- **Linux / WSL / Git Bash**: `./scripts/setup.sh`

These idempotent scripts automatically install missing external dependencies (`ripgrep`, `fd`, `gcc`, `chafa`, Node.js, Bun, Go, .NET SDK). If you don't run them right away, KrsVim will still run with [graceful fallbacks](docs/installation.md#⚡-what-if-you-havent-run-setupps1-or-setupsh).

---

## 📚 Documentation & Help

Everything else — install, keybinds, debugging, launch profiles, custom modules — lives in the wiki:

- **Documentation Center Modal**: Press `<C-S-d>` (or run `:KrsWiki` / `:NvimWiki`) from anywhere to open the interactive Wiki Reader.
- **➡️ [docs/index.md](docs/index.md)** (Full Wiki Index)
- **➡️ [docs/how-to-customize-editor.md](docs/how-to-customize-editor.md)** (Complete How-To & Customization Guide with Examples)

Start here if you are reading the code:

| Page | What it answers |
|---|---|
| 🎓 [How-To & Customization Guide](docs/how-to-customize-editor.md) | Step-by-step guide for adding plugins, local modules, languages, themes, and terminals |
| 🏛️ [Architecture](docs/architecture.md) | The layers, what may depend on what, startup order, where new code goes |
| 🧩 [Module Architecture](docs/module-architecture.md) | How a file in `lua/plugins/krs/` is both a module and a lazy.nvim spec |
| 🔌 [Creating Local Plugins](docs/how-to-create-local-plugin.md) | Building custom features in `lua/plugins/krs/` using the dual spec-module metatable |
| 🧪 [Testing](docs/testing.md) | Running the suite and writing a spec |

---

## 🧪 Tests

```sh
nvim -l tests/syntax_check.lua                 # every Lua file still parses
nvim -l tests/run.lua                          # unit specs (fast, no plugins)
nvim --headless -S tests/integration/run.lua   # with the real editor loaded
```

Inside the editor: `:KrsTest` (optionally `:KrsTest git` to filter by spec name).

---

## 🦊 Master CLI Runner (`run_me.lua`)

You can run project scripts (test suite, syntax checks, setup dependencies, etc.) using the master Lua CLI:

```sh
# Launch interactive CLI menu
nvim --headless -l run_me.lua

# Run options directly via flags
nvim --headless -l run_me.lua -- --syntax
nvim --headless -l run_me.lua -- --tests
nvim --headless -l run_me.lua -- --setup
nvim --headless -l run_me.lua -- --help
```

