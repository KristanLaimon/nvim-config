# 🐙 Interactive Git Control Center (`plugins.krs.git.git_center`)

[← Back to Wiki Index](index.md)

The **Git Control Center** (`<C-S-g>`) is a high-speed, interactive floating Git interface with live VSCode-style diff previews, branch status tracking, and one-key staging/commit/push operations.

---

## ⚡ Highlights

- **Instant Opening (< 30ms)**: Asynchronous status parsing without heavy background Git log scans.
- **Git Submodules & Repository Tabs**: Aesthetic tab bar integrated directly at the top of the control panel with support for Git submodules. Root repository is always on the far-left tab, followed by submodules sorted alphabetically.
- **Persistent Active Tab**: Active submodule tab is saved per-project in `.krsnvim/git-center.json` so re-opening Git Center returns directly to the last active submodule repository.
- **VSCode Live Side-by-Side Diff Preview**: Right-hand preview window and full-screen diff modal (`d`) display side-by-side comparisons (left = before with soft red `-` highlights, right = after with soft green `+` highlights).
- **Branch Management & Checkout (`b`)**: Switch/checkout branches, create new branches, delete branches (with `-D` force delete fallback), and rename branches (`b`).
- **Lazygit-Style Visual Aesthetics**: Vibrant section headers, status badges (`✓` staged green, `M` modified yellow, `?` untracked cyan, `D` deleted red), color-coded keybind badges `[c]`, `[s]`, `[u]`, `[P]`, `[b]`, `[l]`, and capsule repository tab indicators.
- **Commit Log & History Viewer (`l`/`L`) & Full-Page Commit Diff**: Open floating commit history showing `git log --all`. Pressing `<CR>` or `d` on any file listed under "Files Changed" opens the full-screen side-by-side diff modal (`open_diff_modal`) showing that commit file's diff full page!
- **Staging & Unstaging**: Single file staging/unstaging (`s`/`u`) and bulk staging/unstaging (`S`/`U`) scoped to the selected submodule repository.
- **File & Section Restore**: Discard changes for single file (`r`) or entire section (`R`) with confirmation dialogs.
- **Remote Push**: Execute `git push` (`P`) with automatic upstream tracking detection or interactive remote branch selection.
- **Commit & Tag Box**: Multi-line commit title (`c`), description (`m`), and optional tag (`t`) via the `input_modal` component.
- **In-Buffer GitSigns Integration (`gitsigns.nvim`)**: Real-time signcolumn diff indicators (`▎`, ``) and hunk navigation (`]c`/`[c`). See [Keybinds](keybinds.md#git--gitsigns) for full list.

---

## ⌨️ Git Center Shortcuts

| Key | Mode | Action |
| :--- | :---: | :--- |
| `<C-S-g>` / `<Esc>` / `q` | All | Close Git Control Center or active modal |
| `<C-h>` / `<C-H>` | All | Focus Left Panel / Switch to Previous Submodule Tab |
| `<C-l>` / `<C-L>` | All | Focus Right Panel / Switch to Next Submodule Tab |
| `<A-h>` / `<M-h>` | Normal, Visual, Insert, Terminal | Switch to Previous Submodule Tab (Left) |
| `<A-l>` / `<M-l>` | Normal, Visual, Insert, Terminal | Switch to Next Submodule Tab (Right) |
| `b` | Normal | Open Branch Management Modal (Create, Delete, Switch, Rename) |
| `l` / `L` | Normal | Open Commit Log & History Modal (`git log --all` with per-file diffs & jump) |
| `<CR>` (Commit Log) | Normal | Press Enter on file in "Files Changed" to jump directly to its diff |
| `s` | Normal, Visual | Stage selected file or selection |
| `S` | Normal, Visual | Stage all files |
| `u` | Normal, Visual | Unstage selected file or selection |
| `U` | Normal, Visual | Unstage all files |
| `r` | Normal | Discard changes / Restore selected file (with confirmation) |
| `R` | Normal | Discard changes / Restore entire section (with confirmation) |
| `P` | Normal | Push to remote (with confirmation and remote branch selector) |
| `c` | Normal | Edit Commit Title via `input_modal` |
| `m` | Normal | Edit Commit Description via `input_modal` |
| `t` | Normal | Edit Optional Tag via `input_modal` |
| `C` | Normal | Execute Commit & Tag |
| `<Tab>` | Normal | Toggle focus between left control panel and right live preview |
| `<C-S-j>` / `<C-S-k>` | Normal | Scroll right live diff preview window |
| `d` | Normal | Open selected file in Side-by-Side Diff Modal UI |
| `<S-CR>` / `<S-Enter>` | Normal, Visual, Insert | Open file under cursor in bufferline tab (switches to existing tab if open) |
| `<F5>` / `<C-r>` | Normal | Refresh Git status |

---

## 🔧 Customizing

Everything tunable lives in `M.settings` at the top of
[`lua/plugins/krs/git_center.lua`](../lua/plugins/krs/git_center.lua)
— sizes, filenames, delays. To make the panel take up (almost) the whole
screen instead of the default 92%×85%:

```lua
-- lua/plugins/krs/git_center.lua
M.settings = {
    width_ratio = 0.98,   -- was 0.92
    height_ratio = 0.95,  -- was 0.85
    left_ratio = 0.30,    -- unchanged: file list stays 30% of that width
    -- ...
}
```

Save, restart (or `:Lazy reload krs_git_center`), reopen with `<C-S-g>`. Same
pattern for `modal_width_ratio`/`modal_height_ratio` (the full-screen diff
modal opened with `d`) or `editor_width_ratio`/`editor_height` (the commit
message box opened with `c`/`m`/`t`).

To change a keybind (e.g. `P` for push feels wrong), search this same file for
the key's *current* mapping — Git Center's keys are wired inside its own
buffer-local `map_keys` function rather than a flat `M.settings.keys` table
(too many context-dependent bindings for that to stay simple), so `grep -n
'"P"' lua/plugins/krs/git_center.lua` finds the exact `vim.keymap.set` call to
edit directly.

