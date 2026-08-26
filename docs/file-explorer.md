# 📁 File Explorers & Move Picker (`plugins.krs.tools.file_explorer`)

[← Back to Wiki Index](index.md)

KRS Neovim includes native floating file explorers for Desktop, WSL, folder picking, and moving files.

---

## ⚡ Features

1. **Desktop Explorer (`<C-S-f>`)**: Pure Lua floating file explorer starting at user Desktop or home directory.
2. **WSL Explorer (`:TelescopeFileBrowserWSL`)**: Native WSL distribution filesystem explorer.
3. **Sneak-Peek Project Modal (`<C-S-y>`)**: Open any folder in an on-top modal window (90% width x 90% height) with fresh LSP initialization and full process tree cleanup on close.
4. **Neo-tree Move File Picker (`m`)**: Pressing `m` on a file in Neo-tree opens the floating file explorer starting at project root (`getcwd()`). Navigate to target folder and press `O` to move file without renaming.
5. **Gitignore vs All Files Search in Neo-tree**:
   - `<C-k>` / `<C-K>` / `<C-/>` / `<C-_>`: Find files **respecting `.gitignore`**.
   - `<C-A-k>` / `<C-S-/>` / `<C-?>`: Find **all files ignoring `.gitignore`**.
6. **Visually Hide Files & Folders (`H` / `gh`)**:
   - Press `H` or `gh` on any file or folder in Neo-tree to mark/unmark it as hidden.
   - Hidden items are visually excluded from the Neo-tree sidebar UI.
   - Toggle visibility of all marked hidden items via Command Palette (`<C-S-p>` -> `NeotreeToggleCustomHiddenVisibility`) or `:NeotreeToggleCustomHiddenVisibility`.
   - When marked items are set to visible, they are rendered using a theme-derived color (`NeoTreeCustomHidden`, linked to active theme's `Comment` group).

---

## ⌨️ Explorer Shortcuts

- `<C-S-f>`: Open Desktop File Explorer
- `<leader>fw`: Open WSL File Explorer
- `<C-S-y>`: Open Sneak-Peek Project Modal (90% width & height)
- `m` (in Neo-tree): Move file/folder via floating picker
- `O` / `o` (in Move Picker): Confirm target folder to move file into
- `r` (in Neo-tree): Rename file/folder via `input_modal`
- `a` (in Neo-tree): Create new file or folder via `input_modal`
- `H` / `gh` (in Neo-tree): Mark selected file/folder as visually hidden
- `<C-k>` / `<C-/>`: Search files respecting `.gitignore`
- `<C-A-k>` / `<C-S-/>`: Search all files ignoring `.gitignore`
