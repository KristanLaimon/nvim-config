# 🙈 Neo-tree Custom Hidden Files & Folders (`plugins.krs.neotree_hidden`)

[← Back to Wiki Index](index.md)

KrsVim provides a native custom file and folder hiding system for **Neo-tree**. It allows you to visually exclude specific files, folders, or nested subtrees from the sidebar UI without modifying `.gitignore` or filesystem permissions.

---

## ⚡ Key Features

1. **Sidebar-Only Node Hiding (`H` / `gh`)**:
   - Press **`H`** or **`gh`** while focused on any file or folder in Neo-tree to mark or unmark it as hidden.
   - Hiding a directory automatically hides all of its child files and nested subdirectories.

2. **Visual Hide vs. Show Modes**:
   - **Hide Mode (Default)**: Items marked as hidden are completely removed from the Neo-tree sidebar UI.
   - **Show Mode**: Items marked as hidden are displayed in the Neo-tree sidebar UI, but styled using a theme-derived highlight group (`NeoTreeCustomHidden`).

3. **Theme-Aware Highlight Colors**:
   - Items shown in "Show Mode" automatically adapt to your active Neovim colorscheme (linked to the theme's `Comment` group).
   - Dynamically updates when switching themes via `:KrsThemePicker` or `ColorScheme` events.

4. **Command Palette Integration**:
   - Easily toggle visibility of marked items or clear all hidden marks via `<C-S-p>`.

5. **Per-Project `.krsnvim/` Persistence**:
   - Marked hidden paths (stored as portable project-relative paths) and visibility settings are saved per-project in `.krsnvim/neotree_hidden.json`.
   - Automatically switches settings when changing directories or project workspaces.

---

## ⌨️ Shortcuts & Commands

### Neo-tree Sidebar Mappings
Available only when the cursor is inside the Neo-tree window:

| Shortcut | Command | Description |
| :--- | :--- | :--- |
| `H` | `toggle_custom_hidden` | Toggle marked hidden state for file or directory under cursor |
| `gh` | `toggle_custom_hidden` | Alias to toggle marked hidden state for file or directory under cursor |

### Command Palette Actions (`<C-S-p>`)

| Action Name | Category | Description |
| :--- | :--- | :--- |
| `🙈 Toggle Custom Hidden Items Visibility` | `Explorer` | Toggles between hiding marked items and displaying them with theme colors |
| `🧹 Clear All Custom Hidden Files & Folders` | `Explorer` | Clears all hidden marks across the whole project/session |

### User Ex Commands

- `:NeotreeToggleCustomHiddenVisibility` — Toggles showing/hiding marked items.
- `:NeotreeClearCustomHidden` — Resets and removes all hidden marks.

---

## 🎨 Theme Customization

When marked hidden items are displayed in "Show Mode", Neo-tree highlights both their icon and file/folder name using the **`NeoTreeCustomHidden`** highlight group.

By default, `NeoTreeCustomHidden` links to Neovim's standard `Comment` highlight group with **strikethrough** (`strikethrough = true`) and **italic** (`italic = true`) text styles applied, making marked hidden items instantly distinguishable from normal files. To customize its appearance in your local configuration or colorscheme overrides:

```lua
-- Example: Customize highlight properties
vim.api.nvim_set_hl(0, "NeoTreeCustomHidden", { link = "Comment", strikethrough = true, italic = true })
```

---

## 🧠 Lua API Reference

The `plugins.krs.neotree_hidden` module exports the following functions for programmatic access:

```lua
local neotree_hidden = require("plugins.krs.neotree_hidden")

-- Toggles hidden state for an absolute or relative path
neotree_hidden.toggle_path("/path/to/file_or_dir")

-- Checks if a path (or any parent directory) is marked hidden
local is_hidden = neotree_hidden.is_path_hidden("/path/to/file")

-- Toggles visibility mode between "hide" and "show"
neotree_hidden.toggle_visibility()

-- Clears all marked hidden items
neotree_hidden.clear_all()

-- Refreshes Neo-tree filesystem view
neotree_hidden.refresh_neotree()
```
