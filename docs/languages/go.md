# 🟦 Go Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides a dedicated **Go** environment powered by `gopls`, `gofumpt`, `goimports`, and `delve` DAP debugging.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `gopls` | Official Go language server with integrated staticcheck analysis, inlay hints, and code lenses |
| **Linters** | `staticcheck`, `revive`, `golangci-lint` | Advanced static analysis & code style (SA/ST/QF/U rules) running alongside `go vet` |
| **Formatters (Conform)** | `goimports`, `gofumpt` | Automatic import organization and strict Go code formatting |
| **Treesitter Parsers** | `go`, `gomod`, `gowork`, `gosum` | Highlighting for Go source, `go.mod`, `go.work`, `go.sum` |
| **Autocompletion** | `blink.cmp` | Type completion, struct field hints, and snippet completion |
| **Debug Adapter (DAP)** | `delve` (`nvim-dap-go`) | Full Go debugger for main packages, single files, and test suites |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:FormatDocument` – Format active file using `goimports` and `gofumpt`.
* `:LanguageManager` – Install or uninstall the Go language bundle.

---

## 🐞 Debugger Profiles (`<F5>`)

1. **Go: Debug Package**: Debug current Go package directory using Delve.
2. **Go: Debug Test**: Run and debug the Go test under cursor.
