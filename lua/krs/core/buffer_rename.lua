-- ============================================================================
-- krs.core.buffer_rename -- Buffer & bufferline tab updates on file/dir rename.
-- ============================================================================

local path = require("krs.core.path")

local M = {}

--- Updates open buffers and bufferline tabs when a file or directory is renamed or moved.
--- @param old_path string Old file or directory path.
--- @param new_path string New file or directory path.
--- @return integer count Number of buffers updated.
function M.update_buffers_path(old_path, new_path)
	if not old_path or not new_path or old_path == "" or new_path == "" then
		return 0
	end

	local norm_old = path.normalize(old_path)
	local norm_new = path.normalize(new_path)
	if path.equals(norm_old, norm_new) then
		return 0
	end

	local old_dir_prefix = norm_old .. "/"
	local count = 0

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local raw_name = vim.api.nvim_buf_get_name(bufnr)
			if raw_name ~= "" then
				local norm_buf = path.normalize(raw_name)
				local target_new_path = nil

				if path.equals(norm_buf, norm_old) then
					target_new_path = norm_new
				elseif norm_buf:sub(1, #old_dir_prefix):lower() == old_dir_prefix:lower() then
					target_new_path = norm_new .. "/" .. norm_buf:sub(#old_dir_prefix + 1)
				end

				if target_new_path then
					-- Delete any duplicate buffer handle that might already have target_new_path
					local existing = vim.fn.bufnr(target_new_path)
					if existing ~= -1 and existing ~= bufnr and vim.api.nvim_buf_is_valid(existing) then
						pcall(vim.api.nvim_buf_delete, existing, { force = true })
					end

					-- Rename the active buffer handle
					local ok_rename = pcall(vim.api.nvim_buf_set_name, bufnr, target_new_path)
					if ok_rename then
						vim.bo[bufnr].buflisted = true
						-- Trigger filetype detection for extension changes
						pcall(function()
							vim.api.nvim_buf_call(bufnr, function()
								vim.cmd("filetype detect")
							end)
						end)
						count = count + 1
					end
				end
			end
		end
	end

	-- Update pinned tabs list if any pinned file was renamed/moved
	pcall(function()
		local pinned_tabs = require("plugins.krs.ui.pinned_tabs")
		local pins = pinned_tabs.load_pins()
		local updated_pins = {}
		local changed_pins = false
		local project_root = require("krs.core.project").root()

		for _, p in ipairs(pins) do
			local is_abs = (path.is_absolute and path.is_absolute(p)) or (p:sub(1, 1) == "/" or p:match("^%a:") ~= nil)
			local full = is_abs and path.normalize(p) or path.join(project_root, p)

			if path.equals(full, norm_old) then
				local rel = path.relative_to(norm_new, project_root) or norm_new
				table.insert(updated_pins, rel)
				changed_pins = true
			elseif full:sub(1, #old_dir_prefix):lower() == old_dir_prefix:lower() then
				local new_full = norm_new .. "/" .. full:sub(#old_dir_prefix + 1)
				local rel = path.relative_to(new_full, project_root) or new_full
				table.insert(updated_pins, rel)
				changed_pins = true
			else
				table.insert(updated_pins, p)
			end
		end

		if changed_pins then
			pinned_tabs.save_pins(updated_pins)
			pinned_tabs.restore_pins()
		end
	end)

	-- Redraw bufferline / tabline to update titles immediately
	pcall(function()
		vim.cmd("redrawtabline")
	end)

	return count
end

return M
