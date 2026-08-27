-- ============================================================================
-- KRS PLUGIN: Buffer Cleaner & Smart Quit.
-- ============================================================================
-- WHAT IT DOES
--   1. Smart quit (`<C-q>`, `<leader>q`, and `:q`): closes the smallest sensible
--      thing instead of the whole editor.
--        in the dashboard   -> quit Neovim
--        in neo-tree        -> close the sidebar
--        in a terminal      -> close that window
--        with splits open   -> close the current split
--        last file buffer   -> delete it and land on the dashboard
--   2. Removes empty `[No Name]` buffers once a real file is open.
--   3. Tracks directories that have been opened, for the pickers to offer.
--
-- WHY GLOBAL FUNCTIONS
--   `_G.Neotree_Smart_Quit` / `_G.Smart_Close_Buffer` / `_G.AddOpenedFolder` are
--   called from `cnoreabbrev` (Vimscript, no `require`), from bufferline's close
--   command, and from the terminal plugin. Keep the names.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Filetypes that are UI, not files: they never count as "open work".
	ui_filetypes = { "alpha", "neo-tree" },

	--- Dashboard filetype and the command that opens it.
	dashboard_filetype = "alpha",
	dashboard_command = "Alpha",

	keys = {
		--- Smart quit.
		quit = { "<C-q>" },
	},

	--- Command-line abbreviations rerouted to smart quit. Each maps the bare
	--- command to a `-bang`-aware user command below, so typing `!` after the
	--- abbreviation expands (e.g. `q!` -> `KrsQ!`) instead of being swallowed
	--- by the word-boundary trigger that fires the abbrev in the first place.
	abbreviations = {
		{ lhs = "q", user_cmd = "KrsQ" },
		{ lhs = "bd", user_cmd = "KrsBd" },
		{ lhs = "bdelete", user_cmd = "KrsBd" },
	},
}

--- Directories opened this session, keyed by lowercase path.
_G.OpenedFolders = _G.OpenedFolders or {}

-- ============================================================================
-- HELPERS
-- ============================================================================

--- True when the buffer holds UI rather than a file.
--- @param buf integer
--- @return boolean
local function is_ui_buffer(buf)
	return vim.tbl_contains(M.settings.ui_filetypes, vim.bo[buf].filetype)
end

--- Listed buffers that hold actual work.
--- @return integer[] buffers
local function real_buffers()
	local out = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1 and not is_ui_buffer(buf) then
			table.insert(out, buf)
		end
	end
	return out
end

-- ============================================================================
-- GLOBAL API (called from Vimscript and other plugins)
-- ============================================================================

--- Records a directory as opened, so pickers can offer it later.
--- @param dir_path string|nil
function _G.AddOpenedFolder(dir_path)
	if not dir_path or dir_path == "" then
		return
	end

	local clean = (vim.fn.fnamemodify(dir_path, ":p"):gsub("[/\\]$", ""))
	if vim.fn.isdirectory(clean) == 1 then
		_G.OpenedFolders[clean:lower()] = clean
	end
end

--- Closes one buffer, keeping the editor in a usable state.
--- @param target_buf integer|nil Buffer to close. Defaults to the current one.
--- @param force boolean|nil Discard unsaved changes.
function _G.Smart_Close_Buffer(target_buf, force)
	local cur_buf = vim.api.nvim_get_current_buf()
	target_buf = target_buf or cur_buf

	if not vim.api.nvim_buf_is_valid(target_buf) then
		return
	end

	local ft = vim.bo[target_buf].filetype
	if ft == M.settings.dashboard_filetype then
		vim.cmd(force and "qa!" or "qa")
		return
	end
	if ft == "neo-tree" then
		pcall(vim.cmd, "Neotree close")
		return
	end

	local bname = vim.api.nvim_buf_get_name(target_buf)
	local is_deleted = false
	if bname ~= "" and vim.bo[target_buf].buftype == "" then
		if _G.Is_File_Deleted then
			is_deleted = _G.Is_File_Deleted(target_buf)
		else
			is_deleted = vim.fn.filereadable(bname) == 0 and not vim.fn.isdirectory(bname)
		end
	end

	-- Intercept closing a deleted file buffer when force is false.
	-- Prompts a clean UI confirmation modal (Enter to continue, Esc to cancel) instead of raw Neovim error / `!` prompt.
	if is_deleted and not force then
		local filename = vim.fn.fnamemodify(bname, ":t")
		if filename == "" then
			filename = "buffer #" .. target_buf
		end

		vim.ui.select({
			"🔥 Close deleted file buffer (" .. filename .. ")",
			"❌ Cancel (Keep buffer)",
		}, {
			prompt = "[D] File was deleted from disk. Close buffer?",
			format_item = function(item)
				return item
			end,
		}, function(choice)
			if choice and choice:find("Close") then
				_G.Smart_Close_Buffer(target_buf, true)
			end
		end)
		return
	end

	-- 1. Identify the visually next/prev buffer to land on
	local next_buf = nil
	local has_bl, bl = pcall(require, "bufferline")
	if has_bl and type(bl.get_elements) == "function" then
		local res = bl.get_elements()
		local elements = res and res.elements
		if elements and type(elements) == "table" then
			local idx = nil
			for i, e in ipairs(elements) do
				if e.id == target_buf then
					idx = i
					break
				end
			end
			if idx then
				if idx < #elements then
					next_buf = elements[idx + 1].id
				elseif idx > 1 then
					next_buf = elements[idx - 1].id
				end
			end
		end
	end

	-- Fallback to Neovim's buffer list if bufferline didn't help
	if not next_buf then
		local real = real_buffers()
		for i, b in ipairs(real) do
			if b == target_buf then
				if i < #real then
					next_buf = real[i + 1]
				elseif i > 1 then
					next_buf = real[i - 1]
				end
				break
			end
		end
	end

	-- 2. Switch all windows showing this buffer to the next buffer (or dashboard)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == target_buf then
			if next_buf then
				pcall(vim.api.nvim_win_set_buf, win, next_buf)
			else
				vim.api.nvim_win_call(win, function()
					if not pcall(vim.cmd, M.settings.dashboard_command) then
						pcall(vim.cmd, "enew")
					end
				end)
			end
		end
	end

	-- 3. Delete the buffer
	pcall(vim.api.nvim_buf_delete, target_buf, { force = force or is_deleted })
