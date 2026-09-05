# 🌐 Adding a New Language / LSP to Neovim Config

[← Back to Wiki Index](index.md)

This guide outlines the exact step-by-step procedure for adding new programming language support, Language Servers (LSPs), Treesitter syntax highlighting, and auto-formatters to this Neovim setup.

> ⚠️ **This config is not the "add each server to one big `servers = {}` table" style.** Every language owns one file, [`lua/krs/langs/<language>/init.lua`](../lua/krs/langs/), exporting `M.lsp_config`, `M.mason`/`M.mason_order`, `M.formatters_by_ft`, and (optionally) DAP config. `lua/plugins/lsp/lsp.lua`, `lua/plugins/lsp/formatting.lua`, and `lua/krs/core/installer.lua` only *merge* those per-language tables — they have no hardcoded per-language entries to edit. See [`docs/languages.md`](languages.md) for the full picture.

---

## 🧠 Understanding Property Origins & Specifications

When authoring a language module, fields come from standard Neovim APIs and community plugin specs:

1. **`M.lsp_config`** *(Standard Neovim `vim.lsp.Config` & `nvim-lspconfig`)*:
   - `filetypes = { "c", "cpp" }`: Neovim buffer filetypes that trigger this server.
   - `cmd = { "clangd", "--background-index" }`: Command array executed to launch the server.
   - `root_dir`: Function or `root_pattern(...)` determining the project workspace root.
   - `settings`: Table of server-specific options sent via LSP `workspace/didChangeConfiguration`.
   - `capabilities`: LSP client capabilities (e.g. `capabilities = { offsetEncoding = { "utf-16" } }` for `clangd`).

2. **`M.formatters_by_ft` & `M.conform_formatters`** *(Standard `conform.nvim`)*:
   - `M.formatters_by_ft`: Maps filetypes to formatter names (e.g. `php = { "pint", "php_cs_fixer", stop_after_first = true }`).
   - `M.conform_formatters`: Overrides formatter execution:
     - `condition = function(self, ctx)`: Returns `true` if formatter should run (e.g. checking binary existence or `.prettierrc`).
     - `command`: Overrides the CLI executable name.
     - `args`: Array or callback returning arguments passed to the CLI binary.
     - `stdin`: Boolean, whether tool reads code from stdin (default `true`).

3. **`M.dap_configs` & `M.dap_setup`** *(Standard `nvim-dap`)*:
   - `type`: Adapter name registered in `dap.adapters` (e.g., `"codelldb"`, `"php"`, `"python"`).
   - `request`: `"launch"` or `"attach"`.
   - `program`: Path to executable or script.
   - `cwd`: Working directory.

4. **`M.mason`** *(KrsVim Language Tooling Manager)*:
   - `mason`: Mason registry package name.
   - `type`: `"lsp"` | `"formatter"` | `"dap"` | `"extra"` (drives UI grouping).
   - `cmd`: Binary name used to detect an already-installed tool via `executable()`.
   - `lang` / `name`: Human-readable label displayed in `:LanguageManager`.

---

## ⚖️ Vanilla Neovim vs. KrsVim Architecture

To appreciate why KrsVim uses single-file language modules, here is a comparison of how **pure vanilla Neovim (0.10+)** configures tools versus how **KrsVim** centralizes them:

### 1. Vanilla Neovim Way (No Framework or Plugins)
In vanilla Neovim, you write autocmds to spawn `vim.lsp.start`, handle formatting with `vim.fn.system()`, and set keymaps on `LspAttach`:

```lua
-- Vanilla Neovim (0.10+) LSP start
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "c", "cpp" },
	callback = function(args)
		vim.lsp.start({
			name = "clangd",
			cmd = { "clangd", "--background-index" },
			root_dir = vim.fs.root(args.buf, { "compile_commands.json", "CMakeLists.txt", ".git" }),
			capabilities = vim.lsp.protocol.make_client_capabilities(),
		})
	end,
})

-- Vanilla Format-on-Save via raw CLI binary (clang-format)
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = { "*.c", "*.cpp" },
	callback = function(args)
		local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
		local formatted = vim.fn.system("clang-format", table.concat(lines, "\n"))
		if vim.v.shell_error == 0 then
			vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, vim.split(formatted, "\n"))
		end
	end,
})
```

