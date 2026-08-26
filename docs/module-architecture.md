# 🧩 Module Architecture

[← Back to Wiki Index](index.md)

How the custom modules in `lua/plugins/krs/` are wired into lazy.nvim, and the two lazy.nvim internals that shape the layout.

> For the bigger picture — the four layers, the startup sequence and where new code belongs — see [Architecture](architecture.md).

---

## 📂 Layout

```
lua/
├── config/            -- editor bootstrap
│   ├── options.lua    -- options, filetypes, shell, PATH
│   ├── lazy.lua       -- plugin manager bootstrap
│   └── keymaps/       -- every global mapping, split by domain
├── krs/               -- shared libraries (NOT plugin specs)
│   ├── core/          -- path, store, project, ui, dock, lazyspec
│   ├── git/           -- cmd, status, diff
│   ├── launch/        -- runtimes
│   ├── lsp/           -- code_action_menu, editorconfig, dap_repl_source
│   └── projects/      -- favorites
└── plugins/
    ├── editor/        -- third-party editor plugins (dap, telescope, neo-tree, …)
    ├── lsp/           -- servers, formatting, treesitter, completion sources
    ├── ui/            -- dashboard, bufferline, themes, devicons
    ├── miscelanea/    -- everything else
    └── krs/           -- custom modules, each its own lazy spec
        └── debuggers/ -- per-language DAP modules (NOT specs)
```

`lua/lazy_init.lua` imports `plugins.krs` as a whole directory, so **every file directly inside `lua/plugins/krs/` must return a lazy spec**.

---

## 🧱 The local-spec pattern

A custom module is a normal Lua module (`local M = {} … return M`) that ends by wrapping itself in a spec:

```lua
local plugin_spec = {
  name = "krs_dap_breakpoints",
  dir = require("krs.core.lazyspec").for_module(),
  lazy = false,
  config = function()
    M.setup()
  end,
}

return setmetatable(plugin_spec, { __index = M })
```

The `setmetatable` is what makes both worlds work at once: lazy.nvim sees a spec table, while `require("plugins.krs.dev.dap_breakpoints").save_breakpoints()` still resolves to the module's own functions through `__index`.

Modules that only need to exist on demand use `keys = { … }` or `cmd = { … }` in the spec instead of `lazy = false`, so their code never loads until the key or command is used.

---

## ⚠️ `lazydir` — why every spec needs its own directory

lazy.nvim indexes **local** specs by their `dir` (`lua/lazy/core/meta.lua`, `self.str_to_meta[fragment.dir]`). Every spec declaring the same directory is merged into **one** plugin: the last `name` wins, and only one `config()` ever runs.

Every module in `lua/plugins/krs/` used to declare the same `dir`, so all but one were silently dropped — no error, no warning, just `setup()` never running. The visible symptom was breakpoints being neither saved nor restored; the cause had nothing to do with breakpoints.

`lua/krs/core/lazyspec.lua` hands each spec its own real, empty directory, named after the calling file:

```lua
function M.for_module()
  local source = debug.getinfo(2, "S").source:sub(2)
  local dir = vim.fn.stdpath("data") .. "/krs-specs/" .. vim.fn.fnamemodify(source, ":t:r")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return dir
end
```

It must be called **from the spec table itself** (`dir = require("krs.core.lazyspec").for_module()`), because it derives the name from the file at stack level 2 — its caller.

Directories live in `stdpath("data")/krs-specs/<module>/` and are empty by design; lazy only needs them to exist and be distinct.

> Symptom to remember: a module's `config()` silently never runs, and `:Lazy` shows fewer plugins than there are files. That's a `dir` collision, not a broken module.

---

## 🙈 Subdirectories are invisible to `import`

lazy's directory import only walks subdirectories that contain an `init.lua` (`lua/lazy/core/util.lua`). That's why `lua/plugins/krs/debuggers/` can hold plain modules that are *not* specs: `lua/plugins/editor/dap.lua` requires each one by name and calls it with the `dap` module.

Same idea, different reason, for `lua/krs/`: it sits outside `lua/plugins/` entirely, so it is never imported as specs — it holds the shared libraries (`krs.core.*`, `krs.git.*`, `krs.launch.runtimes`, …) that modules require directly.

---

## ⚙️ Module settings live in `M.settings`

Each module puts everything tunable in an `M.settings` table at the very top of the file: keys, sizes, file names, timeouts, language lists.

The name matters. `config` and `opts` are **lazy.nvim spec fields**, so a module exposing `M.config` would be shadowed by the spec's own `config` function when read through `require(...)`. `M.settings` never collides.

---

## 🚚 The `config/krs` → `plugins/krs` migration

Custom modules used to live in `lua/krs/` and were required by hand from `lua/*.lua` wrappers (`lua/tasks.lua`, `lua/font.lua`, …). Those wrapper files and the whole `lua/krs/` tree are gone; the modules now live in `lua/plugins/krs/` as self-contained specs.

What that changed:

- **Loading is lazy where it should be.** A module with `keys`/`cmd` no longer costs startup time; before, the wrapper required it eagerly.
- **One require path.** Everything is `require("plugins.krs.<module>")`. Cross-module calls (breakpoints asking tasks for the project root, launch profiles reusing the same resolver) all use that path.
- **Modules are portable.** A single file carries its own spec, commands and keymaps, so dropping it into another config's `lua/plugins/` directory is enough.

If you find a stale `require("config.krs.…")` anywhere, it's a leftover — the module moved.

---

## 🗂️ Per-project state

Modules that persist anything write it under the project root, resolved by `plugins.krs.dev.tasks.get_project_root()` (every other module defers to it so they all agree on what "the project" is):

| File | Module |
|---|---|
| `.krsnvim/tasks.json` | [tasks](tasks.md) |
| `.krsnvim/launch.json` | [launch_profiles](launch-profiles.md) |
| `.krsnvim/breakpoints.json` | [dap_breakpoints](breakpoints.md) |
| `.krsnvim/types.json`, `.krsnvim/types.d.ts` | [type_injector](type-injector.md) |

`.krslocal/` (and `.nvimkrs/` for some modules) are used instead when they already exist. Files are only created when there is something to write.
