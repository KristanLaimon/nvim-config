j 🤖 AGENTS.md — KrsVim AI Assistant Guidelines & Compact Wiki Reference

This file defines mandatory guidelines and reference links for AI coding assistants working in or customizing this Neovim distribution (**KrsVim**).

> 🌐 **Per-Language Documentation Reference**: Individual language toolchain guides, debug profiles, and LSP/formatter commands are documented under [`docs/languages/`](docs/languages/) (e.g., [`php.md`](docs/languages/php.md), [`typescript.md`](docs/languages/typescript.md), [`cpp.md`](docs/languages/cpp.md), [`zig.md`](docs/languages/zig.md), [`ruby.md`](docs/languages/ruby.md), [`haskell.md`](docs/languages/haskell.md), [`teal.md`](docs/languages/teal.md), [`github.md`](docs/languages/github.md), [`web.md`](docs/languages/web.md), [`astro.md`](docs/languages/astro.md), [`web-ui.md`](docs/languages/web-ui.md), [`rust.md`](docs/languages/rust.md), [`csharp.md`](docs/languages/csharp.md), [`go.md`](docs/languages/go.md), [`python.md`](docs/languages/python.md), [`lua.md`](docs/languages/lua.md), [`docker.md`](docs/languages/docker.md), [`proto.md`](docs/languages/proto.md), [`bash.md`](docs/languages/bash.md)).

---

## 📌 1. Mandatory Development & Architecture Guidelines

### 🌐 1.1 Language Additions & Tooling Registration Rule

**Centralized-config pattern**: everything specific to one language -- LSP server settings, Mason package names, formatter assignment, indentation defaults -- lives in that language's own `lua/krs/langs/<language>/init.lua`, never scattered across `lsp.lua`/`formatting.lua`/`installer.lua`. Those three files only *aggregate* what each language module exports; swapping a tool (e.g. `tsc` -> `tsgo`) or changing its settings is a one-file edit. See `lua/krs/langs/typescript/init.lua` for the fullest example. A language module exports whichever of these fields it needs:

