# 🎓 How-To & Configuration Guide: Extending & Customizing KrsVim

[← Back to Wiki Index](index.md)

This comprehensive guide teaches you how to extend, customize, and maintain your **KrsVim** Neovim setup. It is written with easy-to-follow examples for every part of the configuration so you can add new plugins, languages, themes, terminals, or custom modules with complete confidence.

New to Vim/Neovim itself (modes, buffers, the leader key)? Read
[Neovim Basics](neovim-basics.md) first — this page assumes you already know what
those words mean.

---

## ⚡ Quick Answer: "How do I change X?"

Every feature in this config follows the same shape, so the same three steps
find and change almost anything without needing to ask for help:

1. **Find the file.** Every KRS feature lives in one file named after what it
   does: `lua/plugins/krs/<feature>.lua` (e.g. `git_center.lua`, `tasks.lua`,
   `wiki_modal.lua`). Not sure of the name? Search for text you see on screen —
   e.g. if a notification says "Saved as favorite", `grep -rn "Saved as
   favorite" lua/` finds the exact file and line.
2. **Look at the top of that file for `M.settings`.** Keybinds, titles, colors,
   and other tunables are pulled out into this table on purpose — you almost
   never need to touch the logic below it. See `M.settings.keys.open` in
   `lua/plugins/krs/wiki_modal.lua` for an example: change the value, save, and
   the next `:e` or restart picks it up.
3. **Save and reload.** `:source $MYVIMRC` re-runs `init.lua` for options/keymap
   changes; a changed plugin `config` function needs `:Lazy reload <name>` or a
   full restart to re-run. When in doubt, restart — it's fast.

