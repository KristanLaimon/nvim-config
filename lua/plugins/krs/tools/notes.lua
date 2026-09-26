-- ============================================================================
-- KRS PLUGIN: Notes Manager -- Quick access to personal notes workspace.
-- ============================================================================
-- WHAT IT DOES
--   1. Provides direct access from the main dashboard (press 'n') to a designated
--      Notes folder on the system, bypassing manual filesystem navigation.
--   2. On first run (or if unset/deleted), prompts via the floating file explorer
--      to select any system folder as the default notes folder.
--   3. Automatically persists the configured folder to Neovim data:
--      `<stdpath("data")>/notes_config.json`.
--   4. Provides a Command Palette command (`:NotesChangeFolder`) to update the
--      notes folder at any time, with built-in validation for unset/missing state.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local path = lazy_req("krs.core.path")

local M = {}

M.config_file = vim.fn.stdpath("data") .. "/notes_config.json"

--- Notifies user with Notes prefix
--- @param msg string
--- @param level integer|nil
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "Notes" })
end

--- Retrieves the configured notes folder if it exists on disk.
--- Returns nil if unset, invalid, or removed.
--- @return string|nil
function M.get_notes_dir()
	local data = store.load(M.config_file, {})
	local folder = data and (data.folder or data.notes_dir or data.path)
	if folder and folder ~= "" then
		local clean = path.normalize(folder)
		if vim.fn.isdirectory(clean) == 1 then
			return clean
		end
	end
	return nil
end

--- Validates and saves the notes folder to persistent storage.
--- @param dir string Directory path
--- @return boolean ok, string message_or_path
function M.set_notes_dir(dir)
	if not dir or dir == "" then
		return false, "Directory path cannot be empty"
	end
	local full = vim.fn.fnamemodify(dir, ":p")
	local clean = path.normalize(full)
	if vim.fn.isdirectory(clean) == 0 then
		return false, "Directory does not exist: " .. clean
	end

	local ok, err = store.save(M.config_file, {
		folder = clean,
		updated_at = os.time(),
	})
	if not ok then
		return false, "Failed to save notes configuration: " .. tostring(err)
	end
	return true, clean
end

--- Clears the configured notes folder (useful for testing or resetting).
--- @return boolean
function M.clear_notes_dir()
	return store.save(M.config_file, {})
end

--- Prompts the user with the file explorer to select a folder as the notes folder.
--- Works reliably whether a notes folder is currently set or not.
--- @param opts? { prompt_title?: string, initial_dir?: string }
--- @param callback? fun(selected_dir: string)
function M.select_notes_folder(opts, callback)
	opts = opts or {}
	local ok_fe, file_explorer = pcall(require, "plugins.krs.tools.file_explorer")
	if not ok_fe then
		notify("File explorer plugin is not available", vim.log.levels.ERROR)
		return
	end

	local current = M.get_notes_dir()
	local start_dir = opts.initial_dir or current
	if not start_dir or vim.fn.isdirectory(start_dir) == 0 then
		if file_explorer.get_desktop_path then
			start_dir = file_explorer.get_desktop_path()
		end
	end
	if not start_dir or vim.fn.isdirectory(start_dir) == 0 then
		start_dir = vim.fn.expand("~")
	end
	if not start_dir or vim.fn.isdirectory(start_dir) == 0 then
		start_dir = vim.fn.getcwd()
	end

	local prompt_title = opts.prompt_title or " 📝 Select Notes Folder (Navigate & press [o] / [Ctrl+O] to choose) "

	file_explorer.open_folder_picker({
		path = start_dir,
		cwd = start_dir,
		prompt_title = prompt_title,
	}, function(chosen_dir)
		if not chosen_dir or chosen_dir == "" then
			return
		end
		local clean = path.normalize(chosen_dir)
		if vim.fn.isdirectory(clean) == 0 then
			notify("Selected path is not a directory: " .. clean, vim.log.levels.WARN)
			return
		end

		if callback then
			callback(clean)
		else
			local ok, res = M.set_notes_dir(clean)
			if ok then
				notify("📝 Notes folder configured:\n" .. res)
				vim.schedule(function()
					M.open_notes()
				end)
			else
				notify(res, vim.log.levels.ERROR)
			end
		end
	end)
end

--- Opens the notes folder in the floating file explorer.
--- Prompts to configure the folder first if not already set or if missing.
function M.open_notes()
	local notes_dir = M.get_notes_dir()
	if not notes_dir then
		notify("Notes folder is not set yet. Please select your notes folder:")
		M.select_notes_folder()
		return
	end

	local ok_fe, file_explorer = pcall(require, "plugins.krs.tools.file_explorer")
	if not ok_fe then
		notify("File explorer plugin is not available", vim.log.levels.ERROR)
		return
	end

	local folder_name = vim.fn.fnamemodify(notes_dir, ":t")
	file_explorer.open_desktop_explorer({
		path = notes_dir,
		prompt_title = string.format(" 📝 Notes (%s): %s ", folder_name, notes_dir),
	})
end

--- Allows changing the notes folder at any time from Command Palette or command line.
--- Validates whether the folder is currently set or unset and continues smoothly.
function M.change_notes_folder()
	local current = M.get_notes_dir()
	if not current then
		notify("No notes folder currently set. Selecting default notes folder:")
	else
		notify("Current notes folder: " .. current .. "\nSelect new folder:")
	end

	M.select_notes_folder({
		prompt_title = " 📝 Change Notes Folder (Navigate & press [o] / [Ctrl+O] to choose) ",
	})
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("Notes", function()
		M.open_notes()
	end, { desc = "Open Notes folder in File Explorer" })

	vim.api.nvim_create_user_command("NotesChangeFolder", function()
		M.change_notes_folder()
	end, { desc = "Change default Notes folder" })

	vim.api.nvim_create_user_command("NotesSetFolder", function(opts)
		if opts.args and vim.trim(opts.args) ~= "" then
			local target = vim.trim(opts.args)
			local ok, res = M.set_notes_dir(target)
			if ok then
				notify("📝 Notes folder set to:\n" .. res)
			else
				notify(res, vim.log.levels.ERROR)
			end
		else
			M.change_notes_folder()
		end
	end, {
		desc = "Set default Notes folder (prompts if no argument)",
		nargs = "?",
		complete = "dir",
	})
end

return setmetatable({
	name = "krs_notes",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "Notes", "NotesChangeFolder", "NotesSetFolder" },
	config = function()
		M.setup()
	end,
}, { __index = M, __newindex = M })
