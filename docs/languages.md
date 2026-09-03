# 🛠️ Languages, LSP, Formatters & Parsers

[← Back to Wiki Index](index.md)

Nothing below installs automatically on first start: `mason-lspconfig` is configured with `automatic_installation = false, ensure_installed = {}` (`lua/plugins/lsp/lsp.lua`), and Treesitter only auto-installs the fresh-install `core_parsers` (`lua`, `vim`, `vimdoc`, `markdown`, `markdown_inline`). Everything else — LSP/DAP/formatter Mason packages and non-core Treesitter parsers — installs per language via the opt-in **Language Bundle** picker: run `:LanguageManager`.

**Where a language's actual settings live**: `lua/krs/langs/<language>/init.lua` — LSP server settings, Mason package names, formatter assignment, debugger config and launch-profile runtimes are all defined there, one file per language. `lua/plugins/lsp/lsp.lua` (servers + completion), `lua/plugins/lsp/formatting.lua` (Conform), `lua/plugins/lsp/treesitter.lua` (parsers), `lua/plugins/editor/dap.lua` (debug adapters), and `lua/krs/core/installer.lua` (Mason install list) only *aggregate* what every language module exports — swapping a tool means editing the one language file, not four.

---

## 📋 Matrix

| Language / Environment | LSP server | Formatter (Conform) | Treesitter parser | Debug adapter |
|---|---|---|---|---|
| **Lua** | `lua_ls` | `stylua` | `lua` | — |
| **JSON** | `jsonls` *(SchemaStore + local schemas)* | `prettierd` → `prettier` → `biome` | `json` | — |
| **Web Frontend Vanilla** | `html`, `cssls`, `emmet_ls`, `tailwindcss` | `prettierd` → `prettier` → `biome` | `html`, `css` | browser adapters |
| **Web Frameworks (Astro)** | `astro` | `prettier` (always) | `astro` | browser adapters |
| **Web UI (Svelte / Angular / React)** | `svelte`, `angularls`, `vtsls` | `prettierd` → `prettier` → `biome` | `svelte`, `html`, `scss`, `typescript`, `javascript`, `tsx`, `jsx` | `js-debug-adapter`, Bun adapter |
| **Python** | `basedpyright`, `ruff` | `black` → `isort` → `ruff` | `python` | `debugpy` DAP |
| **Go** | `gopls` | `gofumpt` → `goimports` | `go`, `gomod`, `gowork`, `gotmpl` | `delve` DAP (`nvim-dap-go`) |
| **C# / .NET / Blazor** | `omnisharp` | `csharpier` | `csharp` | `netcoredbg` |
| **PHP & Laravel** | `intelephense` | `pint` → `php_cs_fixer` → `blade-formatter` | `php`, `blade` | Xdebug |
| **Rust** | `rust_analyzer` | `rustfmt` | `rust` | — |
| **Shell / Bash** | `bashls` | `beautysh` | `bash` | `bash-debug-adapter` |
| **Docker & Proto** | `dockerls`, `buf_ls` | `dockerfmt`, `protolint` | `dockerfile`, `proto` | — |

---

## 🧠 Server notes

## 🟨 Language Details & Documentation Sitemap

### 🌐 [TypeScript / JavaScript / Web UI](languages/web-ui.md) & [TypeScript Suite](languages/typescript.md)
**TypeScript and React run on `vtsls`.** Its settings live in `lua/krs/langs/typescript/init.lua`; its installable LSP, formatter, parser, and debug-adapter components are grouped under **Web UI (Svelte, Angular, React)** in `:LanguageManager`. It roots at `tsconfig.json` / `jsconfig.json` / `package.json`, and falls back to the file's own directory when the only match would be `$HOME` — otherwise opening a stray script indexes the whole home directory. Automatic type acquisition is off; types come from the [Type Injector](type-injector.md) instead.

**Diagnostics are native.** The configured TypeScript server advertises `diagnosticProvider`, so Neovim pulls and refreshes diagnostics itself.

**PHP** — `intelephense` with a large stub set and `maxSize = 5000000`, allowing Laravel's larger Composer class-map files to be indexed. `pint` and `php_cs_fixer` are conditional formatters: they only run when the binary is on `PATH` **or** `vendor/bin/pint(.bat)` / `vendor/bin/php-cs-fixer(.bat)` exists upward from the file. `.blade.php` is remapped to the `blade` filetype. `:PHPCheckTools` reports which PHP tools are missing on the host and inside WSL, with install steps.

**Astro and biome** — biome cannot format `.astro` templates at all, so those files are pinned to `prettier` (the project needs `prettier-plugin-astro` installed). Everywhere else the chain is `prettierd` → `prettier` → `biome`, `stop_after_first`.

