local M = {}

function M.run()
	local sh = require("krsnvim.terminal")
	local res = sh("echo krsnvimscript_test_ok")
	assert(res.ok == true, "terminal execution failed, ok is false")
	assert(res.code == 0, "terminal exit code non-zero: " .. tostring(res.code))
	assert(
		res.stdout:find("krsnvimscript_test_ok"),
		"terminal stdout does not contain expected output: " .. tostring(res.stdout)
	)

	print("  ✓ krsnvim.terminal spec passed")
end

return M
