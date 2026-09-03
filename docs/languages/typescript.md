# 🟨 TypeScript & JavaScript Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides a high-performance **TypeScript / JavaScript** environment supporting Node.js, Bun, React (JSX/TSX), Vue, Svelte, and Astro.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `vtsls`, `eslint`, `biome` | TypeScript/JavaScript language server with auto-imports and inlay hints |
| **Formatters (Conform)** | `prettierd`, `prettier`, `biome` | Priority chain: `prettierd` → `prettier` → `biome` (`stop_after_first = true`) |
| **Treesitter Parsers** | `typescript`, `javascript`, `tsx`, `jsx` | Complete syntax parsing for TS, JS, and React |
| **Autocompletion** | `blink.cmp` | LSP completions, snippets, path autocompletion, and Tailwind CSS color previews |
| **Debug Adapter (DAP)** | `js-debug-adapter`, Bun adapter | `pwa-node` (Node.js), `pwa-chrome` (Chrome), `pwa-msedge` (Edge), and Bun DAP |
| **Type Injector** | `plugins.krs.tools.type_injector` | Automatic type acquisition and project `@types` helper |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:TypeInjector` – Open modular type injector modal to manage TypeScript definitions and project typings.
* `:TailwindOrganize` – Re-order Tailwind CSS classes in JSX/TSX/HTML according to standard class sorting guidelines.
* `:TailwindOrganizerToggle` – Toggle auto-organizing Tailwind CSS classes on save.
* `:FormatDocument` – Format active file using Prettier/Prettierd/Biome.
* `:LanguageManager` – Install the shared TypeScript components from the **Web UI (Svelte, Angular, React)** bundle.

---

## 🐞 Debugger Profiles (`<F5>`)

1. **`pwa-node`**: Attach to or launch Node.js scripts with `js-debug-adapter`.
2. **`pwa-chrome` / `pwa-msedge`**: Launch browser or attach to web dev servers (Vite, Next.js, Nuxt, React).
3. **Bun Debugger**: Direct debugging for Bun scripts and test suites.
