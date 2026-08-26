local M = {}

function M.run()
	local krsnvim = require("krs.lib.krsnvim")
	local import = krsnvim.import

	local json_mod = import("krsnvim.json")
	assert(type(json_mod.decode) == "function", "import('krsnvim.json') failed")

	local sh_mod = import("krsnvim.terminal")
	assert(type(sh_mod.exec) == "function", "import('krsnvim.terminal') failed")

	local cli_mod = import("krsnvim.cli")
	assert(type(cli_mod.parse_args) == "function", "import('krsnvim.cli') failed")

	print("  ✓ krsnvim.import spec passed")
end

return M
