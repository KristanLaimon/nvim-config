# 🐚 Shell, Bash & PowerShell Development Suite

This document provides setup instructions, LSP server settings, formatting pipelines, and execution details for Shell, Bash, and PowerShell scripts in **KrsVim**.

---

## 🛠️ Toolchain Summary

The **Shell & Bash** bundle (`🐚 Shell & Bash`) is an optional opt-in bundle in the Language Tooling Manager (`:LanguageManager`).

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Bash / Shell LSP** | `bashls` | Shell script LSP (`sh`, `bash`, `zsh`, `csh`, `ksh`) with ShellCheck integration |
| **PowerShell LSP** | `powershell_es` | PowerShell Editor Services LSP (`ps1`, `psm1`, `psd1`) |
| **Formatters (Conform)** | `beautysh` | Indentation and format cleanup for shell & powershell scripts |
| **Treesitter Parsers** | `bash`, `powershell` | Full syntax tree for Bash & PowerShell scripts |
| **Autocompletion** | `blink.cmp` | Command name, path, and variable autocompletion |
| **Debug Adapter (DAP)** | `bash-debug-adapter` / `bashdb` | Step-by-step debugging for Bash scripts |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:FormatDocument` – Format active shell script using Beautysh.
* `:LanguageManager` – Install or uninstall Shell, Bash & PowerShell bundle.
