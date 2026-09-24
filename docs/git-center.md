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
- **GitKraken-Style Commit Graph Viewer (`g` / `:GitGraph`)**: Interactive dual-pane commit graph with 2 modes (🌿 Current Branch only vs 🌐 `--all` branches, toggleable via `a`). Renders GitKraken visual aesthetics with 8-color branch lanes, circular commit nodes (`●`), pill badges (`[🌿 branch]`, `[☁️ remote]`, `[🏷️ tag]`), short SHA, and relative dates. Supports on-the-fly lazy loading / infinite scroll when navigating down using Vim half-page motions (`d`, `u`, `<C-d>`, `<C-u>`, `j`, `k`, `G`, `gg`). Right preview pane displays full commit metadata, author details, changed files list with status badges, and interactive side-by-side diffs.
- **Staging & Unstaging**: Single file staging/unstaging (`s`/`u`) and bulk staging/unstaging (`S`/`U`) scoped to the selected submodule repository.
- **File & Section Restore**: Discard changes for single file (`r`) or entire section (`R`) with confirmation dialogs.
- **Remote Push**: Execute `git push` (`P`) with automatic upstream tracking detection or interactive remote branch selection.
- **Commit & Tag Box**: Multi-line commit title (`c`), description (`m`), and optional tag (`t`) via the `input_modal` component.
- **VSCode 3-Way Merge Conflict Resolver (`M` / `:GitConflictResolve` / `<leader>gm`)**: Opens a full-screen tiled workspace (like the DAP debugger) with 4 synchronized panels: Left Sidebar (conflicted files with live decreasing counts `(2)` -> `(1)` -> `(0)` and locked to Neo-tree width), Top-Left Current/Ours (highlighted in Green), Top-Right Incoming/Theirs (highlighted in Blue), Bottom editable Result (clean merged code with unlimited undo). Panel jumps: `<C-h>` (Sidebar), `<C-k>` (Current), `<C-l>` (Incoming), `<C-j>` (Result), `<Tab>`/`<S-Tab>`. Conflict actions: Accept Ours (`<C-1>`/`<C-o>`), Accept Theirs (`<C-2>`/`<C-t>`), Accept Both (`<C-3>`/`<C-b>`), Undo resolution (`<C-z>`/`u` - repeatable back to initial state), navigate (`<C-n>`/`<C-p>`), and stage (`<C-s>`).
- **RAM Screen Caching (`<C-S-g>`)**: Closing Git Center while on any subscreen (such as the Commit History Log or Branch Modal) using `<C-S-g>` caches the view and cursor position in RAM. Re-opening with `<C-S-g>` restores you directly to the exact screen where you left off. Closing with `q` or `<Esc>` returns to the main control panel.
- **Git Diff Mode (Same Branch) (`V` / `:GitDiffSameBranch`)**: In-buffer diff comparison highlighting added lines in green and displaying deleted lines via red virtual lines (`-`). By default, compares live working tree changes (both staged & unstaged) against the `HEAD` commit. Supports configurable diff ranges via `c` (`HEAD~N` + working tree, committed history only `HEAD~N..HEAD`, or between 2 chosen commits). Features a docked right sidebar file list with status markers. Selecting a file (`<CR>`, `<Space>`, or click) loads the diff while keeping focus in the sidebar. Navigate between diff modifications directly from the sidebar using `J`/`K`, `n`/`p`, or `]c`/`[c` quietly without toast notifications; the diff sidebar instead displays `<1/# Changes in file>` and `<1/# Changes in total>`, alongside real-time Total diffs (`+`/`-`) and file Subtotal diffs (`+`/`-`) in the bottom diff bar. Return focus to the code editor using `h` or `<Esc>`.
- **Git Diff Mode (Between 2 Branches) (`v` / `:GitDiffBetweenBranches`)**: Dual synchronized split view comparing the same file across two branches or refs (selected via dual Base & Target floating menus with custom branch/ref input prompt). Supports synchronized scrolling (`scrollbind`/`cursorbind`), side-by-side color highlights, and jumping between modifications with `]c`/`[c` or `]d`/`[d`.
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
| `M` | Normal | Open 3-Way Merge Conflict Resolver |
| `<leader>gm` | Normal | Open 3-Way Merge Conflict Resolver from anywhere |
| `b` | Normal | Open Branch Management Modal (Create, Delete, Switch, Rename, Dry-Run) |
| `l` / `L` | Normal | Open GitKraken Commit Graph Viewer (`:GitGraph`, 2 modes: Current / `--all`, on-the-fly fetch) |
| `t` | Normal | 🧪 Dry-Run Merge simulation (predict conflicts between branches without touching CWD) |
| `T` | Normal | 🧪 Dry-Run Rebase simulation (predict conflicts between branches without touching CWD) |
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
| `v` | Normal | Open Git Diff Mode Manager menu (Same branch, 2 branches, commits) |
| `V` | Normal | Toggle Git Diff Mode (Same branch: Live working tree vs HEAD) |
| `<CR>` / `<Space>` / `<LeftMouse>` (Diff Sidebar) | Normal | Select and open file in code window while keeping focus in sidebar |
| `J` / `K` (Diff Sidebar) | Normal | Jump to next / previous diff modification in current viewing file |
| `n` / `p` / `N` (Diff Sidebar) | Normal | Jump to next / previous diff modification in current viewing file |
| `]c` / `[c` or `]d` / `[d` | Normal | Jump to next / previous modification in active diff buffer |
| `c` (Diff Sidebar) | Normal | Configure diff scope / commits behind range |
| `e` / `E` / `z` (Diff Sidebar) | Normal | Export currently diffed files with current code into a `.zip` archive |
| `i` / `I` (Diff Sidebar) | Normal | Import & 3-way merge diff files from a compatible KRS `.zip` archive (with automatic conflict markers `<<<<<<<` / `>>>>>>>` when conflicts occur) |
| `h` / `<Esc>` (Diff Sidebar) | Normal | Return focus to code editor |
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

---

## 🔍 VS Code-Style Git Blame (`git-blame.nvim`)

KrsVim integrates `f-person/git-blame.nvim` configured to emulate the VS Code GitLens inline blame virtual text.

### Features:
- **Inline Virtual Text**: Displays `  <author>, <date> • <summary>` at the end of the active cursor line.
- **Relative Dates**: Shows relative time format (e.g., `2 hours ago`, `3 days ago`) matching VS Code.
- **Smart Highlighting**: Italicized, subtle text dynamically linked to the active colorscheme's `Comment` highlight.
- **Filetype Gating**: Automatically suppressed in explorer, picker, help, and popup buffers (`neo-tree`, `TelescopePrompt`, `alpha`, `dashboard`, `help`, `gitcommit`, `lazy`, `mason`).

### Commands & Palette Actions:
- `:GitBlameToggle` — Toggle inline virtual text on / off.
- `:GitBlameOpenCommitURL` — Open commit in web browser.
- `:GitBlameCopySHA` — Copy commit SHA hash to clipboard.
- `:GitBlameCopyCommitURL` — Copy web commit URL to clipboard.
- `:GitBlameOpenFileURL` — Open file at commit in web browser.
- All actions are discoverable via Command Palette (`<C-S-p>`).

