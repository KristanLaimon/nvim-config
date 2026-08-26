# 💉 Type Injector (`plugins.krs.tools.type_injector`)

[← Back to Wiki Index](index.md)

Turns type definitions on and off **per project**, for Lua and for TypeScript/JavaScript, from one picker — without editing `.luarc.json` or `tsconfig.json` by hand, and without dumping every schema you own into every project.

---

## ⌨️ Commands

| Command | Action |
| :--- | :--- |
| `:KrsTypes` / `:TypeInjector` | Open the picker |
| `:KrsGitignoreGenerated` | Add the generated `.krsnvim/types.d.ts` to `.gitignore` |

Inside the picker: `<Enter>` / `<Tab>` toggles a schema, `<C-n>` installs an `@types` package from NPM, `<C-d>` deletes one. Active schemas are ✅, sorted to the top, with their version in the label.

The language is inferred from the current filetype; from any other buffer it asks Lua vs TypeScript/JavaScript first.

---

## 📁 Where schemas come from

```
schemas-langs/
├── lua/
│   ├── vim_nvim/       -- Neovim API
│   ├── neovide/        -- Neovide GUI globals (vim.g)
│   ├── love/           -- LÖVE
│   └── koreader/
└── typescript_javascript/
    ├── browser/        -- hand-written DOM/window stub
    ├── node/           -- real @types/node, fetched from the npm registry
    └── bun/            -- real bun-types, self-contained (own node_modules/@types/node copy)
```

Each directory is a schema. A TS schema is either a flat folder of `.d.ts` files, or (when a package needs it — see the by-hand guide) holds a `node_modules/@types/…` tree, which is where the version shown in the picker comes from.

Adding one is just adding a directory — `scan_available_schemas()` reads the filesystem, there is no registry to update. See [Managing TypeScript Type Schemas](how-to-manage-typescript-type-schemas.md) for how `node/` and `bun/` were populated without running `npm install`.

---

## 🔌 How each language is wired

**Lua (`lua_ls`).** Active schema directories are appended to `Lua.workspace.library`, and the running client is notified with `workspace/didChangeConfiguration` — so toggling a schema takes effect immediately, no restart.

**TypeScript (`vtsls`).** All active schemas are collapsed into a *single* generated file, `.krsnvim/types.d.ts`, holding one `/// <reference path="…" />` per schema. The project's TS config is patched to include it. One generated file instead of N `typeRoots` entries keeps `tsconfig.json` readable and makes "what types are on?" a single file to look at.

Automatic type acquisition is disabled on `vtsls` (see [Languages](languages.md)), so what you toggle here is exactly what the server sees. The client name notified after a change is resolved from `lua/krs/langs/typescript/init.lua`'s `M.lsp_server`, not hardcoded — it stays correct if that server is ever swapped.

---

## 💾 State

`.krsnvim/types.json` records which schemas are active, per language:

```json
{
  "lua": ["vim_nvim"],
  "typescript_javascript": ["browser"]
}
```

Commit that file — it's the project's decision. The *generated* `.krsnvim/types.d.ts` is machine output; `:KrsGitignoreGenerated` adds it to `.gitignore` for you (and is a no-op if it's already listed).

---

## 📦 Installing `@types` from NPM

`<C-n>` in the picker takes a package name, normalises it to `@types/<name>` when needed, and installs it into the TypeScript schemas directory. It then shows up as a normal togglable schema with its version — so a project that needs `@types/node` gets it once, and every other project stays clean.
