# 🛠️ Per-Project Task Runner & Executor (`plugins.krs.dev.tasks`)

[← Back to Wiki Index](index.md)

The **KRS Task Runner** provides automatic project build detection, custom task chains, background task slots, and error popups for seamless development workflows.

---

## ⚡ Key Features

1. **Auto-Discovery**: Scans project build files (`package.json`, `Makefile`, `Cargo.toml`, `go.mod`) automatically.
2. **Task Chains**: Allows chaining multiple commands (`make && make test`). If a step fails, execution halts immediately and displays a floating alert.
3. **Background Slots**: Manages up to 4 concurrent task output buffers (`<C-1..4>`), keeping tasks (e.g. `bun run dev`) running in the background.
4. **Task Output Toggle**: Easily toggle the task output terminal window with `<C-S-:>` / `<C-S-;>` (`Ctrl + Shift + ;`).

---

## ⌨️ Shortcuts & User Commands

- `<C-S-t>`: Open Task Manager (Telescope)
- `<C-S-a>`: Run Default Task or Open Task Menu
- `<C-1..4>`: Toggle Background Task Slot 1..4
- `<C-`>`: Toggle Last Active Task Output Terminal
- `:TaskRestart`: Kill and restart the active task (or via Command Palette `<C-S-p>` -> `🔄 Restart Current Task (Kill & Rerun)`)
- `:TaskKill`: Stop/kill the currently running task process
- `:TaskRunDefault`: Execute the default task directly
- `d` (inside menu): Set selected task as project default
- `a` (inside menu): Add custom single command task
- `c` (inside menu): Add chained multi-step task
- `x` (inside menu): Delete task
