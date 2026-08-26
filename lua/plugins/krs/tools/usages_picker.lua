-- ============================================================================
-- KRS PLUGIN: Symbol Usage UI Theme Picker.
-- ============================================================================
-- WHAT IT DOES
--   Provides 3 symbol-usage UI formats from the README:
--     1. bubbles (Rounded Pill Badges) [DEFAULT]
--     2. plain   (Clean Text & Separators)
--     3. labels  (Filled Tag Badges)
--   Provides interactive picker command `:KrsUsagesTheme` / `:UsagesThemePicker`.
-- ============================================================================

local store = require("krs.core.store")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.krsnvim/usages_theme.json",
	default_style = "bubbles",
	keymap = nil,
}

M.available_styles = {
	bubbles = "Bubbles (Rounded Pill Badges) [Default]",
	plain = "Plain Text (Clean Text & Separators)",
	labels = "Labels (Filled Tag Badges)",
}

local function h(name)
	return vim.api.nvim_get_hl(0, { name = name })
end

local function setup_bubbles_hl()
	local cursor_line = h("CursorLine").bg or h("NormalFloat").bg or "#2a2e38"
	local comment_fg = h("Comment").fg or "#6c7086"
	local func_fg = h("Function").fg or "#89b4fa"
	local type_fg = h("Type").fg or "#f9e2af"
	local keyword_fg = h("@keyword").fg or h("Keyword").fg or "#cba6f7"

	vim.api.nvim_set_hl(0, "SymbolUsageRounding", { fg = cursor_line, italic = true })
	vim.api.nvim_set_hl(0, "SymbolUsageContent", { bg = cursor_line, fg = comment_fg, italic = true })
	vim.api.nvim_set_hl(0, "SymbolUsageRef", { fg = func_fg, bg = cursor_line, italic = true })
	vim.api.nvim_set_hl(0, "SymbolUsageDef", { fg = type_fg, bg = cursor_line, italic = true })
	vim.api.nvim_set_hl(0, "SymbolUsageImpl", { fg = keyword_fg, bg = cursor_line, italic = true })
end

local function setup_labels_hl()
	local normal_bg = h("Normal").bg or "#1e1e2e"
	local type_fg = h("Type").fg or "#f9e2af"
	local func_fg = h("Function").fg or "#89b4fa"
	local param_fg = h("@parameter").fg or h("Identifier").fg or "#a6e3a1"

	vim.api.nvim_set_hl(0, "SymbolUsageRef", { bg = type_fg, fg = normal_bg, bold = true })
	vim.api.nvim_set_hl(0, "SymbolUsageRefRound", { fg = type_fg })

	vim.api.nvim_set_hl(0, "SymbolUsageDef", { bg = func_fg, fg = normal_bg, bold = true })
	vim.api.nvim_set_hl(0, "SymbolUsageDefRound", { fg = func_fg })

	vim.api.nvim_set_hl(0, "SymbolUsageImpl", { bg = param_fg, fg = normal_bg, bold = true })
	vim.api.nvim_set_hl(0, "SymbolUsageImplRound", { fg = param_fg })
end

M.formatters = {
	bubbles = function(symbol)
		setup_bubbles_hl()
		local res = {}

		local round_start = { "", "SymbolUsageRounding" }
		local round_end = { "", "SymbolUsageRounding" }

		local stacked_functions_content = symbol.stacked_count > 0 and ("+%s"):format(symbol.stacked_count) or ""

		if symbol.references then
			local usage = symbol.references <= 1 and "usage" or "usages"
			local num = symbol.references == 0 and "no" or symbol.references
			table.insert(res, round_start)
			table.insert(res, { "󰌹 ", "SymbolUsageRef" })
			table.insert(res, { ("%s %s"):format(num, usage), "SymbolUsageContent" })
			table.insert(res, round_end)
		end

		if symbol.definition then
			if #res > 0 then
				table.insert(res, { " ", "NonText" })
			end
			table.insert(res, round_start)
			table.insert(res, { "󰳽 ", "SymbolUsageDef" })
			table.insert(res, { symbol.definition .. " defs", "SymbolUsageContent" })
			table.insert(res, round_end)
		end

		if symbol.implementation then
			if #res > 0 then
				table.insert(res, { " ", "NonText" })
			end
			table.insert(res, round_start)
			table.insert(res, { "󰡱 ", "SymbolUsageImpl" })
			table.insert(res, { symbol.implementation .. " impls", "SymbolUsageContent" })
			table.insert(res, round_end)
		end

		if stacked_functions_content ~= "" then
			if #res > 0 then
				table.insert(res, { " ", "NonText" })
			end
			table.insert(res, round_start)
			table.insert(res, { " ", "SymbolUsageImpl" })
			table.insert(res, { stacked_functions_content, "SymbolUsageContent" })
			table.insert(res, round_end)
		end

		return res
	end,

	plain = function(symbol)
		local fragments = {}

		local stacked_functions = symbol.stacked_count > 0 and (" | +%s"):format(symbol.stacked_count) or ""

		if symbol.references then
			local usage = symbol.references <= 1 and "usage" or "usages"
			local num = symbol.references == 0 and "no" or symbol.references
			table.insert(fragments, ("%s %s"):format(num, usage))
		end

		if symbol.definition and symbol.definition > 0 then
			table.insert(fragments, symbol.definition .. " defs")
		end

		if symbol.implementation and symbol.implementation > 0 then
			table.insert(fragments, symbol.implementation .. " impls")
		end

		return table.concat(fragments, ", ") .. stacked_functions
	end,

	labels = function(symbol)
		setup_labels_hl()
		local res = {}

		local stacked_functions_content = symbol.stacked_count > 0 and ("+%s"):format(symbol.stacked_count) or ""

		if symbol.references then
			table.insert(res, { "󰍞", "SymbolUsageRefRound" })
			table.insert(res, { "󰌹 " .. tostring(symbol.references), "SymbolUsageRef" })
			table.insert(res, { "󰍟", "SymbolUsageRefRound" })
		end

		if symbol.definition and symbol.definition > 0 then
			if #res > 0 then
				table.insert(res, { " ", "NonText" })
			end
			table.insert(res, { "󰍞", "SymbolUsageDefRound" })
			table.insert(res, { "󰳽 " .. tostring(symbol.definition), "SymbolUsageDef" })
			table.insert(res, { "󰍟", "SymbolUsageDefRound" })
		end

		if symbol.implementation and symbol.implementation > 0 then
			if #res > 0 then
				table.insert(res, { " ", "NonText" })
			end
			table.insert(res, { "󰍞", "SymbolUsageImplRound" })
			table.insert(res, { "󰡱 " .. tostring(symbol.implementation), "SymbolUsageImpl" })
			table.insert(res, { "󰍟", "SymbolUsageImplRound" })
		end

		if stacked_functions_content ~= "" then
			if #res > 0 then
				table.insert(res, { " ", "NonText" })
			end
			table.insert(res, { "󰍞", "SymbolUsageImplRound" })
			table.insert(res, { " " .. tostring(stacked_functions_content), "SymbolUsageImpl" })
			table.insert(res, { "󰍟", "SymbolUsageImplRound" })
		end

		return res
	end,
}

