local M = {}

function M.run()
	local json = require("krs.lib.krsnvim.json")
	local obj = { name = "krsnvimscript", version = 1, active = true }
	local encoded = json.encode(obj)
	assert(encoded:find("krsnvimscript"), "JSON encode failed")

	local decoded = json.decode(encoded)
	assert(decoded.name == "krsnvimscript", "JSON decode name failed")
	assert(decoded.version == 1, "JSON decode version failed")
	assert(decoded.active == true, "JSON decode boolean failed")

	print("  ✓ krsnvim.json spec passed")
end

return M
