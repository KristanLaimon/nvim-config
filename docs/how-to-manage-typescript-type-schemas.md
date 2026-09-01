# 🧬 How to Create / Update / Delete / Register a TypeScript/JS Type Schema

[← Back to Wiki Index](index.md)

This is the by-hand companion to [Type Injector](type-injector.md), for TypeScript/JavaScript. It covers the same ground as `<C-n>` (install from NPM) in the picker, plus the case the picker doesn't cover: dropping in real `.d.ts` files **without** the `npm` CLI, `node_modules`, or a `package.json` install step at all — just the type files themselves, fetched straight from the npm registry's tarball.

A **schema** is a directory of `.d.ts` files under `schemas-langs/typescript_javascript/<name>/`. There is no registry to update — `scan_available_schemas()` reads the filesystem, so a directory that exists *is* an available schema. This repo ships two worked examples: `node/` (`@types/node`) and `bun/` (`bun-types`), both fetched this way.

---

## 🏗️ Create a new schema

### Step 1: Pick a name and a location

```
schemas-langs/typescript_javascript/<schema_name>/
```

Two roots are searched (`M.get_schema_roots` in `lua/plugins/krs/type_injector.lua`):

1. `stdpath("data")/schemas-langs/typescript_javascript/<schema_name>/` — where the picker's `<C-n>` NPM install lands; fine for personal, machine-local schemas.
2. `stdpath("config")/schemas-langs/typescript_javascript/<schema_name>/` (this repo's `schemas-langs/typescript_javascript/`) — versioned with the rest of KrsVim; use this for anything you want to keep and share across machines.

### Step 2: Get real `.d.ts` files, no `npm install` required

`resolve_schema_dir()` / `active_schema_entries()` (`lua/plugins/krs/type_injector.lua`) accept **two shapes** for a schema directory:

- **Flat** — an `index.d.ts` (or any `*.d.ts` at the top level) directly in `schemas-langs/typescript_javascript/<name>/`. Use this for most packages.
- **`node_modules/@types/<pkg>/`** — mirrors what `npm install` would produce. Only needed when a package's own `.d.ts` uses `/// <reference types="X" />` (an *ambient* reference, resolved through Node's module resolution) rather than `/// <reference path="./x.d.ts" />` (a plain relative file reference, which works with the flat shape — no special layout needed).

Every real npm package that ships types is just a tarball on the registry — `npm` is only a convenience wrapper around fetching that tarball and unpacking it. You can do the unpack step yourself with `curl` + `tar`, no npm/Node package manager involved:

```bash
# 1. Look up the tarball URL for the latest version (or pin one: /@types/node/22.10.0)
curl -s https://registry.npmjs.org/@types/node/latest \
  | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const j=JSON.parse(d);console.log(j.version, j.dist.tarball)})"
# -> 26.2.0 https://registry.npmjs.org/@types/node/-/node-26.2.0.tgz

# 2. Download and extract it somewhere scratch
mkdir /tmp/fetch && cd /tmp/fetch
curl -sL https://registry.npmjs.org/@types/node/-/node-26.2.0.tgz -o pkg.tgz
tar xzf pkg.tgz            # unpacks into ./package/ or ./<name>/, depending on the package

# 3. Copy ONLY the type files (and package.json, for the version) into the schema
CFG="$HOME/AppData/Local/nvim/schemas-langs/typescript_javascript/node"   # adjust for your platform
mkdir -p "$CFG"
cd /tmp/fetch/package   # or whatever the extracted top folder is named
find . -type f \( -name "*.d.ts" -o -name "package.json" \) -exec cp --parents {} "$CFG/" \;
```

No `curl`/`node` in your `PATH`? `unpkg.com/@scope/pkg@version/file.d.ts` serves individual files over plain HTTPS too — fetch just the files you need by hand if you'd rather not deal with tarballs.

> ⚠️ **`npx <something>` still shells out to npm's registry/installer.** "npm-free" here means the *editing session* never runs `npm install`/`npx` against your project — the registry tarball fetch above is a one-time, throwaway step to populate the schema folder, same as downloading a `.zip` from GitHub. Once the `.d.ts` files are on disk, nothing about using the schema touches npm again.

### Step 3: Handle `/// <reference types="X" />` (ambient references)

Check the package's `index.d.ts` for lines like:

```ts
/// <reference types="node" />
```

This is different from `/// <reference path="./globals.d.ts" />` — a `path` reference is just a relative file link and works with the flat layout from Step 2 as-is. A `types` reference asks TypeScript's *module resolution* to find `node_modules/@types/node/` (or a package named `node` in `node_modules/`) by walking up from the referencing file.

If you see one, self-contain the dependency inside your schema so it works standalone, without requiring the other schema to also be active:

```
schemas-langs/typescript_javascript/bun/
├── index.d.ts              -- has `/// <reference types="node" />`
├── globals.d.ts, bun.d.ts, sqlite.d.ts, ...
└── node_modules/
    └── @types/
        └── node/            -- full @types/node copy, fetched the same way as Step 2
            ├── index.d.ts
            └── ...
