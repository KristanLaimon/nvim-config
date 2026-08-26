-- ============================================================================
-- PLUGIN: EditorConfig IntelliSense -- diagnostics, hover and completion.
-- ============================================================================
-- WHAT IT DOES
--   `.editorconfig` has no language server, so this file supplies the three
--   things one would give you:
--     * diagnostics -- unknown properties warn, invalid values error,
--     * `K` hover    -- what the property under the cursor means,
--     * completion   -- registered as a blink.cmp source.
--
-- WHERE THE KNOWLEDGE LIVES
--   lua/krs/lsp/editorconfig.lua. Add a property there and all three features
--   pick it up.
-- ============================================================================

local editorconfig = require("krs.lsp.editorconfig")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Diagnostic namespace owned by this checker.
	namespace = vim.api.nvim_create_namespace("editorconfig_intellisense"),

	--- Filetypes and file name treated as EditorConfig.
	filetypes = { "editorconfig", "dosini" },
	filename = ".editorconfig",

	--- Events that re-run validation.
	validate_events = { "BufReadPost", "BufWritePost", "TextChanged", "TextChangedI" },

	--- Hover popup border.
	border = "rounded",
}

-- ============================================================================
-- VALIDATION
-- ============================================================================

--- True when the buffer is an `.editorconfig` file.
--- @param bufnr integer
--- @return boolean
local function is_editorconfig(bufnr)
	local filetype = vim.bo[bufnr].filetype
	local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	return vim.tbl_contains(settings.filetypes, filetype) or name == settings.filename
end

--- Reports unknown properties and invalid values as diagnostics.
--- @param bufnr integer|nil Defaults to the current buffer.
local function validate_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_editorconfig(bufnr) then
		return
	end

	local diagnostics = {}

	for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		local trimmed = vim.trim(line)
		local is_content = trimmed ~= "" and not trimmed:match("^[#;]") and not trimmed:match("^%[.*%]$")

		if is_content then
			local key, value = trimmed:match("^([%w_]+)%s*=?%s*(.-)%s*$")
			if key then
				local known, valid, allowed = editorconfig.validate(key, value)

				if not known then
					table.insert(diagnostics, {
						lnum = index - 1,
						col = 0,
						end_col = #key,
						severity = vim.diagnostic.severity.WARN,
						message = "Unknown EditorConfig property: '" .. key .. "'",
						source = "EditorConfig",
					})
				elseif not valid then
					table.insert(diagnostics, {
						lnum = index - 1,
						col = line:find("=") or 0,
						end_col = #line,
						severity = vim.diagnostic.severity.ERROR,
						message = "Invalid value '" .. value .. "' for '" .. key .. "'. Allowed values: " .. table.concat(
							allowed,
							", "
						),
						source = "EditorConfig",
					})
				end
			end
		end
	end

	vim.diagnostic.set(settings.namespace, bufnr, diagnostics)
end

-- ============================================================================
-- HOVER
-- ============================================================================

--- Documents the property under the cursor, falling back to LSP hover.
--- The word under the cursor is tried first, then the property on the line, so
--- hovering a VALUE still documents its property.
local function show_hover()
	local word = vim.fn.expand("<cword>")
	local property = editorconfig.properties[word]

	if not property then
		local key = vim.api.nvim_get_current_line():match("^%s*([%w_]+)%s*=")
		if key and editorconfig.properties[key] then
			property, word = editorconfig.properties[key], key
		end
	end

	if not property then
		vim.lsp.buf.hover()
		return
	end

	local lines = {
		"# " .. word .. " (EditorConfig)",
		"",
		property.desc,
		"",
		"### Allowed values:",
	}
	for _, value in ipairs(property.values or {}) do
		table.insert(lines, "• `" .. value.label .. "`: " .. value.desc)
	end

	vim.lsp.util.open_floating_preview(lines, "markdown", {
		border = settings.border,
		focus_id = "editorconfig_hover",
	})
end

-- ============================================================================
-- WIRING
-- ============================================================================

vim.filetype.add({ filename = { [settings.filename] = "editorconfig" } })

vim.api.nvim_create_autocmd(settings.validate_events, {
	pattern = { settings.filename, "*" .. settings.filename },
	callback = function(args)
		validate_buffer(args.buf)
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = settings.filetypes,
	callback = function(args)
		validate_buffer(args.buf)
		vim.keymap.set("n", "K", show_hover, { buffer = args.buf, desc = "EditorConfig Hover Documentation" })
	end,
})

return {
	{
		"saghen/blink.cmp",
		opts = function(_, opts)
			opts.sources = opts.sources or {}
			opts.sources.providers = opts.sources.providers or {}

			opts.sources.providers.editorconfig = {
				name = "EditorConfig",
				module = "krs.lsp.editorconfig",
				-- Above the generic buffer/snippet sources: inside .editorconfig
				-- these completions are the only relevant ones.
				score_offset = 100,
				enabled = function()
					return is_editorconfig(vim.api.nvim_get_current_buf())
				end,
			}

			opts.sources.default = opts.sources.default or {}
			if not vim.tbl_contains(opts.sources.default, "editorconfig") then
				table.insert(opts.sources.default, "editorconfig")
			end
		end,
	},
}
