local M = {}

function M.run()
	local yaml = require("krs.lib.krsnvim.yaml")
	local sample_yaml = [[
name: krsnvimscript
version: 2
mode: test
]]

	local decoded = yaml.decode(sample_yaml)
	assert(decoded.name == "krsnvimscript", "YAML decode name failed: " .. tostring(decoded.name))
	assert(decoded.version == 2, "YAML decode version failed: " .. tostring(decoded.version))

	local encoded = yaml.encode(decoded)
	assert(encoded:find("krsnvimscript"), "YAML encode failed")

	print("  ✓ krsnvim.yaml spec passed")
end

return M
