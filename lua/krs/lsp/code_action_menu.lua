-- ============================================================================
-- krs.lsp.code_action_menu -- VSCode-style code action dropdown at the caret.
-- ============================================================================
-- WHAT IT IS
--   A `vim.ui.select` replacement anchored to the CURSOR rather than the bottom
--   of the screen, used for LSP code actions (`<C-.>`). Actions are re-ordered so
--   the useful ones come first: preferred actions, then quickfixes, then
--   refactors, then whole-file sources -- raw LSP order is close to arbitrary.
--
-- USAGE
--   local menu = require("krs.lsp.code_action_menu")
--   menu.select(items, opts, on_choice)   -- same signature as vim.ui.select
--   menu.request()                        -- ask the LSP and show the menu
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Lower sorts first. Anything unlisted goes last.
	kind_priority = {
		quickfix = 1,
		["refactor.rewrite"] = 2,
		refactor = 3,
		["source.fixAll"] = 4,
		["source.organizeImports"] = 5,
		source = 6,
	},

	--- Width limits of the dropdown, in cells.
	min_width = 40,
	max_width = 85,

	--- Border and title decoration.
	border = "rounded",
	title_icon = "💡",

	--- How many entries get a number shortcut.
	max_number_shortcuts = 9,

	--- Notification title.
	notify_title = "LSP Code Actions",
}

-- ============================================================================
-- SORTING
-- ============================================================================

--- Sorts code actions into the order described at the top of this file.
--- The original index breaks ties, so the sort is stable.
---
--- @param items table[] Items as passed to `vim.ui.select`.
--- @return table[] sorted
function M.sort_items(items)
	local order = {}
	for index in ipairs(items) do
		order[index] = index
	end

	table.sort(order, function(a, b)
		local action_a = items[a].action or items[a]
		local action_b = items[b].action or items[b]

		local preferred_a = action_a.isPreferred and 0 or 1
		local preferred_b = action_b.isPreferred and 0 or 1
		if preferred_a ~= preferred_b then
			return preferred_a < preferred_b
		end

		local kind_a = M.settings.kind_priority[action_a.kind] or 99
		local kind_b = M.settings.kind_priority[action_b.kind] or 99
		if kind_a ~= kind_b then
			return kind_a < kind_b
		end
		return a < b
	end)

	local sorted = {}
	for position, index in ipairs(order) do
		sorted[position] = items[index]
	end
	return sorted
end

-- ============================================================================
-- MENU
-- ============================================================================

--- Shows the dropdown. Drop-in replacement for `vim.ui.select`.
---
--- @param items table[] Selectable items.
--- @param opts table|nil `{ prompt = string, format_item = fun(item): string }`
--- @param on_choice fun(item: any|nil, index: integer|nil)
function M.select(items, opts, on_choice)
	opts = opts or {}
	local prompt = (opts.prompt or "Available Code Actions:"):gsub("^%s*", ""):gsub("%s*$", "")

	items = M.sort_items(items)

	local labels = {}
	for index, item in ipairs(items) do
		local text = opts.format_item and opts.format_item(item) or tostring(item)
		text = text:gsub("[\r\n]+", " ")
		table.insert(labels, string.format("%d. %s", index, text))
	end

	if #labels == 0 then
		vim.notify("No code suggestions available here", vim.log.levels.INFO, { title = M.settings.notify_title })
		return
	end

	local width = #prompt + 6
	for _, label in ipairs(labels) do
		width = math.max(width, #label)
	end
	width = math.min(math.max(width + 4, M.settings.min_width), M.settings.max_width)

	-- Two header lines sit above the entries, so entry N is on buffer line N + 2.
	local header_lines = 2
	local lines = { " " .. M.settings.title_icon .. " " .. prompt, string.rep("─", width - 2) }
	for _, label in ipairs(labels) do
		table.insert(lines, "  " .. label)
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = #lines,
		style = "minimal",
		border = M.settings.border,
	})
	pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = win })

	local selected = 1

	--- Moves the highlight, clamped to the list.
	local function focus(index)
		selected = math.max(1, math.min(#labels, index))
		pcall(vim.api.nvim_win_set_cursor, win, { selected + header_lines, 2 })
	end
	focus(1)

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	--- Runs the focused action. The cursor wins over `selected`, so moving with
	--- `j`/`k` or the mouse and pressing <CR> picks what is highlighted.
	local function confirm()
		local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
		if ok then
			local index = cursor[1] - header_lines
			if index >= 1 and index <= #items then
				selected = index
			end
		end

		close()
		if on_choice and items[selected] then
			on_choice(items[selected], selected)
		end
	end

	local function cancel()
		close()
		if on_choice then
			on_choice(nil, nil)
		end
	end

	local kopts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("n", "<CR>", confirm, kopts)

	for _, key in ipairs({ "j", "<Down>" }) do
		vim.keymap.set("n", key, function()
			focus(selected + 1)
		end, kopts)
	end
	for _, key in ipairs({ "k", "<Up>" }) do
		vim.keymap.set("n", key, function()
			focus(selected - 1)
		end, kopts)
	end
	for _, key in ipairs({ "<Esc>", "q" }) do
		vim.keymap.set("n", key, cancel, kopts)
	end

	for index = 1, math.min(M.settings.max_number_shortcuts, #labels) do
		vim.keymap.set("n", tostring(index), function()
			selected = index
			confirm()
		end, kopts)
	end
end

--- Requests code actions from the attached LSP and shows them in this menu.
--- `vim.ui.select` is swapped for exactly one call, then restored.
function M.request()
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	local clients = get_clients({ bufnr = 0 })

	if not clients or #clients == 0 then
		vim.notify("No active LSP server for this file", vim.log.levels.WARN, { title = M.settings.notify_title })
		return
	end

	local original_select = vim.ui.select
	vim.ui.select = function(items, opts, on_choice)
		vim.ui.select = original_select
		if not items or #items == 0 then
			vim.notify(
				"No suggestions or code actions available here",
				vim.log.levels.INFO,
				{ title = M.settings.notify_title }
			)
			return
		end
		M.select(items, opts, on_choice)
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 1
	local line_diags = vim.diagnostic.get(bufnr, { lnum = cur_line })

	local lsp_diags = {}
	for _, item in ipairs(line_diags) do
		if item.user_data and item.user_data.lsp then
			table.insert(lsp_diags, item.user_data.lsp)
		else
			table.insert(lsp_diags, {
				range = {
					start = { line = item.lnum, character = item.col },
					["end"] = { line = item.end_lnum or item.lnum, character = item.end_col or item.col },
				},
				severity = item.severity,
				code = item.code,
				source = item.source,
				message = item.message,
			})
		end
	end

	if #lsp_diags > 0 then
		pcall(vim.lsp.buf.code_action, { context = { diagnostics = lsp_diags } })
	else
		pcall(vim.lsp.buf.code_action)
	end
end

return M
