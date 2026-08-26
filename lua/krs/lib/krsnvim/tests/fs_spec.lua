local M = {}

function M.run()
	local fs = require("krs.lib.krsnvim.fs")
	local test_file = vim.fn.stdpath("cache") .. "/krs_test_fs.txt"

	fs.write(test_file, "hello krsnvim fs")
	assert(fs.exists(test_file), "fs.exists failed")

	local content = fs.read(test_file)
	assert(content == "hello krsnvim fs", "fs.read content mismatch: " .. tostring(content))

	vim.fn.delete(test_file)
	print("  ✓ krsnvim.fs spec passed")
end

return M
