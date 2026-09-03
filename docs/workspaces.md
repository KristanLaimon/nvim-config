# 🗂️ Workspaces & Session Manager (`plugins.krs.tools.workspaces`)

[← Back to Wiki Index](index.md)

The **Workspaces Manager** allows saving, loading, restoring, and switching full project session states in Neovim.

---

## ⚡ Highlights

- **Full Session Persistence**: Saves open buffers, tab pages, window splits, and fold states.
- **Terminal Exclusion**: Excludes terminal buffers/windows (`buftype=terminal`) from sessions to prevent stale terminal splits from messing up layout on load.
- **Telescope Selection UI**: `<C-S-w>` opens an interactive Telescope workspace manager with preview, relative timestamps, and slot indexing.
- **Dashboard Return**: `<leader>wm` allows closing the current workspace and returning cleanly to the Main Menu (Alpha Dashboard).

---

## ⌨️ Workspace Shortcuts

- `<C-S-w>`: Open Workspaces UI (Telescope)
- `<leader>wm`: Close session and return to Dashboard
- `<leader>ws`: Quick save current workspace
- `<leader>ww`: Open Workspaces UI
- `<leader>w1..9`: Quick load workspace slot #1..9
