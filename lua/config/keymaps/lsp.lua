-- ============================================================================
-- KEYMAPS: LSP -- documentation, diagnostics, code actions, rename.
-- ============================================================================
-- KEYS
--   K                Hover documentation
--   gK               Diagnostic float at cursor line
--   <C-j>            Signature / parameter help
--   <C-.>            Code actions, in a dropdown at the caret
--   <A-j> / <A-k>    Go to definition (jump back with <C-o>)
--   <F2>             Rename: LSP symbol, neo-tree entry, or the file on disk
--   [d / ]d          Previous / next diagnostic (built-in Neovim)
--   gl               Diagnostic under the cursor (built-in Neovim)
--
-- TERMINAL COMPAT (Termux / xterm / SSH)
--   <C-.> has no standard ASCII escape. In TUI mode we register the raw
--   sequences that xterm-compatible terminals actually send so the action
--   still works across the Termux → Ubuntu → nvim chain.
--   The aliases are only registered when Neovim is NOT running as a GUI
--   (Neovide, gvim, etc.), so desktop behaviour is completely untouched.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	keys = {
		hover = "K",
		signature_help = "<C-j>",
		code_action = "<C-.>",
		goto_definition = { "<A-k>", "<M-k>", "<A-j>", "<M-j>" },
		show_usages = { "<A-S-k>", "<A-S-K>", "<M-S-k>", "<M-S-K>" },
		rename = "<F2>",
		diagnostic_float = "gK",
		diagnostic_prev = nil,
		diagnostic_next = nil,
		format = nil,
	},

	--- Border used by every LSP popup.
	border = "rounded",
}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function opts(desc)
	return { noremap = true, silent = true, desc = desc }
end

--- Language servers attached to the current buffer.
--- @return table[] clients
local function attached_clients()
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	return get_clients({ bufnr = 0 }) or {}
end

-- ============================================================================
-- DOCUMENTATION & DIAGNOSTICS
-- ============================================================================

vim.keymap.set("n", M.settings.keys.hover, function()
	require("plugins.krs.hover_links").show_or_focus_hover()
end, opts("Show or focus hover documentation"))

vim.keymap.set({ "i", "v" }, M.settings.keys.signature_help, function()
	if #attached_clients() == 0 then
		vim.notify("No active LSP for parameter help", vim.log.levels.WARN, { title = "LSP Signature Help" })
		return
	end
	pcall(vim.lsp.buf.signature_help, { border = M.settings.border, focusable = false })
	pcall(vim.lsp.buf.hover, { border = M.settings.border })
end, opts("Show parameter signature help"))

if M.settings.keys.diagnostic_float then
	vim.keymap.set("n", M.settings.keys.diagnostic_float, function()
		vim.diagnostic.open_float({ border = M.settings.border, scope = "cursor", focusable = true })
	end, { desc = "Show diagnostic info" })
end