```

From `bun/index.d.ts`, TypeScript walks up looking for a `node_modules/@types/` ancestor — `bun/node_modules/@types/` is the first one it finds, containing `node`, so the reference resolves. This is exactly what `bun-types`' own `package.json` (`"dependencies": { "@types/node": "*" }`) says npm would install anyway — you're just doing the same nesting by hand.

**Verify it actually resolves** before committing (only needs `npx typescript` once, doesn't touch your project):

```bash
cd /tmp/verify
cat > t.ts <<'EOF'
import fs from "fs";
const f: Bun.BunFile = Bun.file("x");
EOF
cat > tsconfig.json <<'EOF'
{ "compilerOptions": { "noEmit": true, "skipLibCheck": true, "moduleResolution": "bundler" }, "include": ["*.ts"] }
EOF
cat > types.d.ts <<EOF
/// <reference path="/absolute/path/to/schemas-langs/typescript_javascript/node/index.d.ts" />
/// <reference path="/absolute/path/to/schemas-langs/typescript_javascript/bun/index.d.ts" />
EOF
npx -y -p typescript tsc -p tsconfig.json   # no errors = the schema resolves cleanly
```

### Step 4: Version it

The extracted `package.json` already has a real `"version"` field — keep it (don't replace it with a hand-written stub like the Lua guide's convention). `M.get_schema_version()` reads it from `schema_dir/package.json` first, falling back to `node_modules/@types/<name>/package.json` (the npm-install-flow shape) — either location works, so it doesn't matter that a hand-fetched schema's `package.json` is the real upstream one instead of a `krs-schema-*` placeholder.

---

## ✅ Register (activate) a schema for a project

**Through the picker (recommended):** open the target project in Neovim, run `:KrsTypes` (or `:TypeInjector`) from a `.ts`/`.js`/`.tsx`/`.jsx` buffer, toggle the schema on. This writes `.krsnvim/types.json`, regenerates `.krsnvim/types.d.ts` (one `/// <reference path>` per active schema), patches `tsconfig.json`'s `include` if needed, and notifies the running `tsc` client — no restart.

**By hand:** create/edit `.krsnvim/types.json` at the project root:

```json
{
  "typescript_javascript": ["node", "bun"]
}
```

Then either run `:KrsTypes` once (toggle a schema off/on, or just open/close the picker — `apply_lsp_settings()` runs on open) to regenerate `.krsnvim/types.d.ts` and patch `tsconfig.json`, or do both yourself:

```ts
// .krsnvim/types.d.ts -- auto-generated shape, one line per active schema
/// <reference path="/abs/path/to/schemas-langs/typescript_javascript/node/index.d.ts" />
/// <reference path="/abs/path/to/schemas-langs/typescript_javascript/bun/index.d.ts" />
```

```jsonc
// tsconfig.json -- must include the generated file, or the TS language server ignores it entirely
{ "include": ["**/*", ".krsnvim/**/*.d.ts"] }
```

Multiple schemas can be active at once — list them all in `types.json`; they combine into the one generated file.

---

## ✏️ Update a schema

Re-run Step 2's fetch against a newer version and overwrite the files in place — there's no diffing needed, just replace the whole folder's contents (delete-then-copy, so removed upstream files don't linger):

```bash
rm -rf "$CFG"/*
# ...repeat Step 2's curl/tar/cp against the new version...
```

Any project with the schema active picks it up the next time `tsc` re-reads the referenced files (usually automatic on save; `:LspRestart` if not).

---

## 🗑️ Delete a schema

**Through the picker:** select the schema, `<C-d>` — confirms, deletes the schema directory, deactivates it from the currently-open project's `.krsnvim/types.json` (other projects' `types.json` entries become dangling references — harmless, `scan_available_schemas()` just stops listing the name).

**By hand:** delete `schemas-langs/typescript_javascript/<schema_name>/` (check both roots with `M.get_schema_roots("typescript_javascript")` if unsure which one has it), remove the name from `.krsnvim/types.json` in any project that had it active, and re-run `:KrsTypes` (or `:LspRestart`) there to regenerate `.krsnvim/types.d.ts` without it.

---

## 🔍 Quick reference

| Action | Picker | By hand |
| :--- | :--- | :--- |
| Create (via npm registry) | `<C-n>` → package name → installs through `npm install` | `curl` the registry tarball URL, `tar xzf`, copy `*.d.ts` + `package.json` into `schemas-langs/typescript_javascript/<name>/` |
| Handle a `types="X"` reference | Automatic — npm installs the dependency into `node_modules` | Nest a copy under `<name>/node_modules/@types/X/` yourself (Step 3) |
| Register for a project | `<Enter>`/`<Tab>`/`<Space>` | Add name to `.krsnvim/types.json` → `"typescript_javascript": [...]`, then `:KrsTypes` once to regen `.krsnvim/types.d.ts` |
| Update | — | Delete + re-fetch the folder's contents |
| Deregister | `<Enter>`/`<Tab>`/`<Space>` (toggle off) | Remove name from `.krsnvim/types.json`, re-run `:KrsTypes`/`:LspRestart` |
| Delete | `<C-d>` | `rm -rf schemas-langs/typescript_javascript/<name>` + remove from any project's `types.json` |

See [Type Injector](type-injector.md) for how the wiring works end to end (generated reference file, `tsconfig.json` patching, LSP notification), and [Managing Lua Type Schemas](how-to-manage-lua-type-schemas.md) for the Lua/`lua_ls` side.
