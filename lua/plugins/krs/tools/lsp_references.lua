-- ============================================================================
-- KRS PLUGIN: LSP Function & Class Reference Counter (CodeLens).
-- ============================================================================
-- WHAT IT DOES
--   Displays LSP reference counts (e.g. "󰌹 3 references", "1 reference") above
--   functions, methods, classes, and structs across all supported languages.
--   Provides a toggle command `:KrsToggleReferences` (default: ON).
-- ============================================================================

local store = require("krs.core.store")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.krsnvim/references.json",
	default_enabled = true,
	keymap = nil,
}

--- Retrieves current toggle state from persistence store.
--- @return boolean enabled
function M.is_enabled()
	local data = store.load(M.settings.store_file, {})
	if data.enabled ~= nil then
		return data.enabled
	end
	return M.settings.default_enabled
end

--- Refreshes LSP code lenses in the active buffer.
--- @param bufnr number|nil
function M.refresh(bufnr)
	if not M.is_enabled() then
		return
	end

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
		return
	end

	local clients = (vim.lsp.get_clients or vim.lsp.get_active_clients)({ bufnr = bufnr })
	if #clients == 0 then
		return
	end

	local has_codelens = false
	for _, client in ipairs(clients) do
		if client:supports_method("textDocument/codeLens") then
			has_codelens = true
			break
		end
	end

	if has_codelens and vim.lsp.codelens then
		pcall(vim.lsp.codelens.refresh, { bufnr = bufnr })
	end
end

--- Clears all LSP code lenses from active buffer.
--- @param bufnr number|nil
function M.clear(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.lsp.codelens then
		pcall(vim.lsp.codelens.clear, nil, bufnr)
	end
end

--- Toggles LSP reference counts on or off.
function M.toggle()
	local new_state = not M.is_enabled()
	store.save(M.settings.store_file, { enabled = new_state })

	local ok_su, su = pcall(require, "symbol-usage")
	if ok_su and su.toggle_globally then
		pcall(su.toggle_globally)
	end

	if new_state then
		vim.notify("LSP Reference Counts: ENABLED", vim.log.levels.INFO, { title = "LSP CodeLens" })
		M.refresh(0)
	else
		vim.notify("LSP Reference Counts: DISABLED", vim.log.levels.WARN, { title = "LSP CodeLens" })
		M.clear(0)
	end
end

--- Runs code lens under cursor or opens references list.
function M.run()
	if vim.lsp.codelens then
		pcall(vim.lsp.codelens.run)
	end
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup("KRS_LSP_References", { clear = true })

	vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "BufWritePost", "InsertLeave" }, {
		group = group,
		callback = function(args)
			if M.is_enabled() then
				vim.schedule(function()
					M.refresh(args.buf)
				end)
			end
		end,
	})

	vim.api.nvim_create_user_command("KrsToggleReferences", function()
		M.toggle()
	end, { desc = "Toggle LSP Reference Counts / CodeLens display" })

	vim.api.nvim_create_user_command("KrsRunCodeLens", function()
		M.run()
	end, { desc = "Run LSP CodeLens / References under cursor" })

	if M.settings.keymap then
		vim.keymap.set("n", M.settings.keymap, M.toggle, { desc = "Toggle LSP Reference Counts" })
	end
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "krs_lsp_references",
	dir = require("krs.core.lazyspec").for_module(),
	event = { "LspAttach" },
	cmd = { "KrsToggleReferences", "KrsRunCodeLens" },
	keys = {},
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
