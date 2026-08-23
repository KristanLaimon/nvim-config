-- ============================================================================
-- KRS GO: Centralized Go Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard `gofmt` hard-tab indentation defaults (tabs, width 4) for Go buffers
--   when no .editorconfig file specifies buffer settings. Also owns the gopls LSP
--   server and the gofumpt/goimports formatters: settings, Mason names, filetypes.
-- ============================================================================

---@type KrsLangModule
local M = {}

local env_ok, env_mod = pcall(require, "krs.core.environment")
local is_low_resource = false
if env_ok then
	local env = env_mod.detect()
	is_low_resource = env.is_termux or env.is_proot or env.is_mobile
else
	is_low_resource = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
end

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "gopls" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	gopls = {
		cmd_env = is_low_resource and { GOMEMLIMIT = "512MiB" } or nil,
		settings = {
			gopls = {
				codelenses = {
					gc_details = false,
					generate = not is_low_resource,
					regenerate_cgo = not is_low_resource,
					run_govulncheck = not is_low_resource,
					test = true,
					tidy = true,
					upgrade_dependency = not is_low_resource,
					vendor = true,
				},
				hints = is_low_resource and {
					assignVariableTypes = false,
					compositeLiteralFields = false,
					compositeLiteralTypes = false,
					constantValues = false,
					functionTypeParameters = false,
					parameterNames = true,
					rangeVariableTypes = false,
				} or {
					assignVariableTypes = true,
					compositeLiteralFields = true,
					compositeLiteralTypes = true,
					constantValues = true,
					functionTypeParameters = true,
					parameterNames = true,
					rangeVariableTypes = true,
				},
				analyses = {
					unusedparams = true,
					shadow = not is_low_resource,
				},
				staticcheck = not is_low_resource,
				gofumpt = true,
			},
		},
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	gopls = { mason = "gopls", lang = "Go", type = "lsp", cmd = "gopls" },
	gofumpt = { mason = "gofumpt", name = "gofumpt", type = "formatter", cmd = "gofumpt" },
	goimports = { mason = "goimports", name = "goimports", type = "formatter", cmd = "goimports" },
}

M.mason_order = { "gopls", "gofumpt", "goimports" }

--- Language Tooling Manager bundle metadata (see lua/krs/core/installer.lua).
M.bundle_name = "🟦 Go"
M.requires = {
	{ cmd = "go", name = "Go runtime", hint = "https://go.dev/dl" },
}
M.treesitter = { "go", "gomod", "gowork", "gosum" }
--- Extra Mason packages the bundle installs that aren't part of `M.mason`:
--- `delve` is normally installed via mason-nvim-dap (see `M.dap_tool` below),
--- and `golangci-lint` is a standalone linter with no LSP/formatter role.
M.bundle_extra_mason_pkgs = { "delve", "golangci-lint" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	go = is_low_resource and { "gofmt" } or { "goimports", "gofumpt" },
}

--- delve is installed via mason-nvim-dap (nvim-dap-go's own concern), not Mason
--- directly, so it has no `M.mason` entry -- kept here only for documentation.
M.dap_tool = "delve"

--- nvim-dap-go registers the adapter and the standard configurations (debug
--- file, debug test, attach) itself, so there is nothing to add by hand here.
--- @param _ table The `dap` module (unused: dap-go talks to nvim-dap directly).
function M.dap_setup(_)
	local ok, dap_go = pcall(require, "dap-go")
	if ok then
		dap_go.setup()
	end
end

--- Launch-profile runtimes this language owns (see lua/krs/launch/runtimes.lua).
M.launch_runtimes = {
	go = {
		command = "go run",
		dap = function(profile, root, ctx)
			return {
				type = "go",
				request = "launch",
				name = profile.name,
				mode = "debug",
				program = ctx.full_entry,
				cwd = root,
			}
		end,
	},
}

--- Standard `gofmt` defaults for Go (hard tabs, width 4).
M.defaults = {
	expandtab = false,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 0,
	autoindent = true,
}

--- Apply Go language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "krs.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Go language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "go", "gomod", "gowork" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
