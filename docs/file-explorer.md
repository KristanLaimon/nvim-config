# 📁 File Explorers & Move Picker (`plugins.krs.tools.file_explorer`)

[← Back to Wiki Index](index.md)

KRS Neovim includes native floating file explorers for Desktop, WSL, folder picking, and moving files.

---

## ⚡ Features

1. **Desktop Explorer (`<C-S-f>`)**: Pure Lua floating file explorer starting at user Desktop or home directory.
2. **WSL Explorer (`:TelescopeFileBrowserWSL`)**: Native WSL distribution filesystem explorer.
3. **Sneak-Peek Project Modal (`<C-S-y>`)**: Open any folder in an on-top modal window (90% width x 90% height) with fresh LSP initialization and full process tree cleanup on close.
4. **Neo-tree Move ("En la mano" Workflow) (`m`)**:
   - Press `m` on any file or folder to pick it up ("En la mano"). A persistent toast notification appears showing the held item.
   - Navigate to the destination directory (or any file inside it) in Neo-tree and press `m` again to move it.
   - If `m` is pressed in the same directory or on the same item, the move is cancelled and a warning notifies you that it was already in the same place.
   - Press `<Esc>` at any time while holding an item to cancel the move.
5. **Gitignore vs All Files Search in Neo-tree**:
   - `<C-k>` / `<C-K>` / `<C-/>` / `<C-_>`: Find files **respecting `.gitignore`**.
   - `<C-A-k>` / `<C-S-/>` / `<C-?>`: Find **all files ignoring `.gitignore`**.
6. **Visually Hide Files & Folders (`H` / `gh`)**:
   - Press `H` or `gh` on any file or folder in Neo-tree to mark/unmark it as hidden.
   - Hidden items are visually excluded from the Neo-tree sidebar UI.
   - Toggle visibility of all marked hidden items via Command Palette (`<C-S-p>` -> `NeotreeToggleCustomHiddenVisibility`) or `:NeotreeToggleCustomHiddenVisibility`.
   - When marked items are set to visible, they are rendered using a theme-derived color (`NeoTreeCustomHidden`, linked to active theme's `Comment` group).
7. **Terminal from Neo-tree (`<C-;>`)**: Opens or toggles the selected multi-terminal slot. This intentionally replaces Neo-tree's default `clear_selection` action for that key.

---

## ⌨️ Explorer Shortcuts

- `<C-S-f>`: Open Desktop File Explorer
- `<leader>fw`: Open WSL File Explorer
- `<C-S-y>`: Open Sneak-Peek Project Modal (90% width & height)
- `m` (in Neo-tree): Pick up file/folder ("En la mano") / Move into target directory (or cancel if same place)
- `<Esc>` (in Neo-tree): Cancel pending move operation if an item is held
- `r` (in Neo-tree): Rename file/folder via `input_modal`
- `a` (in Neo-tree): Create new file or folder via `input_modal`
- `H` / `gh` (in Neo-tree): Mark selected file/folder as visually hidden
- `<C-;>` (in Neo-tree): Toggle the selected terminal panel
- `<C-k>` / `<C-/>`: Search files respecting `.gitignore`
- `<C-A-k>` / `<C-S-/>`: Search all files ignoring `.gitignore`
