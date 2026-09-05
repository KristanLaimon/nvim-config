-- ============================================================================
-- KRS LUA: Centralized Lua Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard 2-space indentation defaults for Lua and .krsnvim buffers when no
--   .editorconfig file specifies buffer settings. Also owns the lua_ls LSP server
--   (which also serves `.krsnvim` scripts) and the stylua formatter.
-- ============================================================================

---@type KrsLangModule
local M = {}

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "lua_ls" }

--- lspconfig server settings, keyed by server name (see M.lsp_server). `.krsnvim`
--- script globals (fetch, console, import, krsnvim) are re-applied on LspAttach by
--- lua/plugins/lsp/lsp.lua so they don't show up as undefined; the workspace
--- library comes from the type injector.
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	lua_ls = {
		filetypes = { "lua", "krsnvim" },
		before_init = function(_, config)
			local libs = require("plugins.krs.tools.type_injector").get_active_lua_libraries(config.root_dir)

			-- Detect Omarchy and inject hyprland and omarchy types
			local env = require("krs.core.environment").detect()
			if env.is_omarchy then
				table.insert(libs, "/usr/share/hypr")
				table.insert(libs, "/usr/share/omarchy")
				-- Optionally also append to globals if not done in the diagnostics below
				local globals = config.settings.Lua.diagnostics.globals or {}
				table.insert(globals, "hl")
				table.insert(globals, "omarchy")
				config.settings.Lua.diagnostics.globals = globals
			end

			config.settings.Lua.workspace.library = libs
		end,
		settings = {
			Lua = {
				runtime = {
					version = "LuaJIT",
				},
				diagnostics = {
					globals = { "vim", "fetch", "console", "import", "krsnvim", "cli", "terminal", "fs" },
				},
				workspace = {
					checkThirdParty = false,
				},
				completion = {
					callSnippet = "Replace",
				},
				hint = {
					enable = true,
					setType = true,
				},
				telemetry = {
					enable = false,
				},
				format = {
					enable = true,
					defaultConfig = {
						indent_style = "tab",
						indent_size = "2",
					},
				},
			},
		},
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	lua_ls = { mason = "lua-language-server", lang = "Lua", type = "lsp", cmd = "lua-language-server" },
	stylua = { mason = "stylua", name = "stylua", type = "formatter", cmd = "stylua" },
}

M.mason_order = { "lua_ls", "stylua" }

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "🌙 Minimal Core"
M.is_minimal = true
M.requires = {} -- lua-language-server ships as a self-contained binary via Mason
M.treesitter = { "lua", "vim", "vimdoc", "markdown", "markdown_inline" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	lua = { "stylua" },
}

--- Registers the krsnvimscript DAP adapter (a headless nvim running the file
--- through the krsnvim runtime) and its launch configuration. A function, not
--- plain `dap_configs`: the adapter itself is a callback (`type = "executable"`
--- alone can't build the `dofile(...)` command line for the launched program).
--- @param dap table The `dap` module.
function M.dap_setup(dap)
	dap.adapters.krsnvimscript = function(callback, config)
		callback({
			type = "executable",
			command = "nvim",
			args = {
				"--headless",
				"-c",
				"lua package.path = vim.fn.stdpath('config') .. '/lua/?.lua;' .. vim.fn.stdpath('config') .. '/lua/?/init.lua;' .. package.path; require('krs.lib.krsnvim'); dofile('"
					.. (config.program or "")
					.. "')",
			},
		})
	end

	dap.configurations.lua = dap.configurations.lua or {}
	table.insert(dap.configurations.lua, {
		type = "krsnvimscript",
		request = "launch",
		name = "🚀 Run with krsnvimscript",
		program = "${file}",
		cwd = "${workspaceFolder}",
	})
end

--- Launch-profile runtimes this language owns (see lua/krs/launch/runtimes.lua).
--- `krsnvimtranspiler` isn't a process: it transpiles the script to shell files
--- and returns. `args_str` selects the target ("sh", "ps1", anything else = both).
local NVIM_LUA_ENTRY_COMMAND =
	"nvim --headless -c \"lua package.path = vim.fn.stdpath('config') .. '/lua/?.lua;' .. vim.fn.stdpath('config') .. '/lua/?/init.lua;' .. package.path; require('krs.lib.krsnvim')\" -l"
M.launch_runtimes = {
	lua = {
		command = NVIM_LUA_ENTRY_COMMAND,
		dap = function(profile, root, ctx)
			return {
				type = "krsnvimscript",
				request = "launch",
				name = profile.name,
				program = ctx.full_entry,
				cwd = root,
			}
		end,
	},
	krsnvimscript = {
		command = NVIM_LUA_ENTRY_COMMAND,
		dap = function(profile, root, ctx)
			return {
				type = "krsnvimscript",
				request = "launch",
				name = profile.name,
				program = ctx.full_entry,
				cwd = root,
			}
		end,
	},
	krsnvimtranspiler = {
		execute = function(ctx)
			local transpiler = require("krs.lib.krsnvim").krsnvimtranspiler
			if ctx.args_str == "sh" then
				transpiler.export_sh(ctx.full_entry)
			elseif ctx.args_str == "ps1" then
				transpiler.export_ps1(ctx.full_entry)
			else
				transpiler.export_both(ctx.full_entry)
			end
			return true
		end,
	},
}

--- Standard defaults for Lua & KrsVim scripts (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply Lua language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Lua language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "lua", "krsnvim" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
