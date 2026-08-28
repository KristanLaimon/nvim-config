# ⌨️ Keybinds

[← Back to Wiki Index](index.md)

All keymappings in KrsVim are designed to be frictionless, non-modal where possible, and VSCode-style (`Ctrl+Shift+<letter>`, `Ctrl+<letter>`, or direct function keys). Global mappings live in `lua/keymaps/` — one file per domain (`editor`, `search`, `lsp`, `debug`, `krs`) — while module-local ones are defined by the module itself in its settings block.

Forgot a shortcut? Press `?` or `<F1>` to see context-aware help, or press `<C-S-p>` to fuzzy-search every registered command in the Command Palette.

---

## 🛠️ General Editing (VSCode-flavored)

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `<C-s>` | n, i, v | Save file (`:w`) |
| `<C-c>` | v | Copy selection to system clipboard |
| `<C-v>` / `<C-S-v>` | n, i, v, t | Paste from system clipboard |
| `<C-z>` | n, i, v | Undo |
| `<C-y>` / `<C-S-z>` | n, i | Redo |
| `<C-w>` | n | Close current buffer (smart tab-close style) |
| `<C-'>` / `<C-S-'>` / `<C-">` / `` <C-`> `` / `<C-~>` / `<C-^>` / `<C-acute>` | n, i, v, t | Toggle comment — line, or selection in visual mode |
| `<F2>` | n | Rename symbol, file on disk, or Neo-tree item |
| `<C-+>` / `<C-=>` | n, i, v, t | Increase font size (persisted) |
| `<C-->` | n, i, v, t | Decrease font size |
| `<C-0>` | n, i, v, t | Reset font size |
| `<C-S-Enter>` | n | Open image/video with the OS default app |
| `<C-S-d>` / `:KrsWiki` | n, i, v, t | Open Documentation Center & Wiki Modal |
| `<C-LeftMouse>` | all | Open the URL under the cursor in a browser |
| `<S-LeftMouse>` | n, i, v | Shift + Click symbol: Move cursor and jump to definition |
| `:q` / `:q!` / `<C-q>` | n, Cmd | Smart quit — split → tab → dashboard → quit |
| `:ReloadConfig` | Cmd | Reload the Neovim configuration |

---

## 🪟 Windows, Splits & Buffers

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `<C-h>` / `<C-l>` | n, t | Focus left / right window |
| `<C-j>` / `<C-k>` / `<C-S-A-k>` | n, t | Focus lower / upper window |
| `<C-S-h>` / `<C-S-j>` / `<C-S-k>` / `<C-S-l>` | n, i, v | Find a file and open it in a split (left / down / up / right) |
| `<C-Left>` / `<C-Right>` | n, i, v, t | Widen / narrow the window |
| `<C-Up>` / `<C-Down>` | n, i, v, t | Taller / shorter |
| `gt` / `<A-l>` / `<M-l>` / `<A-Right>` / `<M-Right>` | n | Next buffer |
| `gT` / `<A-h>` / `<M-h>` / `<A-Left>` / `<M-Left>` | n | Previous buffer |
| `<C-A-Left>` / `<C-A-Right>` | n | Move the current tab left / right |

---

## 💡 LSP, Diagnostics & Completion

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `K` | n | Hover documentation |
| `<A-k>` / `<M-k>` / `<A-j>` / `<M-j>` | n, i, v | Go to definition |
| `<A-S-k>` / `<M-S-k>` | n, i, v | Show all usages of symbol (or toast if no usages) |
| `<C-j>` | i, v | Parameter / signature help (when typing in insert/visual mode) |
| `<C-.>` | n, i, v | Code actions / quick fix at the caret |
| `<C-o>` | n | Jump back in the jump list |
| `<CR>` | i | Accept the highlighted completion |
| `<C-space>` / `<C-@>` / `<C-l>` | i | Force the completion menu / documentation open |
| `<C-n>` | n | Diagnostic float at cursor line |

---

## 🐞 Debugging

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `<A-b>` | n, i, v | Toggle breakpoint |
| `<A-h>` / `<M-h>` / `<C-S-h>` | n, i, v | Enable ⇄ disable breakpoint under the cursor |
| `<C-S-s>` | n, i, v | Run the default launch profile — or stop the running session |
| `<C-S-q>` | n, i, v | Launch profile manager |
| `<F5>` | n, i, v | Start / continue (raw DAP) |
| `<F10>` / `<F11>` / `<F12>` | n, i, v | Step over / into / out |
| `<C-S-x>` | n, i, v | Terminate the debugger and close the UI |
| `<C-S-j>` | n | Toggle the repl (while a session is live) |
| `:DapBreakpointsDisableAll` / `EnableAll` / `RemoveAll` | Cmd | Bulk breakpoint operations |

---

## 🚀 Launch, Tasks & Terminals

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `<C-S-t>` | n, i, v | Task menu (select, run, set default `[d]`, add `[a]`, delete `[x]`) |
| `<C-S-a>` | n, i, v | Run the project's default task |
| `<C-1>`..`<C-4>` | n, i, v, t | Toggle the output window for background task slot 1-4 |
| `<F7>` | n, i, v, t | Toggle the last-focused task output window |
| `:TaskRestart` / `:TaskKill` | Cmd | Restart / kill the active task |
| `<A-1>`..`<A-9>` | n, i, t | Select & switch to terminal #1-#9 (spawned on first use) |
| `<C-;>` / `<C-S-;>` / `<C-S-:>` / `<A-;>` / `<C-A-;>` | n, i, t | Toggle the selected terminal panel |
| `<C-w>c` | n (terminal) | Close the active terminal window |

---

## 🗂️ Workspaces & Sessions

| Shortcut / Command | Mode | Action |
| :--- | :---: | :--- |
| `<C-S-w>` | n, i, v, t | Open the Workspaces picker |
| `<C-S-m>` | n, i, v, t | Close the session and return to the dashboard (with save prompt) |
| `:WorkspaceSave [name]` / `:WorkspaceLoad [name\|slot]` | Cmd | Save / load workspace by name or slot |
| `:WorkspaceDelete` / `:WorkspaceRename` | Cmd | Delete / rename workspace |
| `:Workspaces` / `:WorkspaceSelect` | Cmd | Open the Workspaces picker |

---

## 🔍 Finding Things

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `<C-k>` / `<C-K>` / `<C-/>` / `<C-_>` | n, i | Find files, respecting `.gitignore` |
| `<C-A-k>` / `<C-S-/>` / `<C-?>` | n, i, v | Find files, ignoring `.gitignore` |
| `<C-f>` | n, i | Live grep across the project |
| `<C-S-y>` | n, i, v, t | Sneak-Peek project modal (90% width & height on-top window) |
| `<C-S-f>` | n, i, v | Floating Desktop file explorer |
| `<C-r>` | n | Recent projects modal |
| `<C-S-p>` | n, i, v, t | Command palette |

---

## 🌴 Neo-Tree File Explorer

| Shortcut | Context | Action |
| :--- | :---: | :--- |
| `<C-S-Space>` | n | Toggle the sidebar |
| `a` / `<C-n>` | Neo-tree | New file prompt |
| `A` / `<C-f>` / `<C-S-n>` | Neo-tree | New folder prompt |
| `r` | Neo-tree | Rename via the input modal |
| `d` | Neo-tree | Delete |
| `c` | Neo-tree | Copy |
| `m` | Neo-tree | Move via the floating explorer (`O` confirms the destination) |

---

## 🐙 Git & Git Control Center

| Shortcut | Mode | Action |
| :--- | :---: | :--- |
| `<C-S-g>` | n, i, v, t | Toggle the Git Control Center |
| `]c` / `[c` | n | Jump to next / previous Git change hunk |
| `<C-S-x>` | n, i, v | Stage all changed files |
| `<A-h>` / `<A-l>` | Git Center | Switch previous / next submodule repository tab |
| `s` / `S` | Git Center | Stage selected / stage all |
| `u` / `U` | Git Center | Unstage selected / unstage all |
| `r` / `R` | Git Center | Restore file under cursor / whole section |
| `c` / `m` / `t` | Git Center | Edit commit title / description / tag |
| `C` | Git Center | Commit (and tag) |
| `P` | Git Center | Push (with remote branch selector) |
| `<S-CR>` / `<S-Enter>` | Git Center | Open file under cursor in bufferline tab |

---

## 🎨 Themes, Utility Commands & Tools

| Shortcut / Command | Action |
| :--- | :--- |
| `:KrsThemePicker` | Nagatoro & NvChad Theme Picker with live preview |
| `:KrsStatuslineTheme` | Pick Statusline Theme (`nvchad_pills`, `nvchad_blocks`, `nvchad_round`, `vscode`, `minimal`) |
| `:KrsToggleReferences` | Toggle LSP Reference Counts / CodeLens |
| `:KrsWiki` / `:NvimWiki` / `<C-S-d>` | Open Documentation Center & Wiki Modal |
| `:NugetManager` | Nuget package manager for `.csproj` |
| `:TailwindOrganize` / `:TailwindOrganizerToggle` | Organize Tailwind CSS classes |
| `:KrsTypes` / `:TypeInjector` | Type injector menu |
| `:PHPCheckTools` | PHP / Composer / Intelephense / Pint / Xdebug diagnostic modal |
