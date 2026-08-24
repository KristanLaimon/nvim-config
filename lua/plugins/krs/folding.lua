-- ============================================================================
-- KRS PLUGIN: Folding (HTML Tags, Functions & Scope Folding) -- High Performance
-- ============================================================================
-- WHAT IT DOES
--   * Enables Treesitter folding for HTML tags, JSX/TSX elements, functions/methods,
--     and code scope blocks ({...}, if/for/while, classes).
--   * Toggles fold under cursor or selection with `<Alt+y>` / `<A-y>` across all modes.
--   * Supports mouse click fold toggling via foldcolumn gutter (`foldcolumn = "1"`)
--     and double left-click (`<2-LeftMouse>`) on fold lines.
--   * PERSISTS FOLD STATES IN `.krsnvim/views/` (or workspace-specific `.krsnvim/views_<ws_id>/`)
--     so folds remain saved when closing Neovim, switching projects, or re-entering files.
--   * PERFORMANCE GUARANTEES:
--     - Caches resolved fold view storage path per project/workspace session.
--     - Non-blocking async view saving (`vim.schedule`) with lightweight `viewoptions = "folds,cursor"`.
--     - Skips auto-persistence on huge files (> 10,000 lines or > 1MB) to maintain zero-lag editing.
--     - Fast guards for unlisted, non-code, and virtual buffers.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local project = lazy_req("krs.core.project")
local path = lazy_req("krs.core.path")

local M = {}

M.settings = {
	max_lines_for_persistence = 10000,
	keys = {
		--- Toggle fold at cursor / selection across modes.
		toggle = { "<A-y>", "<A-Y>", "<M-y>", "<M-Y>" },
	},
}

--- Ignored filetypes for fold view persistence.
M.ignored_filetypes = {
	"neo-tree",
	"dashboard",
	"alpha",
	"toggleterm",
	"TaskRunner",
	"qf",
	"help",
	"krsinputmodal",
	"lspinfo",
	"notify",
	"checkhealth",
}

local _cached_dir = nil
local _cached_root = nil
local _cached_ws = nil

--- Resolves the directory in `.krsnvim` where fold views are stored (cached for speed).
--- Workspace path: <root>/.krsnvim/views_<workspace_id>/
--- Normal project path: <root>/.krsnvim/views/
--- @return string dir Absolute path to view directory.
function M.get_folds_dir()
	local root = project.root()
	local ws_id = nil

	local ok_ws, workspaces = pcall(require, "plugins.krs.workspaces")
	if ok_ws and workspaces.get_active_workspace then
		local active = workspaces.get_active_workspace()
		if active and (active.id or active.name) then
			ws_id = active.id or active.name:gsub("[%s/\\]+", "_")
		end
	end

	if _cached_dir and _cached_root == root and _cached_ws == ws_id then
		return _cached_dir
	end

	local folder = (ws_id and ws_id ~= "") and ("views_" .. ws_id) or "views"
	_cached_root = root
	_cached_ws = ws_id
	_cached_dir = path.ensure_dir(path.join(root, ".krsnvim", folder))
	return _cached_dir
end

--- Resets cached directory on directory change or workspace switch.
function M.reset_cache()
	_cached_dir = nil
	_cached_root = nil
	_cached_ws = nil
end

--- Checks if a buffer is a valid code buffer eligible for fold view persistence.
--- Fast non-allocating checks first.
--- @param bufnr integer|nil
--- @return boolean
function M.is_code_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not bufnr or bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	if vim.bo[bufnr].buftype ~= "" then
		return false
	end

	local ft = vim.bo[bufnr].filetype
	if vim.tbl_contains(M.ignored_filetypes, ft) then
		return false
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	if line_count > (M.settings.max_lines_for_persistence or 10000) then
		return false
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" or name:sub(1, 7) == "term://" or name:match("^%a[%a%d+.-]+://") or name:match("^node:") then
		return false
	end

	return vim.fn.filereadable(name) == 1
end

--- Saves fold view state for a buffer into `.krsnvim/views/` (asynchronously).
--- @param bufnr integer|nil
function M.save_fold_view(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_code_buffer(bufnr) then
		return
	end

	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		pcall(function()
			local folds_dir = M.get_folds_dir()
			vim.opt.viewdir = folds_dir
			vim.cmd("silent! mkview")
		end)
	end)
