# 🚀 Launch Profiles (`plugins.krs.dev.launch_profiles`)

[← Back to Wiki Index](index.md)

Per-project entry points — "what does F5 actually run here?" — stored in `.krsnvim/launch.json`. A profile carries a runtime, an entry point, args, env, pre-launch tasks, and a mode: run it in a terminal slot, or debug it under DAP.

This is the layer *above* [Debug Adapters](debug-adapters.md): it builds a DAP configuration for you instead of making you write one.

---

## ⌨️ Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `<C-S-s>` | **Smart launch.** Runs the default profile — or stops the session if one is already running |
| `<C-S-q>` | Open the profile manager (card picker) |
| `<F5>` | Plain DAP continue — resume from a breakpoint, or pick a raw debug configuration |

### Smart launch (`<C-S-s>`) decision tree

```
session already running?      → terminate it (same key stops what it started)
no profiles in this project?  → open the creation form, then run what you just made
a profile marked default?     → run it
otherwise                     → open the profile manager and let you choose
```

That is why `<C-S-s>` is both start and stop, and why resuming from a breakpoint stays on `<F5>` — those are different questions.

---

## 🗂️ The manager (`<C-S-q>`)

A Telescope card picker: default profile pinned first (⭐), each row showing mode, name, `runtime:entry_point`, args and pre-launch tasks, with a full preview pane.

| Key | Mode | Action |
| :--- | :--- | :--- |
| `<Enter>` | n, i | Run the profile |
| `d` / `<C-x>` | n | Delete the profile |
| `r` | n | Rename profile via input modal |
| `e` / `<C-e>` | n | Edit in the form editor |
| `f` / `<C-d>` | n | Toggle favorite ⭐ ("primary default") |
| `a` / `<C-n>` | n | Create a new profile |

### The form editor

One floating screen, eight fields, no wizard steps:

| # | Field | Notes |
| :-- | :--- | :--- |
| 1 | Profile Name | Free text |
| 2 | Runtime | `bun` · `node` · `deno` · `python` · `go` · `php` · `dotnet` · `custom` |
| 3 | Entry Point File | Relative to the project root |
| 4 | Command Args | Space-separated |
| 5 | Pre-launch Tasks | Comma-separated; run in order, abort the launch on any non-zero exit |
| 6 | Execution Mode | 🖥️ Terminal task slot, or 🐞 DAP debugger |
| 7 | Primary Default | Only one profile can hold it; setting it clears the others |
| 8 | Auto Build | `dotnet` only — prepends `dotnet build <target>` to the pre-launch tasks |

Navigation: `1`-`8` jump to a field, `j`/`k`/`<Tab>` move, `<Enter>`/`<Space>` edit or cycle, `S` saves, `<Esc>`/`q` cancels.

---

## 📄 `launch.json`

Written to `.krsnvim/launch.json` (`.krslocal/` and `.nvimkrs/` are honoured when they already exist):

```json
{
  "profiles": [
    {
      "id": "profile-1739212800",
      "name": "API (debug)",
      "runtime": "bun",
      "entry_point": "src/index.ts",
      "args": ["--port", "4000"],
      "env": { "NODE_ENV": "development" },
      "pre_launch_tasks": ["bun install", "bun run build"],
      "mode": "debug",
      "is_default": true,
      "auto_build": false
    }
  ]
}
```

This is **not** VSCode's `.vscode/launch.json` — that file is still read by nvim-dap separately and its configurations show up in the `<F5>` picker. See [Debug Adapters](debug-adapters.md#33-launchjson-and-type_to_filetypes).

### 🧠 IntelliSense inside `launch.json`

`plugins.krs.dev.launch_cmp` registers a blink.cmp source that only fires in files named `launch.json`:

- `pre_launch_tasks` → tasks discovered in the project (npm scripts, Makefile targets, go/cargo commands, `.krsnvim/tasks.json` entries)
- `runtime` → the eight runtimes, with a description of each
- `mode` → `run` (terminal task slot) or `debug` (DAP)

So hand-editing the file is as guided as the form.

---

## ▶️ Run mode

The profile becomes a shell command handed to the [task runner](tasks.md) (`run_custom_command`), with the profile's `env`, in a background task slot:

| Runtime | Command |
| :--- | :--- |
| `bun` | `bun <entry> <args>` |
| `node` | `node <entry>` — or `npx tsx <entry>` for `.ts`/`.tsx` |
| `deno` | `deno run -A <entry>` |
| `python` | `python <entry>` |
| `go` | `go run <entry>` |
| `php` | `php <entry>` |
| `dotnet` | `dotnet run --project <entry>` |
| `custom` | the entry point, verbatim |