| Field | Shape | Consumed by |
|---|---|---|
| `M.lsp_server` | array of lspconfig server names (`{"tsc"}`, even for a single server -- rare multi-server languages just list more) | `installer.lua` bundles, cross-refs from other modules |
| `M.lsp_config` | `{ [server_name] = <lspconfig opts: root_dir, settings, filetypes, ...> }` | `lua/plugins/lsp/lsp.lua` merges every language's `lsp_config` into `opts.servers` |
| `M.mason` | `{ [tool_name] = { mason=, cmd=, lang=/name=, type="lsp"\|"formatter"\|"dap" } }` | `lua/krs/core/installer.lua` merges every language's `mason` into `M.tools` |
| `M.mason_order` | array of tool-name strings, this language's Mason install/display order | `installer.lua` concatenates these into `M.mason_packages` |
| `M.formatters_by_ft` | `{ [filetype] = <conform formatter list> }` | `lua/plugins/lsp/formatting.lua` merges into `opts.formatters_by_ft` |
| `M.conform_formatters` | `{ [formatter_name] = <conform formatter opts: condition/args> }` | `formatting.lua` merges into `opts.formatters` |
| `M.dap_filetypes` + `M.dap_configs` | array of filetypes; array of static nvim-dap config tables | `lua/plugins/editor/dap.lua` calls `debuggers._shared.add(dap, dap_filetypes, dap_configs)` for languages with a plain static list (see `php`/`csharp`/`python`) |
| `M.dap_setup` | `function(dap)` | `dap.lua` calls this instead, for languages whose adapter needs runtime setup (conditional adapter registration, delegating to another plugin's own `setup()`) -- see `bash` (conditional bashdb/bash adapter), `go` (`dap-go`), `lua` (krsnvimscript adapter) |
| `M.launch_runtimes` | `{ [runtime_key] = { command=, dap=, execute= } }` | `lua/krs/launch/runtimes.lua` merges every language's `launch_runtimes` into its registry -- one language can own several runtime flavors (e.g. `typescript` owns `bun`/`node`/`deno`) |

A handful of truly generic, cross-language things have no owning module and stay where they are instead of being forced into one:
- **Generic servers** with no per-language buffer-default concept (TOML/YAML/XML: `taplo`, `yamlls`, `lemminx`) stay directly in `lsp.lua`/`installer.lua`.
- **Cross-language debuggers** that serve multiple `krs.langs` modules at once (`bun`/`node`/`browsers` -- all debug the same JS/TS/web filetypes via js-debug or Bun's own adapter) stay as their own file in `lua/plugins/krs/debuggers/`, loaded explicitly by `dap.lua` alongside the per-language loop.
- **`custom`** (the fallback launch runtime for anything unrecognized) has no language at all and stays in `runtimes.lua`.

Don't invent a language module, or force a field into one, just to host something that doesn't actually belong to a single language.

When adding support for a new programming language (or updating an existing one):
1. **Put everything in `lua/krs/langs/<language>/init.lua`**: LSP server settings, Mason metadata, formatter assignment, debugger config, launch-profile runtimes, indentation defaults, environment path resolution, and setup hooks -- see the field table above. This includes the install-wizard grouping: `M.bundle_name`, `M.requires`, `M.treesitter` (`M.bundle_extra_mason_pkgs`/`M.dotnet_tools` when needed). Register the submodule in `lua/krs/langs/init.lua`'s `M.langs` (and its `M.lang_order`). Document the language in a dedicated file under [`docs/languages/<lang>.md`](docs/languages/).
2. **Nothing to touch in `installer.lua`**: `M.language_bundles` is built automatically from every module's `bundle_name`/`requires`/`treesitter`, and its `mason_pkgs` is resolved straight from the `mason_order` you already wrote -- the two can never drift. The language appears as an optional selectable bundle in the Language Tooling Manager (`:LanguageManager`, `:KrsLanguageManager`) the moment `M.bundle_name` is set.


### 🌙 1.2 Minimal Fresh Setup Rule (Lua Only)
* **Default Fresh Behavior**: On a fresh Neovim installation, the default toolchain installation MUST remain **minimal** (Lua language server `lua_ls`, `stylua` formatter, and core editor parsers `lua`, `vim`, `vimdoc`, `markdown` only).
* **No Background Heavy Installs**: Never auto-install optional language tools (PHP, TypeScript, Python, Go, C#, Docker, Shell) in the background without explicit user selection.
* **UI Selection**: Users choose which optional language toolchains to install using the UI selection menu:
  - **`Select All` (`a`)**: Selects all optional language bundles for installation.
  - **`Select None` (`n`)**: Deselects optional languages, reverting to minimal Lua core.
  - **`Per-Row Toggle` (`Space` / `Enter`)**: Selects/deselects individual language bundles (e.g. PHP & Laravel).

### 🧰 1.3 Command Palette Preference (No `<leader>` Shortcuts)
* **Prefer Command Palette Commands**: Always prefer registering actions and tools in the **Command Palette** (`<C-S-p>` or `:CommandPalette`) over assigning `<leader>` keymaps.
* **Command Registration**: Add user-facing features to `M.commands` in `lua/plugins/krs/command_palette.lua` with descriptive names and categories.
* **Ex Commands**: Provide explicit User Commands (e.g., `:FormatDocument`, `:PHPCheckTools`, `:BladeNavClearCache`) so actions are discoverable via Neovim command-line completion and palette search.

---

## 🏛️ 2. Neovim Architecture Summary

KrsVim follows a modular four-layer design:
1. **`lua/`**: Core editor options (`vim_options.lua`), global keymaps (`keymaps/`), and plugin manager entry (`lazy_init.lua`).
2. **`lua/krs/`**: Pure, testable core modules (UI float helpers, installer, workspace sessions, project path resolution, Z-index manager).
3. **`lua/plugins/`**: Plugin specifications loaded by `lazy.nvim`:
   - `lua/plugins/editor/`: Core editor plugins (Telescope, Neo-tree, DAP, Treesitter).
   - `lua/plugins/lsp/`: LSP configs (`lsp.lua`), formatters (`formatting.lua`), autocompletion (`blink.cmp`), and Laravel support (`laravel.lua`).
   - `lua/plugins/krs/`: KRS local UI modules (Command Palette, Task Runner, Git Center, Terminal Manager, Theme Picker).
4. **`.krsnvim/`**: Per-project config directory created in workspace roots holding tasks, launch profiles, breakpoints, and local script definitions.

---

## 📚 3. Wiki Sitemap & Comprehensive Use-Case Index

Refer to the specific wiki documentation page for each feature or development use case:

### 🏁 Getting Started & System Setup
* ⚙️ [**Installation & System Dependencies**](docs/installation.md) — Setup scripts (`setup.ps1` / `setup.sh`), Scoop/APT commands, health checks & fallbacks.
* 🌱 [**Neovim Basics**](docs/neovim-basics.md) — Buffers, windows, tabs, and VSCode-style editing fundamentals.
* 🎓 [**How-To & Customization Guide**](docs/how-to-customize-editor.md) — Step-by-step guide for adding plugins, local modules, and custom themes.
* 🛠️ [**Languages, LSP & Formatting**](docs/languages.md) — Mason package definitions, Conform formatter pipelines & Treesitter parser setup.
* 🌐 [**Adding a Language / LSP**](docs/adding-language.md) — Walkthrough for integrating a new language server, formatter, and DAP profile.
* 📦 [**Plugin Inventory**](docs/plugins.md) — Full index of built-in `lua/plugins/krs/` modules and third-party lazy plugins.

### ⌨️ Daily Driving & Workflow Use Cases
* 🧰 [**Command Palette**](docs/command-palette.md) — `<C-S-p>` action runner, command registration API & fuzzy search.
* ⌨️ [**Keybinds Reference**](docs/keybinds.md) — Comprehensive keyboard shortcuts organized by feature domain.
* 🗂️ [**Workspaces & Sessions**](docs/workspaces.md) — Per-project session slots (`<C-S-w>`), tab persistence & buffer cleaner.
* 🐙 [**Git Control Center**](docs/git-center.md) — Interactive staging, side-by-side diffs, branch switcher & commit form (`<C-S-g>`).
* 📁 [**File Explorers**](docs/file-explorer.md) — Desktop & WSL file browsers (`<C-S-f>`) and Neo-tree sidebar integration.
* 🖥️ [**Multi-Terminal Manager**](docs/terminals.md) — 9 background terminal slots (`<A-1>`..`<A-9>`), height memory & toggle (`<C-;>`).
* 🎛️ [**Editor Quality of Life**](docs/editor-qol.md) — Context-aware help (`?`/`<F1>`), image viewer (`:ImageViewer`), theme picker & font sizing.
* 🎨 [**Color Palette & Themes**](docs/color-palette.md) — NvChad/Nagatoro theme architecture and palette switcher (`:KrsThemePicker`).

### 🚀 Tasks, Launch Profiles & Debugging Use Cases
* 🛠️ [**Task Runner**](docs/tasks.md) — Auto-discovered build/test tasks (`<C-S-t>`) & background output slots (`<C-1..4>`).
* 🚀 [**Launch Profiles**](docs/launch-profiles.md) — `.krsnvim/launch.json` profile manager (`<C-S-q>`) & default launcher (`<C-S-s>`).
* 🐞 [**Debug Adapters (DAP)**](docs/debug-adapters.md) — Interactive debugging launcher (`<F5>`), REPL completion & adapter setup.
* 🔴 [**Breakpoints Management**](docs/breakpoints.md) — Persistent breakpoints (`<C-b>`), conditional breakpoints, and `.krsnvim/breakpoints.json`.
* 🧪 [**Testing Suite**](docs/testing.md) — Running unit tests for local config modules (`:KrsTest`).

### 🧬 Code Helpers & Tooling Use Cases
* 🌬️ [**Tailwind Class Organizer**](docs/tailwind-organizer.md) — Multi-row class sorting on save or on command (`:TailwindOrganize`).
* 🧬 [**Type Injector**](docs/type-injector.md) — Per-project Lua & TypeScript type definitions manager (`:TypeInjector`).
* 📋 [**Snippets Manager**](docs/snippets-manager.md) — Create, edit, override & list per-language VSCode JSON snippets (`:SnippetManager`).
* 📚 [**Offline Documentation Store**](docs/offline-docs-manager.md) — Store & fuzzy search language docs offline per version (`:DocManager`).
* 📝 [**Input Modal Dialog**](docs/input-modal.md) — Rounded floating dialog for `vim.ui.input`.
* 📄 [**JSON Schemas Catalog**](docs/schemas-json.md) & [**TOML Schemas Catalog**](docs/schemas-toml.md) — Local offline validation schemas.
* ⚙️ [**VSCode Compatibility**](docs/vscode-support.md) — Native support for `.vscode/settings.json`, `launch.json` & `tasks.json` (`:VSCodeSettings`).

---

## 🌐 4. Supported Language Guides (`docs/languages/`)

Detailed setup, Ex commands, DAP debug profiles, and plugin integrations for each supported language:

* 🐘 [**PHP & Laravel Guide**](docs/languages/php.md) — Intelephense, Pint, PHP-CS-Fixer, blade-formatter, `blade-nav.nvim`, Xdebug (`:PHPCheckTools`, `:BladeNavClearCache`, `:FormatDocument`).
* 🟨 [**TypeScript & JavaScript Guide**](docs/languages/typescript.md) — `tsc`, ESLint, Biome, Prettier/Prettierd, `js-debug-adapter`, `type-injector`, `tailwind-organizer`.
* ⚡ [**C / C++ Guide**](docs/languages/cpp.md) — `clangd`, `clang-format`, `cppcheck`, `cpplint`, `codelldb` DAP.
* ⚡ [**Zig Guide**](docs/languages/zig.md) — `zls` (Zig Language Server), `zigfmt` (`zig fmt`).
* 💎 [**Ruby Guide**](docs/languages/ruby.md) — `solargraph`, `rubocop`.
* 🔮 [**Haskell Guide**](docs/languages/haskell.md) — `haskell-language-server` (hls), `fourmolu`, `hlint`.
* 🩵 [**Lua Extras & Teal Guide**](docs/languages/teal.md) — `teal-language-server` (`teal_ls`), `luacheck`, `selene`.
* 🐙 [**GitHub Actions Guide**](docs/languages/github.md) — `gh-actions-language-server`, `actionlint`.
* 🎯 [**C# / .NET / Blazor Guide**](docs/languages/csharp.md) — OmniSharp, `csharp-ls`, CSharpier, `netcoredbg` (Blazor Server & DLL debugging), `:DotnetNew`, `:NugetManager`.
* 🟦 [**Go Guide**](docs/languages/go.md) — `gopls`, `delve` DAP (`nvim-dap-go`), `gofumpt`, `goimports`.
* 🐍 [**Python Guide**](docs/languages/python.md) — `pyright`, `debugpy` DAP, `black`, `isort`, `ruff`.
* 🌙 [**Lua & KrsVim Scripts Guide**](docs/languages/lua.md) — `lua_ls`, `stylua`, `type_injector`, `krsnvimtranspiler` (`:KrsTranspile`).
* 🌐 [**Web Frontend Vanilla Guide**](docs/languages/web.md) — HTML, CSS, Tailwind CSS, Emmet, and snippets.
* 🪐 [**Astro Guide**](docs/languages/astro.md) — Astro LSP and Prettier formatting.
* 🧩 [**Web UI Guide**](docs/languages/web-ui.md) — Svelte, Angular, React/TSX, and the shared TypeScript toolchain.
* 🦀 [**Rust Guide**](docs/languages/rust.md) — rust-analyzer, rustfmt, Cargo, and Treesitter.
* 🐳 [**Docker Guide**](docs/languages/docker.md) — `dockerls`, `dockerfmt`.
* 📜 [**Protocol Buffers Guide**](docs/languages/proto.md) — `buf_ls`, `protols`, `protolint`.
* 🐚 [**Shell / Bash & PowerShell Guide**](docs/languages/bash.md) — `bashls`, `powershell_es`, `bash-debug-adapter`, `beautysh`, ShellCheck.

---

## 🧪 5. Headless Quality Checks (CI / CLI)

Run all quality gates from the command line without opening the UI:

### All checks at once (lint + syntax + tests)

```bash
nvim --headless -c "lua _G.arg = {'--all'}; dofile(vim.fn.stdpath('config') .. '/run_me.lua')" -c "qa!"
```

### Individual checks

```bash
# Lint & format (stylua + luacheck)
nvim --headless -c "lua _G.arg = {'--lint'}; dofile(vim.fn.stdpath('config') .. '/run_me.lua')" -c "qa!"

# Syntax check (parse all Lua files)
nvim --headless -c "lua _G.arg = {'--syntax'}; dofile(vim.fn.stdpath('config') .. '/run_me.lua')" -c "qa!"

# Test suite
nvim --headless -c "lua _G.arg = {'--tests'}; dofile(vim.fn.stdpath('config') .. '/run_me.lua')" -c "qa!"
```

### Required tools

| Tool | Install | Purpose |
|------|---------|---------|
| `stylua` | `cargo install stylua or scoop install stylua on windows (preferred)` | Auto-format Lua code |
| `luacheck` | `luarocks install luacheck or scoop install luacheck on windows (prefferred)` | Static analysis / linting |

Both must be on `PATH`. The scripts exit 1 with an install hint if either is missing.

---

## ⚡ Quick Rule Summary for AI Assistants

> [!IMPORTANT]
> 1. **Always keep fresh setups minimal** (Lua core only).
> 2. **Always list new languages in `:LanguageManager`** as optional UI selections.
> 3. **Prefer Command Palette options** over assigning `<leader>` keymaps.
> 4. **Reference dedicated wiki pages** under [`docs/languages/`](docs/languages/) for language-specific toolchain details.
> 5. **Place ALL per-language config** -- LSP settings, Mason metadata, formatter assignment, debugger config, launch-profile runtimes, indentation defaults -- in `lua/krs/langs/<language>/init.lua` (see §1.1's field table) and register the module in `lua/krs/langs/init.lua`. `lsp.lua`/`formatting.lua`/`installer.lua`/`dap.lua`/`runtimes.lua` only aggregate; never hardcode a language's settings there.
