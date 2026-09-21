# 📝 Todo & Comments Right Sidebar (`plugins.krs.tools.todo_sidebar`)

[← Back to Wiki Index](index.md)

The **Todo & Comments Sidebar** is a fast, interactive right-docked panel (`split = "right"`) that scans, groups, and navigates all `// TODO:`, `/* FIXME */`, and multi-language comments across your entire project or current buffer.

---

## ⚡ Highlights

- **Right-Docked Layout**: Opens docked cleanly on the right side (`split = "right"`) of the editor layout without disrupting active code windows or the bottom dock.
- **Universal Multi-Language Detection**: Works across all programming languages with single-line comments (`//`, `#`, `--`, `;`, `%`) and multi-line/block comments (`/* ... */`, `<!-- ... -->`, `{- ... -}`, `(* ... *)`, `""" ... """`, `--[[ ... ]]`, and `*` continuation lines).
- **Rich Tag Categories & Distinct Color Badges**:
  - ` TODO`: Pending tasks, upcoming features, reminders (Cyan/Blue).
  - ` FIXME / BUG / FIX / ISSUE`: Defects, bugs, broken code needing repair (Red).
  - ` HACK`: Workarounds, temporary compromises, tech debt (Orange).
  - ` WARN / WARNING / CAUTION`: Critical warnings, hazards, side effects (Yellow).
  - ` NOTE / INFO / IDEA / DOC`: Architecture context, notes, design rationale (Green/Teal).
  - `⚡ PERF / OPTIM`: Performance bottlenecks and optimization notes (Magenta).
  - `󰙨 TEST / TESTING`: Pending test cases, assertions, mocks (Purple).
  - `🛡️ SAFETY / SECURITY / AUDIT`: Memory safety, security alerts, auth checks (Amber/Red).
  - `󰒡 REVIEW`: Peer review questions, questions for team (Blue).
  - `󰮆 DEPRECATED`: Deprecated methods scheduled for removal (Muted Gray).
- **Project & Buffer Scopes**: Toggle between scanning your entire project or just your active editor buffer with a single key (`b`).
- **Real-Time Live Updates**: Automatically refreshes in the background upon file save (`BufWritePost`) without freezing the UI.
- **Interactive File Grouping & Folding**: Fold/unfold file sections (`c` or `<Tab>`), collapse all (`C`), and filter by tag (`f`).
- **Companion Fuzzy Search**: Search all project comments with live preview using Telescope (`:TodoSearch`).

---

## ⌨️ Shortcuts & Commands

### Ex Commands

| Command | Action |
| :--- | :--- |
| `:TodoSidebar` / `:TodoToggle` | Toggle the right-side Todo sidebar |
| `:TodoRefresh` | Rescan workspace and refresh sidebar items |
| `:TodoSearch` | Open Telescope interactive fuzzy finder for TODOs |
| `:TodoFilter [tag]` | Open sidebar pre-filtered to a specific tag (e.g., `:TodoFilter FIXME`) |

### Global Toggle Keymaps

| Shortcut | Action |
| :--- | :--- |
| `<leader>td` | Toggle Todo Sidebar |
| `<C-S-o>` | Toggle Todo Sidebar (Alternative desktop shortcut) |
| `<C-S-p>` *(Command Palette)* | Search `Todo` to toggle, search, or refresh |

### Keymaps Inside the Sidebar

| Key | Action |
| :--- | :--- |
| `<CR>` | Jump to file and line in code window (keeps sidebar open) |
| `<Space>` | Preview file and line in code window (keeps focus in sidebar) |
| `o` | Jump to file and line, and close the sidebar |
| `c` / `<Tab>` | Fold / unfold current file group |
| `C` | Toggle fold all / unfold all files |
| `f` | Filter by comment tag (`TODO`, `FIXME`, `WARN`, `NOTE`, etc.) |
| `F` | Clear active tag filter (show all comments) |
| `b` | Toggle scope between Project and Active Buffer |
| `r` | Force rescan workspace |
| `q` / `<Esc>` | Close sidebar |
| `?` | Toggle shortcut help footer |

---

## 🔧 Architecture & Configuration

Settings can be customized directly in `M.settings` inside [`lua/plugins/krs/tools/todo_sidebar.lua`](../lua/plugins/krs/tools/todo_sidebar.lua):

```lua
M.settings = {
    width = 44,                    -- Default sidebar width in columns
    auto_refresh_on_save = true,   -- Debounced rescan on BufWritePost
    default_scope = "project",      -- "project" or "buffer"
}
```
