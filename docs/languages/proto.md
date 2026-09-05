# 📜 Protocol Buffers Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides editing, validation, autocompletion, and formatting for **Protocol Buffer (`.proto`)** schema definitions.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `buf_ls`, `protols` | Protobuf (`.proto`) completion, hover, definitions, & diagnostic validation |
| **Formatters (Conform)** | `protolint` | Protobuf code formatting and lint rules |
| **Linters & Diagnostics** | `buf_ls`, `protolint` | Protobuf schema linting, syntax validation, and rule checking |
| **Treesitter Parsers** | `proto` | Syntax trees for `.proto` |
| **Autocompletion** | `blink.cmp` | Full intellisense for Protobuf keywords, fields, message types, and imports |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:FormatDocument` – Format `.proto` file.
* `:LanguageManager` – Install or uninstall Protocol Buffers bundle.
