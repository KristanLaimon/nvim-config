-- ============================================================================
-- KRS ASTRO: Web Framework Language Configuration
-- ============================================================================

---@type KrsLangModule
local M = {}

M.lsp_server = { "astro" }

M.lsp_config = {
	astro = {
		init_options = {
			typescript = {
				tsdk = (function()
					local ts_lsp_server = require("krs.langs.typescript").lsp_server[1]
					local mason_path = vim.fs.normalize(vim.fn.stdpath("data") .. "/mason/packages")
					local packaged_ts = mason_path .. "/" .. ts_lsp_server .. "/node_modules/typescript/lib"
					local fallback_ts = mason_path .. "/typescript-language-server/node_modules/typescript/lib"
					if (vim.uv or vim.loop).fs_stat(packaged_ts) then
						return packaged_ts
					elseif (vim.uv or vim.loop).fs_stat(fallback_ts) then
						return fallback_ts
					end
					return nil
				end)(),
			},
		},
	},
}

M.mason = {
	astro = { mason = "astro-language-server", lang = "Astro", type = "lsp", cmd = "astro-ls" },
}

M.mason_order = { "astro" }
M.bundle_name = "🪐 Web Frameworks (Astro)"
M.requires = {
	{ cmd = "node", name = "Node.js", hint = "https://nodejs.org" },
}
M.treesitter = { "astro" }

M.formatters_by_ft = {
	astro = { "prettier" },
}

M.formatter_configs = {}

local function build_formatter_configs()
	local ts = require("krs.langs.typescript")
	vim.list_extend(M.formatter_configs, ts.PRETTIER_CONFIG_FILES)
	vim.list_extend(M.formatter_configs, ts.BIOME_CONFIG_FILES)
end

M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_project_config(buf, M.formatter_configs) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

function M.setup()
	build_formatter_configs()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "astro",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