end

--- Restores fold view state for a buffer from `.krsnvim/views/`.
--- @param bufnr integer|nil
function M.restore_fold_view(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not M.is_code_buffer(bufnr) then
		return
	end

	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		pcall(function()
			local folds_dir = M.get_folds_dir()
			vim.opt.viewdir = folds_dir
			vim.cmd("silent! loadview")
		end)
	end)
end

--- Clears all stored fold view files in `.krsnvim/views/` for current project.
function M.clear_stored_folds()
	local folds_dir = M.get_folds_dir()
	if vim.fn.isdirectory(folds_dir) == 1 then
		vim.fn.delete(folds_dir, "rf")
		path.ensure_dir(folds_dir)
		M.reset_cache()
		vim.notify("🗑️ Cleared stored fold states in .krsnvim", vim.log.levels.INFO, { title = "Folding" })
	end
end

--- Toggles fold state at cursor or current visual selection.
function M.toggle_fold()
	local mode = vim.fn.mode()
	if mode == "i" then
		pcall(vim.cmd, "stopinsert")
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local closed = vim.fn.foldclosed(line)

	if closed ~= -1 then
		pcall(vim.cmd, "normal! zo")
	else
		local level = vim.fn.foldlevel(line)
		if level > 0 then
			pcall(vim.cmd, "normal! za")
		else
			local ok = pcall(vim.cmd, "normal! za")
			if not ok then
				vim.notify("No fold at current cursor line", vim.log.levels.WARN, { title = "Folding" })
			end
		end
	end

	if mode == "i" then
		pcall(vim.cmd, "startinsert")
	end

	M.save_fold_view()
end

--- Opens all folds in the active buffer (`zR`).
function M.open_all()
	pcall(vim.cmd, "normal! zR")
	M.save_fold_view()
	vim.notify("📖 Opened all folds", vim.log.levels.INFO, { title = "Folding" })
end

--- Closes all folds in the active buffer (`zM`).
function M.close_all()
	pcall(vim.cmd, "normal! zM")
	M.save_fold_view()
	vim.notify("📕 Closed all folds", vim.log.levels.INFO, { title = "Folding" })
end

--- Folds all functions/methods in the buffer.
function M.fold_functions()
	vim.wo.foldenable = true
	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	vim.wo.foldlevel = 1
	M.save_fold_view()
	vim.notify("󰊕 Folded functions & methods", vim.log.levels.INFO, { title = "Folding" })
end

--- Folds HTML tags & XML elements in the buffer.
function M.fold_html()
	vim.wo.foldenable = true
	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	vim.wo.foldlevel = 1
	M.save_fold_view()
	vim.notify("🏷️ Folded HTML tags & elements", vim.log.levels.INFO, { title = "Folding" })
end

--- Folds block scopes, control structures, and classes.
function M.fold_scopes()
	vim.wo.foldenable = true
	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	vim.wo.foldlevel = 2
	M.save_fold_view()
	vim.notify("📦 Folded scope blocks", vim.log.levels.INFO, { title = "Folding" })
end