If the change touches logic (not just a setting value), skim
[Testing](testing.md#🔧-i-edited-a-plugin-file--do-i-need-a-test) — most
features have a matching `tests/spec/<feature>_spec.lua` you can run in under a
second while you iterate.

---

## 📂 File Structure & Directory Layout Explanation

```
c:\Users\Kristan\AppData\Local\nvim\
├── init.lua                   -- Main Neovim bootstrap file (loads lua/lazy_init.lua)
├── colors/                    -- Colorscheme files in nagatoro-krs palette format (*-krs.lua & nagatoro-*.lua)
├── docs/                      -- Full offline documentation & Wiki files
├── lua/
│   ├── config/                -- Core editor bootstrap & global options
│   │   ├── options.lua        -- Vim options, filetypes, path resolution
│   │   ├── lazy.lua           -- Lazy.nvim plugin manager bootstrap
│   │   └── keymaps/           -- Global keybindings (lsp.lua, editor.lua, search.lua, debug.lua, krs.lua)
│   ├── krs/                   -- Shared pure Lua libraries (NO keymaps/autocmds, 100% unit-testable)
│   │   ├── core/              -- Store (JSON persistence), Path, Project, UI floats, Z-Index stack
│   │   ├── git/               -- Git command wrappers, porcelain parsers, diff formatters
│   │   ├── launch/            -- Launch profile runtimes & DAP resolvers
│   │   ├── lsp/               -- CodeAction menu, Colorify completion engine, EditorConfig
│   │   └── projects/          -- Starred favorites manager
│   └── plugins/               -- Lazy.nvim plugin specifications
│       ├── editor/            -- Third-party editor plugins (Neo-tree, Telescope, DAP, Auto-pairs)
│       ├── lsp/               -- LSP servers, Mason, Blink.cmp, Conform formatting, Treesitter
│       ├── ui/                -- Dashboard, Bufferline, Statusline, Devicons, Themes
│       ├── miscelanea/        -- Utility plugins
│       └── krs/               -- Custom local KRS modules (each a self-contained Lazy spec)
├── tests/                     -- Unit & integration test suite (`tests/run.lua`)
└── .krsnvim/                  -- Per-project persistent state (tasks.json, launch.json, breakpoints.json)
```

---

## 🎹 0. How to Change Any Keybinding

Two kinds of keybind live in this config, and the fix is different for each —
[keybinds.md](keybinds.md) explains which is which up top:

**Global keybind** (editing, windows, LSP, debugging — anything in
`lua/keymaps/*.lua`): open the matching file, find the key in its
`M.settings.keys` table, change the string, save, `:source $MYVIMRC`.

```lua
-- lua/keymaps/lsp.lua
M.settings = {
    keys = {
        hover = "K",              -- change this to e.g. "<leader>k" if K feels wrong
        rename = "<F2>",
    },
}
```

**Feature keybind** (a KRS panel like Git Center, Wiki, Tasks): same idea, but
inside that feature's own file under `lua/plugins/krs/`, because the key needs
to stay next to the `lazy.nvim` spec that registers it as a lazy-load trigger.

```lua
-- lua/plugins/krs/wiki_modal.lua
M.settings = {
    keys = {
        open = { "<C-S-d>", "<leader>?" }, -- add/remove keys here
    },
}
-- ...further down, the SAME list feeds the lazy.nvim `keys = {...}` spec,
-- so a key added here is automatically also a lazy-load trigger.
```

Picking a key that's already used elsewhere silently breaks one of the two
features — whichever sets the mapping last wins, with no error. Before binding
something new, check it isn't taken: `:verbose nmap <the-key>` inside Neovim
shows what currently owns it (and, usefully, which file set it).

---

## 🎓 1. How to Add a New Third-Party Plugin (Lazy.nvim)

All external plugins are managed via `lazy.nvim`. To add a new plugin:

1. Choose the appropriate subdirectory in `lua/plugins/`:
   - `lua/plugins/editor/` for editor features (pickers, motions, tree-sitter tools).
   - `lua/plugins/ui/` for visual components.
   - `lua/plugins/lsp/` for language tooling.
   - `lua/plugins/miscelanea/` for utility tools.

2. Create a new `.lua` file (e.g., `lua/plugins/editor/mini_surround.lua`):
```lua
-- ============================================================================
-- PLUGINS: Mini.surround -- Fast surround manipulation (add, delete, change quotes/brackets).
-- ============================================================================

return {
    "echasnovski/mini.surround",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
        mappings = {
            add = "sa", -- Add surrounding in Normal and Visual modes
            delete = "sd", -- Delete surrounding
            find = "sf", -- Find surrounding (to the right)
            replace = "sr", -- Replace surrounding
        },
    },
}
```

3. Save the file. Next time you start Neovim (or run `:Lazy`), `lazy.nvim` automatically installs and configures the plugin!

---

## 🔌 2. How to Create a Local KRS Module or `.krslocal` Feature

Custom features in KrsVim live in `lua/plugins/krs/*.lua`. Every file directly inside `lua/plugins/krs/` returns a dual spec-module metatable that auto-registers with `lazy.nvim`.

### Step-by-Step Example (`lua/plugins/krs/my_helper.lua`):

```lua
-- ============================================================================
-- KRS PLUGIN: My Helper -- Custom local module.
-- ============================================================================

local store = require("krs.core.store")

local M = {}

-- 1. Put all tunable options in M.settings (NEVER M.config or M.opts!)
M.settings = {
    greeting = "Hello from local module!",
    keymap = "<leader>mh",
}

function M.say_hello()
    vim.notify(M.settings.greeting, vim.log.levels.INFO, { title = "My Helper" })
end

function M.setup()
    vim.api.nvim_create_user_command("MyHelperRun", M.say_hello, { desc = "Run My Helper" })
    vim.keymap.set("n", M.settings.keymap, M.say_hello, { desc = "Run My Helper" })
end

M.setup()

-- 2. Return dual spec-module metatable
local plugin_spec = {
    name = "krs_my_helper",
    dir = require("krs.core.lazyspec").for_module(),
    lazy = false,
    config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
```

---

## 🌐 3. How to Add a New Language (LSP, Treesitter, Formatter, Debugger)

To add full IDE support for a new programming language (e.g., Elixir, Zig, Scala, Kotlin, Ruby):

> ⚠️ There is no `servers = {}` table or `ensure_installed` list to edit in `lsp.lua`/`treesitter.lua` — those files only merge what each language declares. See [Adding a Language / LSP](adding-language.md) for the real, current steps; summary below.

1. **Create `lua/krs/langs/<language>/init.lua`**, exporting `M.lsp_config` (lspconfig opts, keyed by server name), `M.mason`/`M.mason_order` (Mason package metadata), and `M.formatters_by_ft` (conform formatter list per filetype). Register it in `lua/krs/langs/init.lua`'s `M.langs` table (and `M.lang_order`) — `lsp.lua` and `formatting.lua` auto-merge from there.

2. **Add bundle metadata to the same `init.lua`**: `M.bundle_name`, `M.requires`, `M.treesitter`. `lua/krs/core/installer.lua`'s `M.language_bundles` builds itself from these — its `mason_pkgs` resolves straight from the `M.mason_order` in Step 1, no separate list to keep in sync. Nothing installs automatically — the user opts in per language via `:LanguageManager`.

3. **Debug Adapter (DAP) (`lua/plugins/editor/dap.lua` & `lua/krs/launch/runtimes.lua`)**:
   Register DAP adapter configuration in `lua/plugins/editor/dap.lua` and launch command in `runtimes.lua`.

---

## 🖥️ 4. How to Customize Terminals & Dock

KrsVim includes a multi-terminal manager supporting 9 independent floating/docked terminal buffers.

- **Toggle Terminal**: `<C-;>`
- **Switch Slots**: `<A-1>` .. `<A-9>`
- **Config file**: `lua/plugins/krs/terminals.lua`
- **Default Shell**: Automatically detects WSL `wsl.exe` on Windows, or `pwsh.exe` / `bash`. You can set your preferred shell in `lua/vim_options.lua`:
  ```lua
  vim.opt.shell = "pwsh"
  ```

---

## 🎨 5. How to Customize Statusline & Themes

### Statusline Themes:
Run `:KrsStatuslineTheme` or select from Command Palette (`<C-Shift-P>`) to switch between:
- `nvchad_pills` (NvChad rounded pills)
- `nvchad_blocks` (NvChad block separators)
- `nagatoro_classic` (Classic Nagatoro statusline)
- `vscode` (Flat VSCode style)
- `minimal` (Compact)

### Editor Themes in `colors/*.lua`:
To create a new theme matching `nagatoro-krs` format, copy `colors/nagatoro-krs.lua` to `colors/mytheme-krs.lua`, change `vim.g.colors_name = "mytheme-krs"`, and edit the palette table `p`:
```lua
local p = {
    bg = "#1a1b26",
    bg_dark = "#16161e",
    fg = "#a9b1d6",
    func = "#7aa2f7",
    keyword = "#bb9af7",
    -- ...
}
```
Run `:KrsThemePicker` or `<leader>th` to switch themes live with interactive preview!

---

## 🛠️ 6. How to Add Build Tasks & Launch Profiles

Per-project build tasks and debugging launch profiles live in `.krsnvim/` inside your project root:

- **`.krsnvim/tasks.json`** (Build & script runner):
  ```json
  {
    "custom_tasks": [
      {
        "name": "Build Production",
        "cmd": "npm run build",
        "is_default": true
      }
    ]
  }
  ```
  Press `<C-S-t>` to open the Task Runner menu.

- **`.krsnvim/launch.json`** (Debugging profiles):
  ```json
  {
    "version": "0.2.0",
    "configurations": [
      {
        "type": "node",
        "request": "launch",
        "name": "Launch App",
        "program": "${workspaceFolder}/src/index.ts"
      }
    ]
  }
  ```
  Press `<C-S-q>` to open Launch Profiles Manager or `<C-S-s>` to start debugging.

---

## ⚙️ 7. Installation, Dependencies & Requirements

### System Requirements:
- **Neovim**: v0.9.0 or higher (v0.10+ recommended).
- **Git**: Required for plugin downloading & Git Center.
- **CLI Utilities**:
  - `ripgrep` (`rg`) for fast searching (`<C-Shift-F>`).
  - `fd` for fast file finding.
  - C Compiler (`gcc`, `clang`, or `zig`) for Treesitter parser compilation.

### Automated Setup Scripts:
- **Windows**: `powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1`
- **Linux / WSL**: `./scripts/setup.sh`

*(If external tools are missing, KrsVim degrades gracefully with clear notifications instead of crashing).*

---

## 🖼️ 8. Neovide GUI Options & Transparency

When running inside [Neovide](https://neovide.dev/):
- **Window Opacity**: Set `vim.g.neovide_opacity = 0.80` in `init.lua` (*Note: `neovide_opacity` replaces the deprecated `neovide_transparency` option*).
- **Hit-Enter Suppression**: `shortmess = "sWICcfotT"` in `lua/vim_options.lua` suppresses hit-enter prompts on startup.
- **Font & Scale**: Font size can be adjusted live via `<C-+>`, `<C-->`, and `<C-0>`, persisted to `font_config.json` in `nvim-data` (`stdpath("data")`).
