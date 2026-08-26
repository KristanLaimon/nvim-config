-- ============================================================================
-- PLUGINS: blink.cmp completion sources owned by this config.
-- ============================================================================
-- WHAT IS REGISTERED HERE
--   launch_json  IntelliSense inside `.krsnvim/launch.json`: task names, runtimes
--                and modes (lua/plugins/krs/launch_cmp.lua).
--   krsnvim      IntelliSense inside `*.krsnvim` scripts: console, fetch, import
--                and the library modules (lua/plugins/krs/krsnvim_cmp.lua).
--
--   `schemastore.nvim` is declared here too, because it is what jsonls and yamlls
--   pull their schemas from in lsp.lua.
--
-- WHY score_offset
--   Inside those two file types these completions are the only relevant ones, so
--   they outrank the generic buffer and snippet sources.
--
-- OTHER SOURCES
--   editorconfig -> lua/plugins/lsp/editorconfig.lua
--   dap repl     -> lua/plugins/lsp/lsp.lua (sources.providers.dap)
-- ============================================================================

--- Sources added to blink.cmp: provider name -> definition.
local sources = {
	launch_json = {
		name = "LaunchJson",
		module = "plugins.krs.dev.launch_cmp",
		score_offset = 100,
		enabled = function()
			return vim.fn.expand("%:t") == "launch.json"
		end,
	},
	krsnvim = {
		name = "KrsNvimScript",
		module = "plugins.krs.dev.krsnvim_cmp",
		score_offset = 100,
		enabled = function()
			local ft = vim.bo.filetype
			local name = vim.fn.expand("%:t")
			return ft == "lua" or ft == "krsnvim" or name:match("%.krsnvim$") ~= nil or name:match("%.lua$") ~= nil
		end,
	},
}

return {
	{
		"b0o/schemastore.nvim",
		lazy = true,
	},
	{
		"saghen/blink.cmp",
		opts = function(_, opts)
			opts.sources = opts.sources or {}
			opts.sources.providers = opts.sources.providers or {}

			for name, definition in pairs(sources) do
				opts.sources.providers[name] = definition

				if opts.sources.default and not vim.tbl_contains(opts.sources.default, name) then
					table.insert(opts.sources.default, name)
				end
			end
		end,
	},
}
