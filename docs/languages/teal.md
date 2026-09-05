# 🩵 Lua Extras & Teal Toolchain Guide

This document provides setup instructions and details for Lua static analysis extras (`luacheck`, `selene`) and Teal language support (`teal-language-server`) in **KrsVim**.

---

## 📦 1. Installed Components

The **Lua Extras & Teal** bundle (`🩵 Lua Extras & Teal`) is an optional, opt-in bundle in the Language Tooling Manager (`:LanguageManager`).

> ℹ️ Note: Core Lua editing (`lua_ls`, `stylua`) remains essential and always enabled. This bundle provides additional static analysis tools for Lua alongside Teal typed language support.

| Tool | Type | Component Name | Command / Executable |
|---|---|---|---|
| **Teal Language Server** | LSP | `teal-language-server` | `teal-language-server` |
| **Luacheck** | Static Checker / Linter | `luacheck` | `luacheck` |
| **Selene** | Static Checker / Linter | `selene` | `selene` |

---

## ⚙️ 2. Features

- **Teal LSP**: Full completion and diagnostics for Teal typed Lua dialect (`.tl` files).
- **Luacheck**: Static analysis and linter for Neovim/Lua code checking.
- **Selene**: Fast Rust-based linter for Lua.
