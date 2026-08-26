local M = {}

function M.run()
	local toml = require("krs.lib.krsnvim.toml")
	local sample_toml = [[
title = "krsnvimscript"
version = 1

[author]
name = "krs"
]]

	local decoded = toml.decode(sample_toml)
	assert(decoded.title == "krsnvimscript", "TOML decode title failed: " .. tostring(decoded.title))
	assert(decoded.author and decoded.author.name == "krs", "TOML decode section failed")

	local encoded = toml.encode(decoded)
	assert(encoded:find("krsnvimscript"), "TOML encode failed")

	print("  ✓ krsnvim.toml spec passed")
end

return M
