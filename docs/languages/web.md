# 🌐 Web Frontend (HTML, CSS, Svelte, Astro, Tailwind)

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides a complete web frontend development setup for HTML, CSS, Svelte, Astro, and Tailwind CSS.

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Servers (LSP)** | `html`, `cssls`, `tailwindcss`, `svelte`, `astro`, `emmet_ls` | Complete LSP suite for markup, styling, component frameworks, and Emmet expansion |
| **Formatters (Conform)** | `prettierd`, `prettier`, `biome` | `prettier` plugin for Astro; `prettierd`/`prettier` for HTML, CSS, Svelte |
| **Treesitter Parsers** | `html`, `css`, `svelte`, `astro` | Syntax highlighting and element folding |
| **Autocompletion** | `blink.cmp` | Emmet abbreviations, CSS class autocompletion, and live Tailwind color previews (` ██ `) |
| **Tailwind Class Sorting** | `plugins.krs.editor.tailwind_organizer` | Automatic class sorting on save or on command (`:TailwindOrganize`) |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:TailwindOrganize` – Re-order Tailwind CSS classes in current file.
* `:TailwindOrganizerToggle` – Toggle auto-organizing Tailwind CSS classes on save.
* `:FormatDocument` – Format active HTML, CSS, Svelte, or Astro document.
* `:LanguageManager` – Install or uninstall Web Frontend language bundle.