---

## 🐞 Debug mode

`build_dap_config()` maps the profile onto a real DAP configuration. Adapter names match what `mason-nvim-dap` / `nvim-dap-go` register — `pwa-node`, `bun`, `go`, `python`, `php`, `coreclr`.

| Runtime | Adapter | Notes |
| :--- | :--- | :--- |
| `bun` | `bun` | Bun's own WebKit-inspector adapter. It spawns `bun` itself, so no `runtimeExecutable`, and it runs `.ts` with no loader |
| `node` / `deno` / anything else JS | `pwa-node` (js-debug) | `console = "integratedTerminal"` keeps the child in an nvim terminal instead of popping external `cmd.exe` windows for `.cmd` shims on Windows; `skipFiles` keeps js-debug out of node internals and the tsx loader |
| `deno` | `pwa-node` | `deno run --inspect-wait --allow-all` + `attachSimplePort = 9229` |
| `python` | `debugpy` | `console = "integratedTerminal"` |
| `go` | `go` (delve) | `mode = "debug"` |
| `php` | `php` (Xdebug) | Xdebug is a *listener*: nvim waits on port 9003 and the PHP process connects back. `pathMappings` maps `/var/www/html` to the project root |
| `dotnet` | `coreclr` (netcoredbg) | Launches the built **assembly**, not the project — see below |

If the adapter isn't installed, the launch aborts with the exact fix: `:KrsBunDapInstall` for Bun, `:Mason` (or a restart, letting `mason-nvim-dap` fetch it) for everything else.

### TypeScript under Node

`ts_runtime()` picks how a `.ts`/`.tsx` entry point is executed, in this order — and the DAP side uses the same resolver, so run mode and debug mode never disagree:

1. **Project has `node_modules/tsx`** → `node --import tsx`. Handles `tsconfig` paths, enums and decorators.
2. **Node ≥ 22.18 / 23.6** → plain `node`. Native type stripping. (`node -v` is memoised; it costs ~50ms.)
3. **Otherwise** → `npx tsx`.

### .NET

netcoredbg launches a built DLL, so the entry point can be a `.dll`, a `.csproj` or a project directory. For the latter two, `find_dotnet_dll()` globs `bin/**/<Name>.dll` and takes the **newest** one. No DLL on disk → the error tells you to enable Auto Build or point the entry point at `bin/Debug/<tfm>/App.dll`.

With **Auto Build** on, `dotnet build <target>` is prepended to the pre-launch tasks rather than being a second, separate build pipeline — so a failed build aborts the launch like any other failed pre-task.

---

## 🌐 Dev Server Bridge (`plugins.krs.dev.dev_server`)

Browser debug configurations need a URL that is *already serving*. This module starts the project's dev server (or reuses one that is up) and hands back its URL.

It is meant to be used as a **function value inside a DAP configuration**. nvim-dap resolves those inside a coroutine, so yielding here waits for the server without freezing the editor, and the browser only launches once the port actually answers:

```lua
url = function()
  return require("plugins.krs.dev.dev_server").url()
end
```

**Finding the server.** It TCP-connects to a candidate port list — a connect is the only check that proves something is *accepting*; parsing `netstat` reports a bound socket and races the server's first real listen. Defaults: `5173` (vite/sveltekit), `4321` (astro), `3000` (next/nuxt/remix), `4200` (angular), `5174`, `8080`, `1420` (tauri), `3001`. Override per project with `vim.g.krs_dev_ports = { 1234 }`.

**Starting one.** The lockfile picks the package manager (`bun.lock`/`bun.lockb` → `bun run`, `pnpm-lock.yaml` → `pnpm`, `yarn.lock` → `yarn`, else `npm run`), and `package.json` picks the script (`dev`, then `start`, then `serve`). It runs in a task slot, and the module polls every 500ms up to a 60s deadline.

| Function | Behaviour |
| :--- | :--- |
| `url(timeout_ms)` | Reuse a running server, or start one and wait. `nil` on timeout — which aborts the debug session instead of launching a browser at a dead URL |
| `existing_url()` | Never starts anything. For attach configs |
| `find_running_port()` | The raw probe |
| `dev_command(root)` | The command it would run |

> Every entry point must be called from inside a coroutine — it asserts otherwise.
