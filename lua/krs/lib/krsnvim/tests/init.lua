local M = {}

function M.run_all()
	print("==========================================")
	print(" 🦊 Running krsnvimscript Test Suite")
	print("==========================================")

	local specs = {
		"json_spec",
		"yaml_spec",
		"toml_spec",
		"terminal_spec",
		"cli_spec",
		"fs_spec",
		"import_spec",
		"fetch_spec",
		"console_spec",
		"async_spec",
		"test_framework_spec",
		"test_mock_spec",
		"krsnvimtranspiler_spec",
	}

	local passed = 0
	local failed = 0

	for _, spec in ipairs(specs) do
		local ok, mod = pcall(require, "krsnvim.tests." .. spec)
		if ok and mod.run then
			local run_ok, err = pcall(mod.run)
			if run_ok then
				passed = passed + 1
			else
				failed = failed + 1
				print("  ❌ " .. spec .. " FAILED: " .. tostring(err))
			end
		else
			failed = failed + 1
			print("  ❌ Could not load test spec: " .. spec)
		end
	end

	print("==========================================")
	print(string.format(" Test Results: %d Passed, %d Failed", passed, failed))
	print("==========================================")

	if failed > 0 then
		error("krsnvimscript test suite failed with " .. failed .. " errors.")
	end
end

return M