### 2. KrsVim Centralized Architecture
Instead of scattering manual autocmds across multiple config files, KrsVim puts all LSP settings, formatters, Mason packages, DAP debuggers, and runtimes into **one single file per language** (`lua/krs/langs/<language>/init.lua`).

```
┌────────────────────────────────────────────────────────────────────────┐
│                        KRSVIM AGGREGATION MODEL                        │
│                                                                        │
│  lua/krs/langs/cpp/init.lua ──────► M.lsp_config  ──► lsp.lua        │
│                             ──────► M.formatters ──► formatting.lua │
│                             ──────► M.mason      ──► installer.lua  │
│                             ──────► M.dap        ──► dap.lua        │
└────────────────────────────────────────────────────────────────────────┘
```

| Domain | Pure Vanilla Neovim | KrsVim Architecture |
|---|---|---|
| **LSP Setup** | Manual `vim.lsp.start()` or raw `lspconfig` | `M.lsp_config` in `lua/krs/langs/<lang>/init.lua` |
| **Tool Installs** | Manual OS package commands (`apt`/`brew`) | Opt-in bundle installer via `:LanguageManager` UI |
| **Formatting** | Manual `system()` or `vim.lsp.buf.format` | Async preference chains (`prettierd` -> `prettier`) via `conform.nvim` |
| **Completion** | Hand-rolled `omnifunc` | NvChad layout with CSS color preview badges via `blink.cmp` |

---

## 🛠️ Step-by-Step Guide

### Step 1: Create (or extend) `lua/krs/langs/<language>/init.lua`
Every field is optional — only add what the language needs. You can copy the interactive template file [`lua/krs/langs/init_template.lua`](../lua/krs/langs/init_template.lua) or see [`lua/krs/langs/csharp/init.lua`](../lua/krs/langs/csharp/init.lua) for the fullest example.

```lua
local M = {}

-- lspconfig server name(s) this language owns
M.lsp_server = { "zls" }

-- lspconfig opts, keyed by server name -- merged into lsp.lua's opts.servers.
-- The `---@type table<string, vim.lsp.Config>` annotation gets you completion +
-- hover for every entry's fields (cmd, root_dir, filetypes, settings, on_attach,
-- ...) while you write it -- `vim.lsp.Config` ships in Neovim's own runtime
-- (lua/vim/lsp.lua), already on lua_ls's workspace library for this config.
---@type table<string, vim.lsp.Config>
M.lsp_config = {
    zls = {},
}

-- Mason package metadata, keyed by lspconfig/formatter/tool name.
-- `lang`/`name` + `type` drive the Language Tooling Manager UI and status scan.
M.mason = {
    zls = { mason = "zls", lang = "Zig", type = "lsp", cmd = "zls" },
}
M.mason_order = { "zls" } -- install/display order for this language's Mason packages

-- conform.nvim formatter list per filetype
M.formatters_by_ft = {
    zig = { "zigfmt" },
}

return M
```

Then register the module in [`lua/krs/langs/init.lua`](../lua/krs/langs/init.lua)'s `M.langs` table:

```lua
M.langs = {
    -- ...existing entries
    zig = require("krs.langs.zig"),
}
```

> ⚠️ **Why is this step required?**
> `lsp.lua`'s `build_servers()` and `formatting.lua`'s `build_formatters_by_ft()` both loop over `require("krs.langs").langs` and merge each module's `lsp_config` / `formatters_by_ft`. A language missing from `M.langs` contributes nothing — no LSP server enable, no formatter, no Mason package tracked — no matter what's inside its `init.lua`.

---

### Step 2: Add bundle metadata to the same `init.lua`
This repo has **no automatic Mason install**: `mason-lspconfig` is set up with `automatic_installation = false, ensure_installed = {}` in [`lua/plugins/lsp/lsp.lua`](../lua/plugins/lsp/lsp.lua). It also has **no automatic Treesitter parser install** beyond the fresh-install `core_parsers` list in [`lua/plugins/lsp/treesitter.lua`](../lua/plugins/lsp/treesitter.lua) (`lua`, `vim`, `vimdoc`, `markdown`, `markdown_inline`). Everything else — Mason LSP/DAP/formatter packages *and* Treesitter parsers — installs through an opt-in **Language Bundle**, shown in `:LanguageManager` (aliases: `:KrsLanguageManager`, `:LanguageTooling`).

