# 🦀 Rust Development Guide

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

Select **Rust** in `:LanguageManager` to install `rust-analyzer` and the Rust Treesitter parser. The bundle verifies that the system Rust toolchain is available first.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server** | `rust_analyzer` | Completion, diagnostics, code actions, references, and navigation |
| **Formatter** | `rustfmt` | Used by `:FormatDocument` when available on `PATH` |
| **Treesitter** | `rust` | Syntax highlighting and indentation |
| **Requires** | `rustc`, `cargo`, `rustfmt` | Install with [rustup](https://rustup.rs) and add the formatter with `rustup component add rustfmt` if needed |

The Rust toolchain is never installed automatically. Once `rustc`, `cargo`, and `rustfmt` are available, choose the Rust bundle to add `rust-analyzer` through Mason.
