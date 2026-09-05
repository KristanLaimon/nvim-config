-- ============================================================================
-- KRS WEB UI: Svelte, Angular, and React Tooling
-- ============================================================================

---@type KrsLangModule
local M = {}
local typescript = require("krs.langs.typescript")

-- React is handled by the TypeScript language service (`tsc`) for JSX and TSX.
M.lsp_server = { "svelte", "angularls", typescript.lsp_server[1] }

M.lsp_config = {
	svelte = {
		on_attach = function(client, _)
			vim.api.nvim_create_autocmd("BufWritePost", {
				pattern = { "*.js", "*.ts" },
				callback = function(ctx)
					client.notify("$/onDidChangeTsOrJsFile", { uri = ctx.match })
				end,
			})
		end,
	},
	angularls = {
		root_dir = function(bufnr, on_dir)
			local path = vim.api.nvim_buf_get_name(bufnr)
			local root = vim.fs.root(path ~= "" and path or bufnr, { "angular.json", "project.json", "nx.json" })
			if root then
				on_dir(root)
			end
		end,
	},
}

M.mason = vim.tbl_deep_extend("force", {}, typescript.mason, {
	svelte = { mason = "svelte-language-server", lang = "Svelte", type = "lsp", cmd = "svelteserver" },
	angularls = { mason = "angular-language-server", lang = "Angular", type = "lsp", cmd = "ngserver" },
	cssls = { mason = "css-lsp", lang = "CSS", type = "lsp", cmd = "vscode-css-language-server" },
})

M.mason_order = {
	typescript.lsp_server[1],
	"jsonls",
	"biome",
	"eslint",
	"prettierd",
	"prettier",
	"js-debug-adapter",
	"svelte",
	"angularls",
	"cssls",
}

M.bundle_name = "🧩 Web UI (Svelte, Angular, React)"
M.requires = {
	{ cmd = "node", name = "Node.js", hint = "https://nodejs.org" },
}
M.treesitter = { "typescript", "javascript", "tsx", "jsx", "svelte", "html", "scss" }

M.formatters_by_ft = {
	svelte = { "prettierd", "prettier", "biome", stop_after_first = true },
}

M.formatter_configs = {}

local function build_formatter_configs()
	vim.list_extend(M.formatter_configs, typescript.PRETTIER_CONFIG_FILES)
	vim.list_extend(M.formatter_configs, typescript.BIOME_CONFIG_FILES)
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
		pattern = "svelte",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
