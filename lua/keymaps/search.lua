-- ============================================================================
-- KEYMAPS: Search -- finding files, opening them in splits, following URLs.
-- ============================================================================
-- KEYS
--   <C-k>            Find files, respecting .gitignore
--   <C-S-/> / <C-?>  Find files, including ignored and hidden ones
--   <C-S-h/j/k/l>    Find a file and open it in a split in that direction
--   <C-LeftMouse>    Open the URL under the mouse in the browser
--
-- SPECIAL CASE
--   While a debug session is running, <C-S-j> toggles the DAP repl instead of
--   opening a split -- the repl is what you want at a breakpoint, and the key is
--   in the same place as the terminal you would otherwise reach for.
-- ============================================================================

local debug_keymaps = require("keymaps.debug")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	keys = {
		--- Fuzzy find, honouring .gitignore.
		find_files = { "<C-k>", "<C-K>" },
		--- Fuzzy find everything, ignored and hidden files included.
		find_all_files = {
			"<C-A-k>",
			"<C-A-K>",
			"<C-M-k>",
			"<C-M-K>",
			"<A-C-k>",
			"<A-C-K>",
			"<M-C-k>",
			"<M-C-K>",
			"<C-S-/>",
			"<C-?>",
		},
		--- Find a file and open it in a split. Direction follows hjkl.
		split = {
			h = { "<C-S-h>", "<C-S-H>" },
			j = { "<C-S-j>", "<C-S-J>" },
			k = { "<C-S-k>", "<C-S-K>" },
			l = { "<C-S-l>", "<C-S-L>" },
		},
		--- Open a URL under the mouse.
		open_url = "<C-LeftMouse>",
	},

	--- Split command per direction, and how each direction is described.
	splits = {
		h = { command = "leftabove vsplit", label = "Left (←)" },
		j = { command = "rightbelow split", label = "Down (↓)" },
		k = { command = "leftabove split", label = "Up (↑)" },
		l = { command = "rightbelow vsplit", label = "Right (→)" },
	},

	--- Matches a URL inside the WORD under the cursor.
	url_pattern = "https?://[^%s\"'<>%)%]]+",
}

-- ============================================================================
-- ACTIONS
-- ============================================================================

--- Opens the file picker; picking a file opens it in a split.
--- @param direction "h"|"j"|"k"|"l"
local function open_find_files_split(direction)
	local ok, builtin = pcall(require, "telescope.builtin")
	if not ok then
		vim.notify("Telescope is not ready", vim.log.levels.ERROR)
		return
	end

	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local split = M.settings.splits[direction]

	builtin.find_files({
		prompt_title = " 🔍 Open File to the " .. (split and split.label or direction) .. " ",
		attach_mappings = function(prompt_bufnr)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)

				local filepath = selection and (selection.value or selection[1])
				if filepath and split then
					vim.cmd(split.command .. " " .. vim.fn.fnameescape(filepath))
				end
			end)
			return true
		end,
	})
end

-- ============================================================================
-- MAPPINGS
-- ============================================================================

--- Standard mapping options, with a description.
local function opts(desc)
	return { noremap = true, silent = true, desc = desc }
end

local function ensure_code_window()
	local ok, dock = pcall(require, "krs.core.dock")
	if not ok then
		return
	end
	local cur_win = vim.api.nvim_get_current_win()
	if not dock.is_code_win(cur_win) then
		local target = dock.find_code_win()
		if target and vim.api.nvim_win_is_valid(target) then
			vim.api.nvim_set_current_win(target)
		else
			pcall(vim.cmd, "wincmd l")
			local new_win = vim.api.nvim_get_current_win()
			if not dock.is_code_win(new_win) then
				pcall(vim.cmd, "vsplit")
				pcall(vim.cmd, "enew")
			end
		end
	end
end

-- The telescope plugin installs `_G.FindFiles*` with the project's own defaults;
-- the fallbacks keep these keys working before it has loaded.
for _, key in ipairs(M.settings.keys.find_files) do
	vim.keymap.set({ "n", "i" }, key, function()
		ensure_code_window()
		if _G.FindFilesGitignore then
			_G.FindFilesGitignore()
		else
			require("telescope.builtin").git_files({ recurse_submodules = true })
		end
	end, opts("Find files (respecting .gitignore)"))
end

for _, key in ipairs(M.settings.keys.find_all_files) do
	vim.keymap.set({ "n", "i" }, key, function()
		ensure_code_window()
		if _G.FindFilesNoIgnore then
			_G.FindFilesNoIgnore()
		else
			require("telescope.builtin").find_files({ no_ignore = true, hidden = true })
		end
	end, opts("Find all files (ignoring .gitignore)"))
end

for direction, keys in pairs(M.settings.keys.split) do
	for _, key in ipairs(keys) do
		vim.keymap.set({ "n", "i", "v" }, key, function()
			-- Downward split doubles as the repl toggle during a debug session.
			if direction == "j" and debug_keymaps.toggle_repl() then
				return
			end
			open_find_files_split(direction)
		end, opts("Find file and open in split (" .. direction .. ")"))
	end
end

vim.keymap.set({ "n", "i", "v", "t" }, M.settings.keys.open_url, function()
	local mouse = vim.fn.getmousepos()
	if mouse.winid == 0 then
		return
	end

	vim.api.nvim_set_current_win(mouse.winid)
	pcall(vim.api.nvim_win_set_cursor, mouse.winid, { mouse.line, math.max(mouse.column - 1, 0) })

	local url = vim.fn.expand("<cWORD>"):match(M.settings.url_pattern)
	if url then
		vim.ui.open(url)
	end
end, opts("Ctrl+Click: open URL under cursor in browser"))

return M