**Mason has its own spec** (`cmd = "Mason"`) so `:Mason` exists on an empty Neovim. Pulled in only as an `nvim-lspconfig` dependency, its `setup()` runs on `BufReadPre` — no file open, no `:Mason`, which is exactly the state you're in when opening the dashboard on a fresh install.

**Format on save** via `conform.nvim` (`timeout_ms = 1000`, `lsp_fallback = true`). Manual: `<leader>ff` for the file or the visual selection.

**Schemas** — `schemastore.nvim` for `package.json`, `tsconfig.json`, `.eslintrc`… plus the local catalogs documented in [JSON Schemas](schemas-json.md) and [TOML Schemas](schemas-toml.md).

---

## ➕ Adding a Treesitter parser

`nvim-treesitter` is pinned to the `main` branch (the rewrite), which dropped `highlight.enable`. Highlighting is started per-buffer by a `FileType` autocmd calling `vim.treesitter.start()`, wrapped in `pcall` — parser names don't always match filetype names (`tsx` → `typescriptreact`, `vimdoc` → `help`), so the autocmd matches every filetype and lets `pcall` skip the ones with no parser.

- **Editor-internal filetype** (part of the fresh-install default, e.g. Lua/markdown/vimdoc): add it to `core_parsers` at the top of `lua/plugins/lsp/treesitter.lua`, then `:TSUpdate` or restart.
- **Real language**: add it to that language's own `M.treesitter = { ... }` list in `lua/krs/langs/<language>/init.lua` (`lua/krs/core/installer.lua`'s `M.language_bundles` picks it up automatically), then install via `:LanguageManager` (parsers are opt-in per bundle, not installed on startup).

No autocmd or pattern edits needed either way. For a full new language (server + formatter + parser), see [Adding a Language / LSP](adding-language.md).

---

## 👁️ LSP Reference Counter & CodeLens (`plugins.krs.tools.lsp_references`)

KrsVim displays reference counts (`󰌹 3 references`, `1 reference`) above functions, methods, classes, and structs across all supported languages:

- **Default State**: **ON** by default.
- **Toggle Command**: Run `:KrsToggleReferences` or press `<leader>tr`.
- **Command Palette**: Accessible inside Command Palette (`<C-Shift-P>`) under `👁️ Toggle LSP Reference Counts / CodeLens (Default: ON)`.
- **Zero Complexity for New Languages**: Any language server attached to Neovim (such as `tsc`, `gopls`, `rust_analyzer`, `intelephense`, `pyright`, `clangd`, `omnisharp`, `lua_ls`) automatically streams code lenses according to standard LSP specs.

---

## ⚡ Completion (blink.cmp & Colorify)

`blink.cmp` powers autocompletion with NvChad layout:
- **Left Column**: Kind icon pill (` 󰊕 `, ` 󰩫 `, ` 󰀫 `, ` 󰌋 `, ` 󰌗 `) styled with dedicated background & accent colors (`CmpKindBg_*`) from the active theme.
- **Color Items**: CSS & Tailwind hex/RGB colors render a preview rectangle badge (` ██ `) using the exact hex color with luminance contrast text (`CmpColor_<hex>`).
- **Right Column**: Kind label (`<Snippet>`, `<Function>`, `<Variable>`, etc.).

Two behaviours are tuned:

**Completion is off entirely** in the `krsinputmodal` filetype (so the [input modal](input-modal.md) stays a plain text field) and in any buffer setting `vim.b.completion = false`.

**The menu does not auto-open inside a freshly inserted empty pair** — right after autopairs turns `{` into `{}`, `[` into `[]`, `(` into `()`. This used to be a hard `enabled = false`, which also killed `<C-space>`: you couldn't ask for completion inside `import { | }`, which is the one place you always want it. Now only `menu.auto_show` is suppressed:

```lua
completion = {
  menu = {
    auto_show = function()
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local before, after = line:sub(col, col), line:sub(col + 1, col + 1)
      local pairs_map = { ["{"] = "}", ["["] = "]", ["("] = ")" }
      return pairs_map[before] ~= after
    end,
  },
  documentation = { auto_show = false },
}
```

Documentation is opt-in (`<C-space>`), and `{` / `[` are excluded from trigger characters so bracket-pair snippets don't fire on every keystroke.

### Custom completion sources

| Source | Fires in | Offers |
|---|---|---|
| [`krs.lsp.dap_repl_source`](debug-adapters.md#36-repl-completion-immediate-window) | `dap-repl`, only while a session is live | Real variables from the stopped frame, via the adapter's `completions` / `scopes` requests |
| [`plugins.krs.dev.launch_cmp`](launch-profiles.md#-intellisense-inside-launchjson) | Any file named `launch.json` | Discovered project tasks for `pre_launch_tasks`, runtimes for `runtime`, `run`/`debug` for `mode` |
