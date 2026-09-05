# ⚡ Zig Toolchain Guide

This document provides setup instructions, LSP server settings, formatting pipelines, and execution details for Zig in **KrsVim**.

---

## 📦 1. Installed Components

The **Zig** bundle (`⚡ Zig`) is an optional, opt-in bundle in the Language Tooling Manager (`:LanguageManager`). It includes:

| Tool | Type | Component Name | Command / Executable |
|---|---|---|---|
| **Zig Language Server (zls)** | LSP | `zls` | `zls` |
| **zigfmt** | Formatter | Built into `zig` compiler | `zig fmt` |

---

## ⚙️ 2. System Requirements

- **Zig Compiler**: `zig`

### Installation Commands
- **Debian / Ubuntu**: `sudo snap install zig --classic` or download binary from [ziglang.org](https://ziglang.org/download/)
- **Fedora**: `sudo dnf install zig`
- **Arch Linux**: `sudo pacman -S zig`
- **macOS**: `brew install zig`

---

## 🛠️ 3. Formatting & Autocompletion

- **Formatter**: `zigfmt` (invokes `zig fmt` on save via `conform.nvim`).
- **LSP Features**: Autocompletion, inlay hints, and automatic fix diagnostics provided by `zls`.

---

## 🚀 4. Launch Profiles

- **Launch Profile (`.krsnvim/launch.json`)**:
  ```json
  {
    "name": "Run Zig Application",
    "runtime": "zig",
    "entry_point": "main.zig"
  }
  ```
