# 🧩 Web UI Development Guide

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

The **Web UI (Svelte, Angular, React)** bundle combines component-framework tooling with the shared TypeScript/JavaScript toolchain. Select it in `:LanguageManager` for a complete React, Svelte, or Angular environment.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **React / TypeScript** | `tsc`, `jsonls`, `eslint`, `biome` | JSX/TSX completion, diagnostics, auto-imports, and project-aware TypeScript support |
| **Svelte** | `svelte` | Completion and diagnostics for `.svelte` components |
| **Angular** | `angularls`, `cssls` | Angular templates plus CSS/SCSS diagnostics |
| **Formatters** | `prettierd`, `prettier`, `biome` | `prettierd` → `prettier` → `biome`; Svelte uses the same chain |
| **Debugging** | `js-debug-adapter` | Node and browser debugging; Bun remains available as a runtime |
| **Treesitter** | `typescript`, `javascript`, `tsx`, `jsx`, `svelte`, `html`, `scss` | Syntax structure for all three UI stacks |

Node.js is required. React uses the TypeScript language service; no separate React-only LSP is required.

Use `:FormatDocument` for formatting, `:TypeInjector` for project type definitions, and `:TailwindOrganize` for Tailwind class ordering.