if M.settings.keys.diagnostic_prev then
	vim.keymap.set("n", M.settings.keys.diagnostic_prev, vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
end
if M.settings.keys.diagnostic_next then
	vim.keymap.set("n", M.settings.keys.diagnostic_next, vim.diagnostic.goto_next, { desc = "Next diagnostic" })
end

if M.settings.keys.format then
	vim.keymap.set({ "n", "v" }, M.settings.keys.format, function()
		require("conform").format({ async = true, lsp_fallback = true })
	end, { desc = "Format file or range" })
end

-- ============================================================================
-- CODE ACTIONS
-- ============================================================================

vim.keymap.set({ "n", "i", "v" }, M.settings.keys.code_action, function()
	require("krs.lsp.code_action_menu").request()
end, opts("Quick Fix / Code Actions (Dropdown at Caret)"))

-- ============================================================================
-- TERMINAL COMPAT: <C-.> aliases for Termux / xterm / SSH (TUI only)
-- ============================================================================
-- In a GUI (Neovide, gvim) the terminal emulation layer is bypassed and
-- <C-.> reaches Neovim directly -- nothing to do there.
--
-- In a plain TUI the key has no standard ASCII code, so different terminals
-- send different raw escape sequences.  We map the two most common ones to
-- the same action so the shortcut works regardless of which terminal is used.
--
-- How to find YOUR terminal's sequence if neither works:
--   1. Inside nvim insert-mode, press Ctrl-V then Ctrl-.
--   2. Whatever appears (e.g. ^[. or ^[[46;5u) is the sequence to map.
--   3. Add it below following the same pattern.
if not vim.g.neovide and vim.fn.has("gui_running") == 0 then
	local code_action_fn = function()
		require("krs.lsp.code_action_menu").request()
	end

	-- CSI-u (Kitty Keyboard Protocol) — sent by Kitty, foot, WezTerm, and
	-- newer xterm / Termux when the protocol is active: ESC [ 46 ; 5 u
	vim.keymap.set({ "n", "i", "v" }, "\x1b[46;5u", code_action_fn, opts("Quick Fix / Code Actions (TUI CSI-u alias)"))

	-- Legacy xterm / Termux fallback: ESC followed by literal '.'
	-- (many xterm-256color builds send this for Ctrl+.)
	vim.keymap.set({ "n", "i", "v" }, "\x1b.", code_action_fn, opts("Quick Fix / Code Actions (TUI xterm alias)"))
end

-- ============================================================================
-- NAVIGATION
-- ============================================================================

--- Jumps to the definition under the cursor.
--- If only 1 definition result is found, it goes straight to it.
--- If 2 or more results are found, it opens Telescope lsp_definitions picker.
local function goto_definition()
	vim.cmd("normal! m'")

	if #attached_clients() == 0 then
		-- No LSP: fall back to the built-in tag jump (<C-]>).
		if not pcall(vim.cmd, "normal! \x1d") then
			vim.notify("No definition found", vim.log.levels.WARN, { title = "LSP" })
		end
		return
	end

	local has_telescope, builtin = pcall(require, "telescope.builtin")

	local status, err = pcall(function()
		vim.lsp.buf.definition({
			on_list = function(options)
				if not options or not options.items or #options.items == 0 then
					vim.notify("No definition found", vim.log.levels.WARN, { title = "LSP" })
					return
				end

				if #options.items == 1 then
					local item = options.items[1]
					if item.filename and item.filename ~= "" then
						if item.filename ~= vim.api.nvim_buf_get_name(0) then
							if vim.bo.modified then
								vim.cmd("split " .. vim.fn.fnameescape(item.filename))
							else
								vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
							end
						end
						pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, math.max(0, item.col - 1) })
					end
				else
					if has_telescope then
						builtin.lsp_definitions({ reuse_win = true, show_line = true })
					else
						vim.lsp.buf.definition()
					end
				end
			end,
		})
	end)

	if not status then
		if has_telescope then
			builtin.lsp_definitions({ reuse_win = true, show_line = true })
		else
			vim.lsp.buf.definition()
		end
	end
end

M.goto_definition = goto_definition

--- Handles Shift + Left Click: moves cursor to mouse position and follows link (if on a link) or jumps to definition.
local function goto_definition_at_mouse()
	local mouse_pos = vim.fn.getmousepos()
	if mouse_pos and mouse_pos.winid > 0 and vim.api.nvim_win_is_valid(mouse_pos.winid) then
		vim.api.nvim_set_current_win(mouse_pos.winid)
		pcall(vim.api.nvim_win_set_cursor, mouse_pos.winid, { mouse_pos.line, math.max(0, mouse_pos.column - 1) })
	end

	local ok, hover_links = pcall(require, "plugins.krs.hover_links")
	if ok and hover_links.follow_link_at_cursor then
		local handled = hover_links.follow_link_at_cursor()
		if handled then
			return
		end
	end

	goto_definition()
end

M.goto_definition_at_mouse = goto_definition_at_mouse

for _, key in ipairs(M.settings.keys.goto_definition) do
	vim.keymap.set({ "n", "i", "v" }, key, goto_definition, opts("Go to definition"))
end

--- Shows all usages/references of the symbol under the cursor.
--- If references are found, opens Telescope lsp_references picker.
--- If no usages are found, displays a toast notification.
local function show_symbol_usages()
	local symbol = vim.fn.expand("<cword>")
	if not symbol or symbol == "" then
		vim.notify("No symbol under cursor", vim.log.levels.WARN, { title = "LSP Usages" })
		return
	end

	local symbol_label = "'" .. symbol .. "'"
	local clients = attached_clients()
	if #clients == 0 then
		vim.notify("No usages found for " .. symbol_label, vim.log.levels.INFO, { title = "LSP Usages" })
		return
	end

	local supports_ref = false
	for _, client in ipairs(clients) do
		if client:supports_method("textDocument/references") then
			supports_ref = true
			break
		end
	end

	if not supports_ref then
		vim.notify("No usages found for " .. symbol_label, vim.log.levels.INFO, { title = "LSP Usages" })
		return
	end

	local has_telescope, builtin = pcall(require, "telescope.builtin")

	local status, err = pcall(function()
		vim.lsp.buf.references(nil, {
			on_list = function(options)
				if not options or not options.items or #options.items == 0 then
					vim.notify("No usages found for " .. symbol_label, vim.log.levels.INFO, { title = "LSP Usages" })
					return
				end

				if has_telescope then
					builtin.lsp_references({
						include_declaration = true,
						show_line = true,
						prompt_title = "Usages of " .. symbol_label,
					})
				else
					vim.fn.setqflist({}, " ", options)
					vim.cmd("copen")
				end
			end,
		})
	end)

	if not status then
		vim.notify("No usages found for " .. symbol_label, vim.log.levels.INFO, { title = "LSP Usages" })
	end
end

M.show_symbol_usages = show_symbol_usages

for _, key in ipairs(M.settings.keys.show_usages) do
	vim.keymap.set({ "n", "i", "v" }, key, show_symbol_usages, opts("Show symbol usages"))
end

vim.keymap.set({ "n", "i", "v" }, "<S-LeftMouse>", goto_definition_at_mouse, opts("Shift + Click: Go to definition"))

-- ============================================================================
-- RENAME
-- ============================================================================

--- Renames a file on disk and reopens it under the new name.
--- @param old_path string Absolute path of the current file.
local function rename_file(old_path)
	local dir = vim.fn.fnamemodify(old_path, ":h")
	local old_name = vim.fn.fnamemodify(old_path, ":t")

	require("plugins.krs.input_modal").open({
		label = "Rename File",
		default_value = old_name,
		relative = "editor",
		callback = function(ok, new_name)
			if not ok or not new_name or new_name == "" or new_name == old_name then
				return
			end

			local new_path = dir .. "/" .. new_name
			if vim.fn.filereadable(new_path) == 1 then
				vim.notify("File already exists: " .. new_path, vim.log.levels.ERROR)
				return
			end

			vim.cmd("write")
			local renamed, err = os.rename(old_path, new_path)
			if not renamed then
				vim.notify("Error renaming file: " .. tostring(err), vim.log.levels.ERROR)
				return
			end

			require("krs.core.buffer_rename").update_buffers_path(old_path, new_path)
			vim.notify("Renamed file: " .. old_name .. " ➜ " .. new_name, vim.log.levels.INFO)
		end,
	})
end

--- Renames the symbol under the cursor through the LSP.
--- @param old_name string Current symbol name.
local function rename_symbol(old_name)
	require("plugins.krs.input_modal").open({
		label = "LSP Rename",
		default_value = old_name,
		relative = "cursor",
		callback = function(ok, new_name)
			if ok and new_name and new_name ~= "" and new_name ~= old_name then
				vim.lsp.buf.rename(new_name)
			end
		end,
	})
end

--- F2 means "rename this", and what "this" is depends on where you are:
--- a neo-tree entry, a symbol with LSP rename support, or the file itself.
vim.keymap.set("n", M.settings.keys.rename, function()
	if vim.bo.filetype == "neo-tree" then
		vim.api.nvim_feedkeys("r", "m", false)
		return
	end

	for _, client in ipairs(attached_clients()) do
		if client:supports_method("textDocument/rename") then
			local symbol = vim.fn.expand("<cword>")
			if symbol ~= "" then
				rename_symbol(symbol)
			end
			return
		end
	end

	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		vim.notify("Buffer has no file, cannot rename", vim.log.levels.WARN)
		return
	end
	rename_file(path)
end, opts("Rename symbol or file"))

return M
