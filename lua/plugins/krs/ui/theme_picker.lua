-- ============================================================================
-- KRS PLUGIN: Nagatoro Theme System & Interactive Theme Picker.
-- ============================================================================
-- WHAT IT DOES
--   Discovers all themes formatted for nagatoro-krs (nagatoro-krs, nagatoro-light,
--   onedark-krs, catppuccin-krs, nord-krs), previews them live in Telescope or
--   vim.ui.select, and persists choice in .krsnvim/theme.json.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.krsnvim/theme.json",
	default_theme = "nagatoro-krs",
	keymap = nil,
}

--- Scans colors/ directory for available nagatoro-krs formatted themes.
--- @return string[] theme_names
function M.discover_themes()
	local themes = {}
	local colors_dir = vim.fn.stdpath("config") .. "/colors"
	local files = vim.fn.globpath(colors_dir, "*.lua", false, true)

	for _, file in ipairs(files) do
		local name = vim.fn.fnamemodify(file, ":t:r")
		if name:match("%-krs$") or name:match("^nagatoro%-") then
			table.insert(themes, name)
		end
	end

	table.sort(themes)
	if #themes == 0 then
		table.insert(themes, M.settings.default_theme)
	end

	return themes
end

--- Gets currently saved theme.
--- @return string theme_name
function M.get_current_theme()
	local data = store.load(M.settings.store_file, {})
	return data.theme or vim.g.colors_name or M.settings.default_theme
end

--- Applies colorscheme and saves to store.
--- @param name string
function M.set_theme(name)
	if not name or name == "" then
		return
	end
	local ok, err = pcall(vim.cmd.colorscheme, name)
	if ok then
		store.save(M.settings.store_file, { theme = name })
		vim.notify("Applied colorscheme: " .. name, vim.log.levels.INFO)
	else
		vim.notify("Failed to apply theme " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Restores persisted theme on startup.
function M.restore_saved_theme()
	local saved = M.get_current_theme()
	if saved then
		pcall(vim.cmd.colorscheme, saved)
	end
end

--- Opens interactive theme picker with live preview.
function M.open_picker()
	local themes = M.discover_themes()
	local original_theme = vim.g.colors_name or M.settings.default_theme

	local has_telescope, builtin = pcall(require, "telescope.builtin")
	local has_actions, actions = pcall(require, "telescope.actions")
	local has_action_state, action_state = pcall(require, "telescope.actions.state")

	if has_telescope and has_actions and has_action_state then
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values

		pickers
			.new({}, {
				prompt_title = "Nagatoro Themes",
				finder = finders.new_table({ results = themes }),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					local function preview_selection()
						local selection = action_state.get_selected_entry()
						if selection and selection[1] then
							pcall(vim.cmd.colorscheme, selection[1])
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
						if selection and selection[1] then
							M.set_theme(selection[1])
						end
					end)

					return true
				end,
			})
			:find()
	else
		vim.ui.select(themes, { prompt = "Select Nagatoro Theme:" }, function(choice)
			if choice then
				M.set_theme(choice)
			else
				pcall(vim.cmd.colorscheme, original_theme)
			end
		end)
	end
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("KrsThemePicker", function(opts)
		if opts.args and opts.args ~= "" then
			M.set_theme(opts.args)
		else
			M.open_picker()
		end
	end, {
		nargs = "?",
		complete = function()
			return M.discover_themes()
		end,
		desc = "Open Nagatoro theme picker",
	})

	if M.settings.keymap then
		vim.keymap.set("n", M.settings.keymap, M.open_picker, { desc = "Theme Picker (Nagatoro Format)" })
	end
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "krs_theme_picker",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = "KrsThemePicker",
	keys = {},
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