--- Retrieves current saved usage style choice.
--- @return string style_name
function M.get_current_style()
	local data = store.load(M.settings.store_file, {})
	return data.style or M.settings.default_style
end

--- Gets text format function for current or specified style.
--- @param style_name string|nil
--- @return function text_format
function M.get_text_format(style_name)
	style_name = style_name or M.get_current_style()
	return M.formatters[style_name] or M.formatters[M.settings.default_style]
end

--- Applies style and saves to store.
--- @param style_name string
function M.set_style(style_name)
	if not M.available_styles[style_name] then
		vim.notify("Unknown usages style: " .. tostring(style_name), vim.log.levels.WARN)
		return
	end

	store.save(M.settings.store_file, { style = style_name })
	local ok_su, su = pcall(require, "symbol-usage")
	if ok_su then
		su.setup({
			text_format = M.get_text_format(style_name),
		})
		pcall(su.refresh)
	end
	vim.notify("Usages UI style set to: " .. M.available_styles[style_name], vim.log.levels.INFO)
end

--- Opens interactive usages theme picker.
function M.open_picker()
	local items = {}
	local keys = {}
	for k, label in pairs(M.available_styles) do
		table.insert(keys, k)
		table.insert(items, label)
	end

	local original_style = M.get_current_style()

	local has_telescope, builtin = pcall(require, "telescope.builtin")
	local has_actions, actions = pcall(require, "telescope.actions")
	local has_action_state, action_state = pcall(require, "telescope.actions.state")

	if has_telescope and has_actions and has_action_state then
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values

		pickers
			.new({}, {
				prompt_title = "Usages UI Theme Picker (SymbolUsage)",
				finder = finders.new_table({
					results = items,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					local function preview_selection()
						local selection = action_state.get_selected_entry()
						if selection then
							local idx = selection.index
							if idx and keys[idx] then
								M.set_style(keys[idx])
							end
						end
					end

					map("i", "<Tab>", function()
						actions.move_selection_next(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<S-Tab>", function()
						actions.move_selection_previous(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<Down>", function()
						actions.move_selection_next(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<Up>", function()
						actions.move_selection_previous(prompt_bufnr)
						preview_selection()
					end)

					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection then
							local idx = selection.index
							if idx and keys[idx] then
								M.set_style(keys[idx])
							end
						end
					end)

					return true
				end,
			})
			:find()
	else
		vim.ui.select(items, { prompt = "Select Usages UI Style:" }, function(choice, index)
			if choice and index and keys[index] then
				M.set_style(keys[index])
			else
				M.set_style(original_style)
			end
		end)
	end
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("KrsUsagesTheme", function(opts)
		if opts.args and opts.args ~= "" then
			M.set_style(opts.args)
		else
			M.open_picker()
		end
	end, {
		nargs = "?",
		complete = function()
			local names = {}
			for k in pairs(M.available_styles) do
				table.insert(names, k)
			end
			return names
		end,
		desc = "Pick or set LSP usages UI theme (bubbles, plain, labels)",
	})

	vim.api.nvim_create_user_command("UsagesThemePicker", function()
		M.open_picker()
	end, { desc = "Open Usages UI theme picker" })
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "krs_usages_picker",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "KrsUsagesTheme", "UsagesThemePicker" },
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