end

--- Smart quit: closes the smallest sensible thing (see the header for the ladder).
--- @param force boolean|nil Discard unsaved changes.
function _G.Neotree_Smart_Quit(force)
	local cur_buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo[cur_buf].filetype
	local buftype = vim.bo[cur_buf].buftype

	-- Never close/delete neo-tree sidebar when Ctrl+W is pressed inside neo-tree;
	-- shift focus back to code window to preserve UI layout.
	if ft == "neo-tree" or ft == "NvimTree" then
		local target_win = nil
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_is_valid(win) then
				local b = vim.api.nvim_win_get_buf(win)
				local bft = vim.bo[b].filetype
				local btype = vim.bo[b].buftype
				if bft ~= "neo-tree" and bft ~= "NvimTree" and btype == "" then
					target_win = win
					break
				end
			end
		end
		if target_win then
			vim.api.nvim_set_current_win(target_win)
		else
			pcall(vim.cmd, "Neotree close")
		end
		return
	end

	if ft == M.settings.dashboard_filetype then
		vim.cmd(force and "qa!" or "qa")
		return
	end

	-- Do not close terminal if currently in terminal insert mode ('t')
	if buftype == "terminal" then
		if vim.fn.mode() == "t" then
			return
		end
		pcall(vim.cmd, force and "close!" or "close")
		return
	end

	-- More than one code window in this tab: close just that split.
	local code_wins = 0
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) and not is_ui_buffer(vim.api.nvim_win_get_buf(win)) then
			code_wins = code_wins + 1
		end
	end
	if code_wins > 1 then
		pcall(vim.cmd, force and "close!" or "close")
		return
	end

	_G.Smart_Close_Buffer(cur_buf, force)
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

--- Deletes empty, unmodified, invisible `[No Name]` buffers, but only once a real
--- file is open -- otherwise the very first empty buffer would be removed too.
function M.clean_buffers()
	local open_files = 0
	for _, buf in ipairs(real_buffers()) do
		if vim.api.nvim_buf_get_name(buf) ~= "" and vim.bo[buf].buftype == "" then
			open_files = open_files + 1
		end
	end
	if open_files == 0 then
		return
	end

	local visible = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) then
			visible[vim.api.nvim_win_get_buf(win)] = true
		end
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local is_candidate = vim.api.nvim_buf_is_valid(buf)
			and vim.fn.buflisted(buf) == 1
			and vim.api.nvim_buf_get_name(buf) == ""
			and vim.bo[buf].buftype == ""
			and not vim.bo[buf].modified
			and not visible[buf]

		if is_candidate then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Binds the quit keys, the `:q` abbreviations, and the cleanup autocmds.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	_G.AddOpenedFolder(vim.fn.getcwd())

	vim.api.nvim_create_autocmd("DirChanged", {
		group = vim.api.nvim_create_augroup("KRSTrackOpenedFolders", { clear = true }),
		callback = function(ctx)
			_G.AddOpenedFolder((ctx.file and ctx.file ~= "") and ctx.file or vim.fn.getcwd())
		end,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = vim.api.nvim_create_augroup("KRSCleanNoNameBuffers", { clear = true }),
		callback = function()
			vim.schedule(M.clean_buffers)
		end,
	})

	for _, key in ipairs(M.settings.keys.quit) do
		vim.keymap.set("n", key, function()
			_G.Neotree_Smart_Quit(false)
		end, { noremap = true, silent = true, desc = "Close current buffer/tab" })
	end

	vim.api.nvim_create_user_command("KrsQ", function(opts)
		_G.Neotree_Smart_Quit(opts.bang)
	end, { bang = true, desc = "Smart quit (bang = force)" })

	vim.api.nvim_create_user_command("KrsBd", function(opts)
		_G.Smart_Close_Buffer(vim.api.nvim_get_current_buf(), opts.bang)
	end, { bang = true, desc = "Smart close buffer (bang = force)" })

	-- `cnoreabbrev` with a guard, so the reroute only fires for the bare command
	-- (`:q`), never inside something longer like `:qall` or a search for "q".
	-- Only the bare word is remapped; a trailing `!` is left untouched so it
	-- attaches to the expanded user command's own `-bang` handling instead of
	-- being swallowed by the abbrev's word-boundary trigger.
	for _, abbrev in ipairs(M.settings.abbreviations) do
		vim.cmd(
			string.format(
				"cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() ==# '%s') ? '%s' : '%s'",
				abbrev.lhs,
				abbrev.lhs,
				abbrev.user_cmd,
				abbrev.lhs
			)
		)
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.BufferCleaner = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_buffer_cleaner",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VimEnter",
	config = M.setup,
}, { __index = M })
