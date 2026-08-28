# 🔴 Breakpoints (`plugins.krs.dev.dap_breakpoints`)

[← Back to Wiki Index](index.md)

Breakpoints survive restarts, and can be *disabled* without being deleted — a concept nvim-dap doesn't have.

---

## ⌨️ Shortcuts

| Shortcut / Command | Action |
| :--- | :--- |
| `<A-b>` | Toggle breakpoint on the current line |
| `<A-h>` / `<M-h>` / `<C-S-h>` | Enable ⇄ disable the breakpoint under the cursor, keeping it in place |
| `:DapBreakpointToggleEnabled` | Same, as a command |
| `:DapBreakpointsDisableAll` | Disable every breakpoint (keeps them all) |
| `:DapBreakpointsEnableAll` | Re-enable every disabled breakpoint |
| `:DapBreakpointsRemoveAll` | Delete everything, live and disabled |

Every one of these saves to disk immediately.

### Why `<A-h>` is layered

`<A-h>` and `<C-S-h>` already do something else (cycle buffers, find-file-in-split), and `<C-S-h>` is claimed by a lazy `keys` spec in `telescope.lua`. The enable/disable mapping is therefore installed on `VimEnter` — last writer wins — after capturing the previous mapping. When the cursor line has **no** breakpoint to flip, the previous mapping is replayed, so the key keeps its original behaviour everywhere else.

---

## 🎨 Signs

| Sign | Meaning |
| :--- | :--- |
| 🦊 | Breakpoint |
| 🔶 | Conditional breakpoint |
| 💬 | Logpoint |
| 🐾 | **Disabled** breakpoint (grey) |
| ⭕ | **Rejected** — the adapter refused to bind it |
| 🟡 | Stopped line (with a highlighted row) |

⭕ is the one worth knowing: it means the program never loaded that file, or its source map doesn't line up. See [Debug Adapters](debug-adapters.md).

---

## 🚫 How "disabled" works

nvim-dap has no disabled state — a breakpoint exists or it doesn't. So a disabled breakpoint is **removed from nvim-dap** (the adapter never binds it) and kept here as our own sign, in our own sign group (`krs_dap_disabled`), holding the options it was carrying (`condition`, `hit_condition`, `log_message`).

Signs, not raw line numbers: a disabled breakpoint then drifts with edits exactly like a live one.

Two details that make it correct:

- **Spelling.** `dap.breakpoints.get()` returns the DAP spelling (`hitCondition`, `logMessage`); `dap.breakpoints.set()` expects snake_case (`hit_condition`, `log_message`). The conversion happens on every hand-off.
- **Live sessions are re-synced.** Adding or removing a breakpoint behind nvim-dap's back leaves a running adapter holding the old set, so the buffer's breakpoints are re-sent to every session. The payload uses an explicit `[bufnr] = … or {}` key, because an empty result would otherwise skip the buffer entirely and leave a stale breakpoint bound.

---

## 💾 Persistence

Saved to `.krsnvim/breakpoints.json` (or `.krslocal/breakpoints.json` when that exists), keyed by path relative to the project root:

```json
{
  "breakpoints": {
    "src/server.ts": [
      { "line": 42, "enabled": true },
      { "line": 88, "enabled": false, "condition": "id === 3" },
      { "line": 91, "enabled": true, "log_message": "hit {id}" }
    ]
  }
}
```

`enabled` is missing-means-true, so files written by older versions still load.

**When it saves:** on every toggle, on every enable/disable, on `VimLeavePre`, and on session end (`event_terminated` / `event_exited`) — signs get re-verified during a session and can flip to "rejected", so waiting for exit would persist a stale picture.

**When it restores:** on `BufReadPost` / `BufNewFile`, per buffer, plus a one-shot sweep of already-loaded buffers at setup — the file passed on the command line is read *before* this module's spec runs, so its `BufReadPost` is already gone.

**It restores into one concrete buffer only.** The earlier version looked each saved path up with `bufnr(path, true)`, which on Windows creates a *second*, forward-slash buffer that isn't the one on screen — so the signs landed nowhere — and re-added the same breakpoints on every `BufReadPost`, stacking duplicates. Path comparison is case-insensitive and slash-normalised for the same reason.

> A project with no breakpoints never grows a `.krsnvim/` directory. An existing file *is* rewritten when empty, so "I deleted them all" persists.

---

## 🧪 Test

`tests/dap_breakpoints_check.lua` exercises disable/enable round-trips, the option round-trip, and save/restore. Run it with:

```
nvim --headless -n -S tests/dap_breakpoints_check.lua
```
