# 🌐 Environments Manager (`plugins.krs.tools.environments`)

[← Back to Wiki Index](index.md)

The **Environments Manager** allows managing up to 9 concurrent, isolated project environments (different working directories, window layouts, buffers, terminals, and scoped LSPs) inside a **single Neovim instance**, eliminating the need to launch multiple separate Neovim processes or terminal windows.

---

## ⚡ Highlights

- **9 Concurrent Project Slots**: Seamlessly switch between different project roots and working directories (`cwd`) with `<C-S-1>` through `<C-S-9>`.
- **Instant In-Memory Performance**: Retains project buffers in memory and uses high-speed session snapshotting (~10ms) when hopping between environments, avoiding costly cold restarts.
- **Scoped LSP Server Management**:
  - When switching between environments, LSPs remain dormant in memory at 0% CPU without being needlessly restarted.
  - When closing an environment (`:EnvironmentClose` or `d` in menu), any LSP servers scoped strictly to that project root are stopped automatically to release RAM and CPU.
- **Per-Environment Multi-Terminals**:
  - Each environment maintains its own independent pool of 9 terminal slots (`<A-1>`..`<A-9>`).
  - Terminal tasks, dev servers, and watcher scripts continue executing in the background in their respective project directories.
  - Closing an environment terminates its scoped terminal jobs cleanly.
- **Bufferline & Screen Indicator**:
  - The top bufferline tab bar dynamically filters out buffers from other environments, keeping your tab bar focused exclusively on the active project.
  - A statusline indicator badge (`󰒋 [Env N: name]`) appears automatically **only when > 1 environments are active**. When running in single-project mode, it is completely hidden.
- **Full Persistence & Workspaces Integration**:
  - All environment layouts and metadata are saved to `stdpath("data")/environments/index.json`.
  - Can export any environment slot as a named Workspace (`:EnvironmentSaveAsWorkspace`) or load any saved Workspace into an environment slot (`:EnvironmentLoadWorkspace`).

---

## ⌨️ Shortcuts & Keybindings

| Keybinding | Mode | Action |
|---|---|---|
| `<C-S-1>` .. `<C-S-9>` | Normal, Insert, Visual, Terminal | Switch directly to Environment Slot 1 through 9 |
| `<C-!>` .. `<C-(>` | Normal, Insert, Visual, Terminal | Terminal-compatible aliases for `<C-S-1>`..`<C-S-9>` |
| `<C-S-e>` / `<leader>ee` | Normal, Insert, Visual, Terminal | Open Interactive Environments CRUD Menu |
| `<A-1>` .. `<A-9>` | Normal, Insert, Terminal | Select and display Terminal 1..9 (scoped to current environment) |

---

## 🎛️ Interactive CRUD Menu

Open the menu with `<C-S-e>`, `:EnvironmentMenu`, or `:Environments`.

| Key in Menu | Action |
|---|---|
| `<CR>` / `Enter` | **Switch** to the selected environment (or **Create** if slot is empty) |
| `a` / `+` | **Add / Configure** a new environment in the selected slot (prompts for project directory) |
| `r` / `<F2>` | **Rename** the selected environment |
| `d` / `<Del>` | **Close & Delete** the selected environment (stops scoped LSPs & terminals) |
| `s` | **Save** all environments and session snapshots to disk |
| `w` | **Export** the selected environment slot as a named Workspace |
| `1` .. `9` | Directly switch to slot number 1..9 |
| `q` / `<Esc>` | Close menu |

---

## 💻 Ex User Commands

- `:EnvironmentMenu` / `:Environments`: Opens the interactive Telescope CRUD menu.
- `:EnvironmentSwitch <slot>`: Switches directly to environment slot `1..9`.
- `:EnvironmentNew [slot] [dir] [name]`: Creates a new environment slot.
- `:EnvironmentClose [slot]`: Closes an environment slot, unloads buffers, terminates scoped terminals, and stops scoped LSPs.
- `:EnvironmentRename [slot] [name]`: Renames an environment.
- `:EnvironmentSave`: Manually persists all active environment layouts and metadata.
- `:EnvironmentRestore`: Restores all previously saved environments and resumes the active slot.
- `:EnvironmentList`: Displays a concise notification listing all slots, their status, cwds, and attached LSPs.
- `:EnvironmentSaveAsWorkspace [slot] [name]`: Exports an environment slot as a named Workspace.
- `:EnvironmentLoadWorkspace [slot] [workspace_name]`: Loads a saved Workspace into an environment slot.

---

## 🚀 Command Palette Integration

All Environment commands are discoverable in the Command Palette (`<C-S-p>` or `:CommandPalette`) under the **"Environments"** category.