`lua/krs/core/installer.lua`'s `M.language_bundles` is **built automatically** from every language module's own metadata — nothing to hand-add there. A language only shows up as a bundle once its `init.lua` sets `M.bundle_name`; the bundle's Mason package list is resolved straight from the `M.mason_order` you already wrote in Step 1 (via `M.get_mason_package_name`), so the two can never drift out of sync. Add to the same `init.lua` from Step 1:

```lua
-- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "⚡ Zig"
M.requires = {
    { cmd = "zig", name = "Zig toolchain", hint = "https://ziglang.org/download" },
}
M.treesitter = { "zig" }
```

Optional extra fields:
- `M.is_minimal = true` — marks the always-on core bundle (reserved for Lua/editor-internal filetypes; not for real languages).
- `M.bundle_extra_mason_pkgs = { "some-pkg" }` — Mason packages the bundle should install that are intentionally **not** in `M.mason` (e.g. a DAP tool installed through a different mechanism, a standalone linter). See `lua/krs/langs/go/init.lua` (`delve`, `golangci-lint`) for an example.
- `M.dotnet_tools = { "some-tool" }` — `dotnet tool install -g` packages, see `lua/krs/langs/csharp/init.lua`.

Skip this step only if the language should ship as part of `core_parsers` (the fresh-install default set) instead of an opt-in bundle — reserve that for editor-internal filetypes like Lua/markdown/vimdoc, not real languages.

---

### Step 3: (Optional) Debug Adapter

Add the DAP config to the **same lang module** from Step 1. Two shapes are supported:

- **Static list** (most languages — see `php`, `csharp`, `python`): add `M.dap_filetypes` (array of filetypes) and `M.dap_configs` (array of nvim-dap config tables).
- **Function** (languages that register an adapter at runtime — see `bash`, `go`, `lua`): add `M.dap_setup = function(dap) ... end`.

Then add the language key to the iteration list in [`lua/plugins/editor/dap.lua`](../lua/plugins/editor/dap.lua) (the `ipairs({ "python", "csharp", ... })` line) to control where in the debugger picker this language's configs appear.

For a **launch-profile runtime** (`M.launch_runtimes`): the runtime definition also goes in the lang module — [`lua/krs/launch/runtimes.lua`](../lua/krs/launch/runtimes.lua) auto-merges every language's `launch_runtimes`. The only edit needed there is adding the runtime key to `M.order` so the profile form can cycle to it.

See [`docs/debug-adapters.md`](debug-adapters.md) for the full DAP setup guide.

---

## ⚡ Quick Checklist for New Languages

| Component | File to Edit | Key Section |
|---|---|---|
| **LSP Server + Formatter + Mason metadata** | [`lua/krs/langs/<language>/init.lua`](../lua/krs/langs/) | `M.lsp_config`, `M.formatters_by_ft`, `M.mason`/`M.mason_order` |
| **Register the module** | [`lua/krs/langs/init.lua`](../lua/krs/langs/init.lua) | Add to `M.langs` |
| **Install bundle (Mason pkgs + Treesitter parsers)** | [`lua/krs/langs/<language>/init.lua`](../lua/krs/langs/) | `M.bundle_name`, `M.requires`, `M.treesitter` |
| **Debug Adapter (optional)** | [`lua/krs/langs/<language>/init.lua`](../lua/krs/langs/) (primary) · [`lua/plugins/editor/dap.lua`](../lua/plugins/editor/dap.lua) (add key to picker order) · [`lua/krs/launch/runtimes.lua`](../lua/krs/launch/runtimes.lua) (add key to `M.order`, if adding a launch runtime) | See [debug-adapters.md](debug-adapters.md) |

`lua/plugins/lsp/lsp.lua`, `lua/plugins/lsp/formatting.lua`, `lua/plugins/lsp/treesitter.lua`, and `lua/krs/core/installer.lua` need **no edits** for a new language — they only aggregate what the language module declares (`installer.lua`'s `M.language_bundles` is built from it automatically).

---

## 🔍 Verification & Debugging

- Open a file of the target language and run:
  ```vim
  :LspInfo
  ```
  Ensure the expected language server appears under **Active client(s)**.
- Run `:LanguageManager` and confirm the new bundle shows `[✅ Installed (n/n)]` after installing.
- For code completion, start typing or press `<C-space>` to open the `blink.cmp` completion menu.
