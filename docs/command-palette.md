# Command Palette Configuration Guide

[← Back to Wiki Index](index.md)

This guide explains how the VSCode-style Command Palette works and how to modify, add, or remove commands in this Neovim configuration.

---

## 📁 Key File

- **Command Palette Plugin:** [`lua/plugins/krs/command_palette.lua`](../lua/plugins/krs/command_palette.lua)

---

## 🚀 How to Trigger the Command Palette

- **Shortcut:** `<Ctrl+Shift+P>` or `<Ctrl+Shift+p>` from any Neovim mode (Normal, Insert, Visual, Terminal).
- **Vim Command:** `:CommandPalette`

---

## 🧩 Architecture & Structure

The Command Palette uses [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) as its picker engine with fuzzy string matching.

Commands are stored in the `M.commands` array inside [`lua/plugins/krs/command_palette.lua`](../lua/plugins/krs/command_palette.lua).

Each command entry is a Lua table supporting three distinct action execution types:

1. **`cmd`**: Executes a standard Neovim / Vimscript command string (e.g., `"Lazy"`, `"Mason"`, `"Neotree toggle"`).
2. **`keys`**: Simulates pressing a keymap combination (e.g., `"<C-k>"`, `"<leader>e"`, `"<F2>"`).
3. **`fn`**: Executes a custom Lua callback function directly.

---

## 🛠️ Adding Commands to the Command Palette

### Method 1: Editing `M.commands` directly

Open [`lua/plugins/krs/command_palette.lua`](../lua/plugins/krs/command_palette.lua) and append your new entry to `M.commands`:

```lua
M.commands = {
    -- Existing commands...

    -- Example 1: Command string execution
    { name = "🔍 Open Git Blame", cmd = "Git blame", category = "Git" },

    -- Example 2: Key combination simulation
    { name = "⚡ Toggle Terminal 1", keys = "<C-;>", category = "Terminal" },

    -- Example 3: Custom Lua function execution
    { 
        name = "🧹 Clean Unused Buffers", 
        fn = function()
            require("plugins.krs.editor.buffer_cleaner").clean_buffers()
        end, 
        category = "Buffer" 
    },
}
```

### Method 2: Dynamic Runtime Addition (`M.add_command`)

You can register commands dynamically from any other Lua plugin or configuration file without modifying `command_palette.lua`:

```lua
local cp = require("plugins.krs.tools.command_palette")

cp.add_command({
    name = "🚀 Run Custom Build Script",
    cmd = "make build",
    category = "Tasks",
})
```

---

## ⚙️ Customizing Display & Layout

The Command Palette utilizes Telescope's dropdown theme:

```lua
pickers.new(
    themes.get_dropdown({
        prompt_title = " 🚀🦊 Command Palette (Ctrl+Shift+P) ",
        width = 0.75,
        results_title = "Available Commands",
    }),
    {
        -- ... finder and sorter definitions
    }
)
```

- To widen or narrow the modal, change `width = 0.75` (75% of screen width).
- To change category labeling or formatting, edit `entry_maker` inside `M.open_palette()`.

---

## ⌨️ Keybinding Configuration

Keybindings are configured in both the Lazy plugin specification `keys` table and inside the `config` function for global mode coverage (including Terminal mode `<C-S-p>` handling):

```lua
vim.keymap.set({ "n", "i", "v", "t" }, "<C-S-p>", function()
    if vim.fn.mode() == "t" then
        vim.cmd("stopinsert")
    end
    M.open_palette()
end, { noremap = true, silent = true, desc = "Open Command Palette" })
```

---

## 📜 MRU History & Persistent Sorting

Command executions are automatically saved to global persistent storage using `krs.core.store`.

- **Storage Location:** `stdpath("data") .. "/command_palette_history.json"`
- **Behavior:**
  - Whenever a command is executed from the Command Palette, it moves to the top of the history list.
  - When opening the Command Palette, results are automatically sorted with the most recently used (MRU) commands at the top.
  - Unvisited commands retain their original relative declaration order below recent commands.
  - History is stored globally across Neovim sessions.

