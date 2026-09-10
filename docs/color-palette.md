# Color Palette & Theme Configuration Guide

[← Back to Wiki Index](index.md)

This guide explains how to manage, customize, and extend colorschemes in this Neovim configuration.

---

## 📁 Key Files & Directories

- **Nagatoro Theme System & Picker:** [`lua/plugins/krs/theme_picker.lua`](../lua/plugins/krs/theme_picker.lua)
- **Statusline Theme Picker:** [`lua/plugins/krs/statusline_picker.lua`](../lua/plugins/krs/statusline_picker.lua)
- **Colorify Engine (CMP Completion):** [`lua/krs/lsp/colorify.lua`](../lua/krs/lsp/colorify.lua)
- **Theme Palette Files:** `colors/nagatoro-krs.lua`, `colors/nagatoro-light.lua`, `colors/onedark-krs.lua`, `colors/catppuccin-krs.lua`, `colors/nord-krs.lua`
- **Customization Guide:** [`how-to-customize-editor.md`](how-to-customize-editor.md)

---

## 🎨 Nagatoro Theme System (`:KrsThemePicker`)

KrsVim ships with a set of complete, hand-crafted themes matching the `nagatoro-krs` palette schema. Run `:KrsThemePicker` to open the interactive theme picker:

- **Available Themes:**
  - `nagatoro-krs` (Hayase Nagatoro Dark — Default)
  - `nagatoro-light` (Hayase Nagatoro Light)
  - `onedark-krs` (NvChad OneDark in nagatoro format)
  - `catppuccin-krs` (NvChad Catppuccin Mocha in nagatoro format)
  - `nord-krs` (NvChad Nord in nagatoro format)
  - `omarchy-krs` (Dynamic theme synced with Omarchy Linux)
- **Live Preview & Store Persistence:** Previews themes in real time while tabbed/selected. Cancelling (`<Esc>`) restores the previous theme; confirming (`<Enter>`) saves choice to `.krsnvim/theme.json` via [`krs.core.store`](architecture.md#layer-2--shared-libraries-luakrs).

---

## 🦊 Omarchy Dynamic Theme Sync (`:KrsOmarchySyncToggle`)

When running under [Omarchy Linux](https://omarchy.org/) (Hyprland), KrsVim can dynamically adapt all editor highlights, syntax tokens, and UI colors to match the active system theme:

- **Command Palette Toggle:** Open `<C-S-p>` and choose `🎨 Toggle Omarchy Theme Sync (Adapt colors to Omarchy - Default: OFF)`.
- **Default State:** Disabled (`false`) by default, preserving your explicit local theme choice until explicitly turned on.
- **Commands:**
  - `:KrsOmarchySyncToggle` — Toggle live Omarchy synchronization on/off.
  - `:KrsOmarchySyncNow` — Force an immediate re-sync with Omarchy's current active theme.
  - `:KrsOmarchySyncStatus` — Inspect current sync status and detected Omarchy theme.
- **Live Adaptation:** When enabled, a libuv filesystem event watcher (`vim.uv.new_fs_event`) monitors `~/.local/state/omarchy/current/theme/colors.toml` and `theme.name`. When `omarchy theme set <theme>` is executed in your terminal or desktop shell, Neovim automatically recompiles and applies the matching color palette on the fly with no restart required. Supports all 20+ Omarchy stock themes and custom themes in dark and light modes.

---

## 📊 NvChad Statusline & Statusline Theme Picker

Run `:KrsStatuslineTheme` (or select from Command Palette `<C-Shift-P>`) to switch statusline layouts:
- `nvchad_pills` (Rounded pill blocks with mode icons ` NORMAL`, Git diff icons, LSP server info ` lua_ls`, and diagnostics)
- `nvchad_blocks` (Slanted powerline block separators `` ``)
- `nvchad_round` (Curved slant separators `` ``)
- `nagatoro_classic` (Minimal classic layout)
- `vscode` (Flat VSCode style)
- `minimal` (Compact)

---

## 🎨 NvChad Completion Kind Icons & Colorify (`lua/krs/lsp/colorify.lua`)

Completion items in `blink.cmp` use NvChad layout:
- **Left**: Kind icon pill (` 󰊕 `, ` 󰩫 `, ` 󰀫 `, ` 󰌋 `, ` 󰌗 `) rendered with dedicated background and accent colors (`CmpKindBg_*`) from the active theme.
- **Color Items**: CSS & Tailwind hex/RGB colors render a preview rectangle badge (` ██ `) using the exact hex color as background with luminance-aware contrast text.
- **Right**: Kind label (`<Snippet>`, `<Function>`, `<Variable>`, etc.).

---

## 📦 How to Add a New Theme

To add a custom theme, create a new file `colors/mytheme-krs.lua` adhering to the `nagatoro-krs.lua` palette format. See [`how-to-customize-editor.md#5-how-to-customize-statusline--themes`](how-to-customize-editor.md#5-how-to-customize-statusline--themes) for full step-by-step instructions and code examples.
