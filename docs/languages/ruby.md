# 💎 Ruby Toolchain Guide

This document provides setup instructions, LSP server settings, formatting pipelines, and execution details for Ruby in **KrsVim**.

---

## 📦 1. Installed Components

The **Ruby** bundle (`💎 Ruby`) is an optional, opt-in bundle in the Language Tooling Manager (`:LanguageManager`). It includes:

| Tool | Type | Component Name | Command / Executable |
|---|---|---|---|
| **Solargraph** | LSP | `solargraph` | `solargraph` |
| **RuboCop** | Formatter / Linter | `rubocop` | `rubocop` |

---

## ⚙️ 2. System Requirements

- **Ruby Runtime**: `ruby` (and `gem`)

### Installation Commands
- **Debian / Ubuntu**: `sudo apt install ruby-full`
- **Fedora**: `sudo dnf install ruby`
- **Arch Linux**: `sudo pacman -S ruby`
- **macOS**: `brew install ruby`

---

## 🛠️ 3. Formatting & Linting

- **Formatter**: `rubocop` (runs automatically on save via `conform.nvim` when `rubocop` is present in the workspace or system).
- **Manual Command**: `:FormatDocument` or `:ConformFormat`.

---

## 🚀 4. Launch Profiles

- **Launch Profile (`.krsnvim/launch.json`)**:
  ```json
  {
    "name": "Run Ruby Script",
    "runtime": "ruby",
    "entry_point": "main.rb"
  }
  ```
