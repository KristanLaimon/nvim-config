# ⚡ C / C++ Toolchain Guide

This document provides setup instructions, LSP server settings, formatting/static-checking pipelines, debugging profiles, and commands for C and C++ in **KrsVim**.

---

## 📦 1. Installed Components

The **C / C++** bundle (`⚡ C / C++`) is an optional, opt-in bundle in the Language Tooling Manager (`:LanguageManager`). It includes:

| Tool | Type | Component Name | Command / Executable |
|---|---|---|---|
| **clangd** | LSP | `clangd` | `clangd` |
| **clang-format** | Formatter | `clang-format` | `clang-format` |
| **cpplint** | Static Analysis / Linter | `cpplint` | `cpplint` |
| **cppcheck** | Static Analysis / Linter | `cppcheck` | `cppcheck` |
| **codelldb** | Debug Adapter (DAP) | `codelldb` | `codelldb` |

---

## ⚙️ 2. System Requirements

Before installing the Mason packages via `:LanguageManager`:
- **Compiler**: `gcc` / `g++` or `clang` / `clang++`
- **Build Systems**: `make` or `cmake`

### Installation Commands
- **Debian / Ubuntu / WSL**:
  ```bash
  sudo apt install build-essential gdb cmake clangd clang-format cppcheck
  ```
- **Fedora / RHEL**:
  ```bash
  sudo dnf groupinstall "Development Tools"
  sudo dnf install gcc-c++ cmake clang clang-tools-extra cppcheck
  ```
- **Arch Linux**:
  ```bash
  sudo pacman -S base-devel cmake clang cppcheck
  ```
- **macOS (Homebrew)**:
  ```bash
  brew install gcc cmake llvm cppcheck
  ```

---

## 🛠️ 3. Formatting & Static Checking

- **Auto-Formatting**: Standard `clang-format` rules apply on save or when executing `:FormatDocument`.
- **Static Checking**: Static checking and linting runs using `cppcheck` and `cpplint` (or via `clangd` built-in diagnostics).

---

## 🐞 4. Debugging & Launch Profiles

- **DAP Engine**: `codelldb` (LLDB Debug Adapter)
- **Keybindings**: Press `<F5>` to start debugging, `<C-b>` to toggle breakpoints.
- **Launch Profile (`.krsnvim/launch.json`)**:
  ```json
  {
    "name": "Run C++ Main",
    "runtime": "cpp",
    "entry_point": "main.cpp"
  }
  ```
