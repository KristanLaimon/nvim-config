# 🔮 Haskell Toolchain Guide

This document provides setup instructions, LSP server settings, formatting pipelines, and execution details for Haskell in **KrsVim**.

---

## 📦 1. Installed Components

The **Haskell** bundle (`🔮 Haskell`) is an optional, opt-in bundle in the Language Tooling Manager (`:LanguageManager`). It includes:

| Tool | Type | Component Name | Command / Executable |
|---|---|---|---|
| **Haskell Language Server** | LSP | `haskell-language-server` | `haskell-language-server-wrapper` |
| **Fourmolu** | Formatter | `fourmolu` | `fourmolu` |
| **HLint** | Linter / Static Analysis | `hlint` | `hlint` |

---

## ⚙️ 2. System Requirements

- **GHC Compiler**: `ghc`
- **Cabal / Stack**: `cabal` or `stack`

Recommend installing via [GHCup](https://www.haskell.org/ghcup/):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
```

---

## 🛠️ 3. Formatting & Linting

- **Formatter**: `fourmolu` (configured as HLS default provider and conform formatter).
- **Linter**: `hlint` static checker.
- **Manual Command**: `:FormatDocument`.

---

## 🚀 4. Launch Profiles

- **Launch Profile (`.krsnvim/launch.json`)**:
  ```json
  {
    "name": "Run Haskell Script",
    "runtime": "haskell",
    "entry_point": "Main.hs"
  }
  ```
