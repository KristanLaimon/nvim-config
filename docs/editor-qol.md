# 🎛️ Editor Quality of Life

[← Back to Wiki Index](index.md)

The small modules — each one file in `lua/plugins/krs/`, each fixing one specific annoyance.

---

## 🚪 Buffer Cleaner & Smart Quit (`buffer_cleaner.lua`)

`:q` in a normal Neovim quits the window, which in practice means "quit the editor" more often than you meant it. Here `:q` and `:q!` are overridden to answer *what did you actually want to close?*:

```
window is one of several splits?  → close the split
several tabs/buffers open?        → close the current tab, move to the previous
last real file?                   → delete the buffer, land on the dashboard
already on the dashboard?         → quit Neovim
```

`<C-q>` does the same thing.

It also sweeps empty, unmodified `[No Name]` buffers as soon as a real file opens — the ones that pile up from `:e`, from opening a folder, or from a plugin that created a scratch buffer and forgot it.

And it keeps `_G.OpenedFolders`, the record of folders you've opened as projects that feeds the pickers.

---

## 💡 Help Menu & Cheatsheet Manager (`help_modal.lua`)

Press `<F1>` (or run `:KrsHelp`, `:Cheatsheet`, `:HelpMenu`, or pick from the Command Palette `<C-S-p>`) to open the **Help Menu & Cheatsheet Manager**.

A dual-pane modal mirroring the Wiki UI:
- **Left Panel (Topic Index)**: Categorized domains:
  - `🌐 Environments` — Multi-CWD project slots (`<C-S-1..9>`), CRUD menu (`<C-S-e>`, `<leader>ee`).
  - `🐙 Git-Center` — Git Center (`<C-S-g>`), staging (`<C-S-x>` / `<A-s>`), diff navigation (`[d`/`]d`).
  - `📁 Neo-tree` — Sidebar file explorer (`<C-e>`), file operations, desktop explorer (`<C-/>`).
  - `📑 InTab` — Buffer tab hopping (`<A-h>` / `<A-l>`), pin tabs (`<C-p>`), buffer cleaner (`<C-w>`).
  - `🖥️ Terminal` — Multi-terminal drawer (`<C-;>`), terminal slots (`<A-1..9>`), resize keys.
  - `🛠️ Task Runner` — Tasks picker (`<C-S-t>`), default task (`<C-S-a>`), output drawers (`<C-1..4>`).
  - `🚀 Launch & Debug` — Launch profiles (`<C-S-q>`), default runner (`<C-S-s>`), DAP debugging (`<F5>`).
  - `🗂️ Workspaces` — Workspaces UI (`<C-S-w>`), project session persistence.
  - `🧰 Command Palette` — Fuzzy actions (`<C-S-p>`), recent projects (`<C-S-r>`), find files (`<C-S-f>`).
  - `✂️ Editor & Navigation` — Save, clipboard bridge, undo/redo, comment toggling, and code folding.
- **Right Panel (Live Runtime Shortcuts)**:
  - **Zero Hardcoded Keys**: Introspects Neovim's active runtime keymap registry on the fly.
  - **Clean & Filtered**: All `<leader>###` keymaps are suppressed (except `<leader>ee`), focusing on clean chords.
- **Controls**:
  - `j` / `k` / `Down` / `Up`: Navigate topics (live-updates cheatsheet in right panel).
  - `<Tab>` / `<Right>`: Focus reader cheatsheet pane.
  - `<S-Tab>` / `<Left>`: Return focus to left index.
  - `/` or `<C-f>`: Search text within pane.
  - `q` / `<Esc>` / `<F1>`: Dismiss help modal.

---

## ❓ Context Help (`context_help.lua`)

`?` shows a quick notification cheatsheet for **whatever window is currently focused** without opening a modal.

Four contexts, detected from the filetype and buffer name:

| Context | Shows |
| :--- | :--- |
| Neo-tree | create / rename / delete / copy / cut / paste, reveal in system explorer |
| Git (Git Center, Neogit, Diffview) | section jumps, stage/unstage, commit, diff modal, preview scrolling |
| Telescope / file explorer / task runner | create, rename, delete, copy, move, open-as-project, favourite, multi-select |
| Anything else (editor) | find file, split-find, live grep, explorer, task menu, comment, terminals |

---

## 🎨 Live Colorscheme Preview (`colorscheme_preview.lua`)

Themes apply **while you tab through** `:colorscheme <Tab>`, so you pick by looking rather than by name.

It listens on `CmdlineChanged`, matches `^colo%S*%s+(%S+)%s*$`, remembers the original theme the first time it previews, and applies each candidate with `pcall` so an unloadable theme doesn't throw mid-typing. On `CmdlineLeave` it checks `vim.v.event.abort`: `<Esc>` restores what you had, `<Enter>` keeps what you're looking at.

See [Color Palette](color-palette.md) for the palette itself.

---

## 🖼️ Image Viewer (`image_viewer.lua`)

`:ImageViewer` renders an image as terminal pixel art through `chafa`, in a floating window — enough to answer "is this the right asset?" without leaving the editor.

`<C-S-Enter>` hands the file to the OS default application instead, which is what you want for anything `chafa` can't do (video, PSD, a real look at a photo). `:OpenRootInExplorer` opens the project root in the system file manager.

---

## 🔤 Font Sizing (`font_size.lua`)

`<C-+>` / `<C-=>` increases font size, `<C-->` decreases, `<C-0>` resets, and the chosen size is saved to `font_config.json` in `nvim-data` (`stdpath("data")`) so it survives restarts.

Defaults to JetBrainsMono Nerd Font at 14pt, clamped to 6–40. It sets `guifont` and, under Neovide, the scale factor — so it does nothing useful in a plain terminal, where font size belongs to the terminal emulator. `<C-MouseWheel>` also works.

---

## 📦 Nuget Manager (`nuget.lua`)

`:NugetManager` opens a Telescope picker over the `<PackageReference>` entries of the project's `.csproj`: `a` adds a package, `u` updates the selected one, `d` removes it.

Every operation shells out to `dotnet add/remove package` rather than editing the XML, so the `.csproj` stays formatted the way the SDK wants it. If the project has no `.csproj`, it says so and does nothing.

---

## 🐘 PHP Tools Check (`php_tools_modal.lua`)

`:PHPCheckTools` probes for PHP, Composer, Intelephense, Pint and the debug adapter — **on the Windows host and inside WSL** — and shows a floating modal with install steps for whatever is missing.

The dual probe is the point: on Windows it's completely normal to have PHP in WSL and nothing on the host, and "command not found" doesn't tell you which side is empty.

---

## 🐧 WSL Helpers (`wsl.lua`)

Distro detection and path translation, used by anything that needs to know whether a path lives inside `\\wsl.localhost\<Distro>\`:

- the [WSL file explorer](file-explorer.md) (`:TelescopeFileBrowserWSL`)
- the [terminal manager](terminals.md), which launches `wsl.exe -d <Distro> --cd <path>` instead of the Windows shell when the `cwd` is inside a distro
- the dashboard, which only shows the WSL button when `wsl.available()` is true
