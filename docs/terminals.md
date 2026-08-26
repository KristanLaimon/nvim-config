# 🖥️ Multi-Terminal Manager (`plugins.krs.dev.terminal`)

[← Back to Wiki Index](index.md)

The **Lazy-Loading Multi-Terminal Manager** manages up to 9 independent terminal buffers with instant switching, split height persistence, and clean window focus navigation.

---

## ⚡ Key Capabilities

1. **9 Independent Buffers**: Switch between terminals 1 through 9 instantly using `<Alt + 1..9>`.
2. **Toggle Key**: Press `<Ctrl + ;>` to toggle open or hidden state for the currently selected terminal.
3. **Height Persistence**: Remembers mouse-dragged terminal split window height (`terminal_height`).
4. **WSL Interop**: Automatically spawns terminal in WSL when working inside a WSL filesystem path.

---

## ⌨️ Terminal Shortcuts

- `<Alt + 1..9>`: Select & switch to terminal #1..9 (Normal, Insert, and Terminal modes)
- `<Ctrl + ;>`: Toggle show/hide for selected terminal
- `<C-w>` (inside terminal): Standard Neovim window navigation prefix
