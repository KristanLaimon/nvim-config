# Plugin List

Core = eager-load (`lazy = false` / no lazy trigger, loaded at startup).
Non-core = lazy-loaded (`event` / `cmd` / `ft` / `keys` trigger).

## 1. External Deps

### Core

- `doki-theme/doki-theme-vim` — colorscheme source (`ui/themes.lua`)
- `nvim-lualine/lualine.nvim` — statusline (`ui/themes.lua`)
- `nvim-tree/nvim-web-devicons` — icons (`ui/devicons.lua`)
- `rcarriga/nvim-notify` — notifications (`ui/notify.lua`)
- `akinsho/bufferline.nvim` — tabline (`ui/bufferline.lua`)
- `goolord/alpha-nvim` — dashboard (`ui/dashboard.lua`)

### Non-core

**Editor**
- `windwp/nvim-autopairs` (`editor/autopairs.lua`)
- `lewis6991/gitsigns.nvim` (`editor/gitsigns.lua`)
- `MeanderingProgrammer/render-markdown.nvim`, `iamcco/markdown-preview.nvim` (`editor/markdown.lua`)
- `nvim-neo-tree/neo-tree.nvim` + deps `MunifTanjim/nui.nvim`, `nvim-lua/plenary.nvim`, `s1n7ax/nvim-window-picker`, `antosha417/nvim-lsp-file-operations`, `Crysthamus/nvim-file-operations`, `folke/snacks.nvim` (`editor/neo-tree.lua`)
- `NeogitOrg/neogit` + deps `nvim-lua/plenary.nvim`, `nvim-telescope/telescope.nvim`, `sindrets/diffview.nvim` (`editor/neogit.lua`)
- `vuki656/package-info.nvim` + dep `MunifTanjim/nui.nvim` (`editor/package-info.lua`)
- `ahmedkhalf/project.nvim` (`editor/project.lua`)
- `nvim-telescope/telescope.nvim` + deps `nvim-lua/plenary.nvim`, `nvim-telescope/telescope-file-browser.nvim` (`editor/telescope.lua`)
- `mfussenegger/nvim-dap` + deps `rcarriga/nvim-dap-ui`, `nvim-neotest/nvim-nio`, `theHamsta/nvim-dap-virtual-text`, `jay-babu/mason-nvim-dap.nvim`, `leoluz/nvim-dap-go`, `m00qek/baleia.nvim` (`editor/dap.lua`)

**LSP**
- `windwp/nvim-ts-autotag` (`lsp/autotag.lua`)
- `saghen/blink.cmp` + deps `b0o/schemastore.nvim`, `rafamadriz/friendly-snippets` (`lsp/blink_sources.lua`, `lsp/lsp.lua`)
- `stevearc/conform.nvim` + deps `williamboman/mason.nvim`, `zapling/mason-conform.nvim` (`lsp/formatting.lua`)
- `jwalton512/vim-blade`, `ricardoramirezr/blade-nav.nvim` (`lsp/laravel.lua`)
- `neovim/nvim-lspconfig` + deps `williamboman/mason.nvim`, `williamboman/mason-lspconfig.nvim`, `b0o/schemastore.nvim` (`lsp/lsp.lua`)
- `Wansmer/symbol-usage.nvim` (`lsp/symbol_usage.lua`)
- `nvim-treesitter/nvim-treesitter` (`lsp/treesitter.lua`)

**UI**
- `brenoprata10/nvim-highlight-colors` (`ui/css-colors.lua`)

**Misc**
- `vyfor/cord.nvim` (`miscelanea/discord.lua`)

## 2. KrsDeps

Self-authored plugins under `lua/plugins/krs/`, registered as lazy.nvim specs (`name = "krs_*"` / `dir = ...`).

### Core

- `buffer_cleaner.lua`
- `context_help.lua`
- `dap_breakpoints.lua`
- `font.lua`
- `image_viewer.lua`
- `input_modal.lua`
- `smart_check.lua`

### Non-core

- `bun_dap.lua` (local `dir` spec: `krs-bun-dap`)
- `caps_lock.lua`
- `colorscheme_preview.lua`
- `command_palette.lua`
- `dev_server.lua`
- `dotnet_creator.lua`
- `file_explorer.lua`
- `folding.lua`
- `git_center.lua`
- `hover_links.lua`
- `krsnvim_cmp.lua`
- `launch_cmp.lua`
- `launch_profiles.lua`
- `line_endings.lua`
- `lsp_references.lua`
- `nuget.lua`
- `php_tools_modal.lua`
- `pinned_tabs.lua`
- `sneak_peek.lua`
- `statusline_picker.lua`
- `tailwind_organizer.lua`
- `tasks.lua`
- `terminal.lua`
- `theme_picker.lua`
- `type_injector.lua`
- `usages_picker.lua`
- `wiki_modal.lua`
- `workspaces.lua`
- `wsl.lua`

Sub-module (not a lazy spec itself, used by `dap_breakpoints.lua`/DAP setup):
- `debuggers/_shared.lua`, `debuggers/bash.lua`, `debuggers/browsers.lua`, `debuggers/bun.lua`, `debuggers/csharp.lua`, `debuggers/go.lua`, `debuggers/krsnvimscript.lua`, `debuggers/node.lua`, `debuggers/php.lua`, `debuggers/python.lua`
