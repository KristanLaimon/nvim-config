local M = {}

function M.run()
	local cli = require("krs.lib.krsnvim.cli")

	local parsed = cli.parse_args({ "--verbose", "--env=test", "main.lua" })
	assert(parsed.flags.verbose == true, "cli parse_args flag verbose failed")
	assert(parsed.flags.env == "test", "cli parse_args flag env failed")
	assert(parsed.positional[1] == "main.lua", "cli parse_args positional failed")

	local help_str = cli.help({
		name = "test_script",
		description = "Test script description",
		options = { verbose = "Enable verbose output" },
	})
	assert(help_str:find("test_script"), "cli help string failed")

	print("  ✓ krsnvim.cli spec passed")
end

return M
