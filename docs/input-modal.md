# 📝 Reusable Input Modal Component (`plugins.krs.ui.input_modal`)

[← Back to Wiki Index](index.md)

The **Reusable Input Modal** is a custom floating UI component in KRS Neovim (`lua/plugins/krs/input_modal.lua`) designed to provide a clean, consistent input experience for renaming, file creation, commit message editing, and custom prompts.

---

## ✨ Features & Capabilities

- **Dynamic Auto-Resizing**: As you type, the floating box resizes dynamically to fit your input.
- **Flexible Anchoring**: Supports `relative = "cursor"` (anchored directly above symbol) or `relative = "editor"` (centered floating dialog).
- **Standard Vim Editing**: Supports full Vim normal and insert mode keys inside the input buffer.
- **Clean Callback Interface**: Delivers an `(ok: boolean, new_text: string)` payload:
  - `ok = true` when confirmed with `<CR>` or `:w`.
  - `ok = false` when cancelled with `<Esc>`, `q`, or closing the window.
- **Dynamic Z-Index Stack Placement**: Integrates with [`krs.core.z_index`](z-index.md) to ensure prompt dialogs always render on top of any UI layer.
- **Global `vim.ui.input` Override**: Automatically powers standard Neovim input prompts across plugins.

---

## 🛠️ Lua API & Usage Example

```lua
local input_modal = require("plugins.krs.ui.input_modal")

input_modal.open({
    label = "Rename Symbol",         -- Title label shown in border header
    default_value = "old_symbol",    -- Initial text inside box
    relative = "cursor",             -- "cursor" or "editor"
    callback = function(ok, new_text)
        if ok and new_text ~= "" and new_text ~= "old_symbol" then
            print("Renamed to: " .. new_text)
        else
            print("Operation cancelled")
        end
    end,
})
```

---

## 📍 Integration Points

1. **LSP & File Rename (`<F2>`)**
   - In code buffers: opens inline anchored to cursor for LSP rename.
   - For unattached files: opens centered for disk file renaming.

2. **Neo-tree Integration**
   - Pressing `r` in Neo-tree triggers `rename_with_modal` for renaming files or folders.
   - Pressing `a`, `A`, `<C-n>`, or `<C-S-n>` triggers `add_with_modal` for creating new files or folders.

3. **Git Control Center (`<C-S-g>`)**
   - Pressing `c` edits Commit Title.
   - Pressing `m` edits Commit Description.
   - Pressing `t` edits Optional Tag.