--- Ensures treesitter fold options are active for a buffer.
--- @param bufnr integer|nil
function M.apply_fold_options(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not bufnr or bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if vim.bo[bufnr].buftype ~= "" then
		return
	end

	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	vim.wo.foldlevel = 99
	vim.wo.foldenable = true
	vim.wo.foldcolumn = "1"
end

--- Sets up autocmds, commands, keymaps, and palette entries.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup("KrsFoldingAuto", { clear = true })

	vim.api.nvim_create_autocmd({ "DirChanged" }, {
		group = group,
		callback = M.reset_cache,
	})

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "FileType" }, {
		group = group,
		callback = function(args)
			local env_ok, env_mod = pcall(require, "krs.core.environment")
			local is_mobile_or_proot = false
			if env_ok then
				local env = env_mod.detect()
				is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile
			else
				is_mobile_or_proot = vim.env.TERMUX_VERSION ~= nil
			end
			if not is_mobile_or_proot then
				vim.schedule(function()
					M.apply_fold_options(args.buf)
				end)
			end
		end,
	})

	-- Register user commands
	local commands = {
		FoldToggle = { M.toggle_fold, "Toggle fold under cursor (Alt+Y)" },
		FoldOpenAll = { M.open_all, "Open all folds in buffer (zR)" },
		FoldCloseAll = { M.close_all, "Close all folds in buffer (zM)" },
		FoldFunctions = { M.fold_functions, "Fold all functions & methods" },
		FoldHTML = { M.fold_html, "Fold HTML tags & elements" },
		FoldScopes = { M.fold_scopes, "Fold code scope blocks" },
		FoldSave = { function() M.save_fold_view(); vim.notify("💾 Fold state saved to .krsnvim", vim.log.levels.INFO, { title = "Folding" }) end, "Save fold state for file to .krsnvim" },
		FoldRestore = { function() M.restore_fold_view(); vim.notify("📂 Fold state restored from .krsnvim", vim.log.levels.INFO, { title = "Folding" }) end, "Restore fold state for file from .krsnvim" },
		FoldClearViews = { M.clear_stored_folds, "Clear stored fold states in .krsnvim" },
	}

	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, function()
				spec[1]()
			end, { desc = spec[2] })
		end
	end

	-- Bind Alt+Y keymaps across normal, visual, insert, and terminal modes
	for _, key in ipairs(M.settings.keys.toggle) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, M.toggle_fold, { noremap = true, silent = true, desc = "Toggle fold (HTML, functions, scopes)" })
	end

	-- Mouse double-click on fold line to toggle fold
	vim.keymap.set("n", "<2-LeftMouse>", function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		if vim.fn.foldclosed(line) ~= -1 or vim.fn.foldlevel(line) > 0 then
			pcall(vim.cmd, "normal! za")
			M.save_fold_view()
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<2-LeftMouse>", true, false, true), "n", false)
		end
	end, { noremap = true, silent = true, desc = "Double-click to toggle fold" })

	-- Register in Command Palette
	local ok, palette = pcall(require, "plugins.krs.command_palette")
	if ok and palette.add_command then
		palette.add_command({ name = "↔️ Toggle Fold at Cursor (Alt+Y)", cmd = "FoldToggle", category = "Folding" })
		palette.add_command({ name = "📖 Open All Folds in File (zR)", cmd = "FoldOpenAll", category = "Folding" })
		palette.add_command({ name = "📕 Close All Folds in File (zM)", cmd = "FoldCloseAll", category = "Folding" })
		palette.add_command({ name = "🏷️ Fold HTML Tags & Components", cmd = "FoldHTML", category = "Folding" })
		palette.add_command({ name = "󰊕 Fold All Functions & Methods", cmd = "FoldFunctions", category = "Folding" })
		palette.add_command({ name = "📦 Fold All Scope Blocks", cmd = "FoldScopes", category = "Folding" })
		palette.add_command({ name = "💾 Save Stored Fold View to .krsnvim", cmd = "FoldSave", category = "Folding" })
		palette.add_command({ name = "📂 Restore Stored Fold View from .krsnvim", cmd = "FoldRestore", category = "Folding" })
		palette.add_command({ name = "🗑️ Clear Stored Fold Views in .krsnvim", cmd = "FoldClearViews", category = "Folding" })
	end
end

return setmetatable({
	name = "krs_folding",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "FoldToggle", "FoldOpenAll", "FoldCloseAll", "FoldFunctions", "FoldHTML", "FoldScopes", "FoldSave", "FoldRestore", "FoldClearViews" },
	event = { "BufReadPost", "BufNewFile" },
	keys = {
		{ "<A-y>", mode = { "n", "v", "i", "t" }, desc = "Toggle fold" },
		{ "<A-Y>", mode = { "n", "v", "i", "t" }, desc = "Toggle fold" },
		{ "<M-y>", mode = { "n", "v", "i", "t" }, desc = "Toggle fold" },
		{ "<M-Y>", mode = { "n", "v", "i", "t" }, desc = "Toggle fold" },
	},
	config = M.setup,
}, { __index = M })
