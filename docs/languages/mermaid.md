# 🧜 Mermaid Guide

This guide covers the Mermaid setup provided out-of-the-box by KrsVim.

## 📦 Installed Toolchain

KrsVim's Mermaid bundle installs the following via Mason (when selected via `:LanguageManager`):

1. **`mermaid-cli`** (`mmdc`): The official Mermaid CLI. Used for diagnostics (linting) and rendering (if terminal rendering is used).
2. **`mermaid` (Treesitter)**: Provides syntax highlighting for Mermaid diagram files and markdown code blocks.

## 🔌 Core Plugins

- **[`kevalin/mermaid.nvim`](https://github.com/kevalin/mermaid.nvim)**: Provides live preview, auto-formatting, linting, and terminal inline rendering for Mermaid files and Mermaid code blocks in Markdown.

## 🚀 Features & Commands

You can access these via the **Command Palette (`<C-S-p>`)** under the `Markdown / Mermaid` category, or via Ex commands:

| Command | Description |
|---|---|
| `:MermaidPreview` | Open live browser preview (auto-updates on edit) |
| `:MermaidPreviewStop` | Stop the preview server |
| `:MermaidFormat` | Auto-format current buffer or diagram |
| `:MermaidRender` | Render inline in Kitty/chafa terminals |
| `:MermaidCopyURL` | Copy preview URL to clipboard |

> **Note**: For Markdown files, hover over a Mermaid code block and use `:MermaidPreview` to preview only that diagram in the browser.

## ⚙️ How to Configure

The core plugin is configured in [`lua/plugins/editor/mermaid.lua`](../../lua/plugins/editor/mermaid.lua).

If you wish to change formatting or rendering themes (such as `beautiful-mermaid` and specific palettes), you can modify the `config` function inside `mermaid.lua`:

```lua
require("mermaid").setup({
    format = {
        shift_width = 4,
    },
    lint = {
        enabled = true,
        command = "mmdc",
    },
    preview = {
        renderer = "mermaid.js", -- "mermaid.js" or "beautiful-mermaid"
        theme = "default",
    },
})
```
