# 🐍 Python Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides a complete **Python** setup with type checking, formatting, and debugging via `debugpy`.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `pyright` (or `ruff`) | Fast static type checking and auto-imports |
| **Formatters (Conform)** | `black`, `isort`, `ruff` | Code formatting and import sorting |
| **Treesitter Parsers** | `python` | Syntax highlighting and indentation |
| **Autocompletion** | `blink.cmp` | Code completion, docstrings, and symbol inspection |
| **Debug Adapter (DAP)** | `debugpy` | Python debugging for CLI scripts, Django, and Flask apps |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:PythonSelectInterpreter` – Interactive UI picker to switch the Python executable/virtualenv (updates `.vscode/settings.json`, basedpyright LSP, and status bar).
* `:FormatDocument` – Format active Python file using Black/Ruff/Isort.
* `:LspInfo` – View attached LSP clients and active Python interpreter path.
* `:LanguageManager` – Install or uninstall the Python language bundle.

---

## 📊 Status Bar Integration

When opening or editing a Python buffer, the status bar displays:
` 3.12.2 (.venv)` or ` 3.11.4 (System)`

It dynamically reflects the Python version and active environment (`.venv`, `venv`, `conda`, `pyenv`, `System`) used by basedpyright for IntelliSense and type diagnostics.

---

## 🐞 Debugger Profiles (`<F5>`)

1. **Python: Launch File**: Debug current Python script with `debugpy`.
2. **Python: Attach**: Attach debugger to a remote or running Python process.
