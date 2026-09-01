# 🪐 Astro Development Guide

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

Astro is an independent **Web Frameworks (Astro)** bundle in `:LanguageManager`. It installs the Astro language server and the Astro Treesitter parser without pulling in the Vanilla Web or Web UI bundles.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server** | `astro` | Completion, diagnostics, navigation, and embedded TypeScript support for `.astro` files |
| **Formatter** | `prettier` | Always used for Astro; the project must provide `prettier-plugin-astro` |
| **Treesitter** | `astro` | Syntax highlighting and structure |
| **Requires** | Node.js | Required by the Astro language server |

`biome` is intentionally not used for Astro formatting. Use `:FormatDocument` to format the active file.
