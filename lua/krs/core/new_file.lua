local M = {}

--- Create without overwriting, then notify language modules.
--- @param filename string
--- @return boolean
function M.create(filename)
	local ok, err = pcall(vim.fn.mkdir, vim.fs.dirname(filename), "p")
	if ok then
		local fd
		fd, err = vim.uv.fs_open(filename, "wx", 420)
		ok = fd ~= nil
		if fd then
			vim.uv.fs_close(fd)
		end
	end
	if not ok then
		vim.notify("Cannot create " .. filename .. ": " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	vim.api.nvim_exec_autocmds("User", { pattern = "KrsFileCreated", data = { path = filename } })
	return true
end

return M
