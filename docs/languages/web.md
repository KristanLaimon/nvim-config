# 🌐 Web Frontend Vanilla (HTML, CSS, Snippets)

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

KrsVim provides the baseline frontend setup for plain HTML and CSS projects, including Emmet snippets and Tailwind CSS support. Framework-specific tooling is documented separately in the [Astro guide](astro.md) and [Web UI guide](web-ui.md).

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Servers (LSP)** | `html`, `cssls`, `tailwindcss`, `emmet_ls` | Markup, styling, Tailwind class completions, and Emmet expansion |
| **Formatters (Conform)** | `prettierd`, `prettier`, `biome` | Priority chain for HTML and CSS |
| **Treesitter Parsers** | `html`, `css` | Syntax highlighting and element folding |
| **Autocompletion** | `blink.cmp` | Emmet abbreviations, CSS class autocompletion, and live Tailwind color previews (` ██ `) |
| **Tailwind Class Sorting** | `plugins.krs.editor.tailwind_organizer` | Automatic class sorting on save or on command (`:TailwindOrganize`) |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:TailwindOrganize` – Re-order Tailwind CSS classes in current file.
* `:TailwindOrganizerToggle` – Toggle auto-organizing Tailwind CSS classes on save.
* `:FormatDocument` – Format the active HTML or CSS document.
* `:LanguageManager` – Install or uninstall the Web Frontend Vanilla bundle.
