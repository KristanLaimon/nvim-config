-- ============================================================================
-- tests/integration/run.lua -- Entry point for tests that need the REAL editor.
-- ============================================================================
-- WHY A SECOND RUNNER
--   tests/run.lua runs under `nvim -l` with no plugins, so it only covers pure
--   logic. Anything that needs nvim-dap, telescope or the actual startup sequence
--   has to boot the full config -- that is what this runner does.
--
-- HOW TO RUN
--   nvim --headless -S tests/integration/run.lua
--   nvim --headless -S tests/integration/run.lua dap    # name filter
--
-- WRITING AN INTEGRATION SPEC
--   Same shape as tests/spec (krsnvim.test describe/it/expect), but plugins may
--   be assumed loaded. Load what you need explicitly at the top of the spec:
--     require("lazy").load({ plugins = { "nvim-dap" } })
-- ============================================================================

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local filter = vim.v.argv and vim.v.argv[#vim.v.argv] or nil
if filter and filter:match("%.lua$") then
	filter = nil
end

local failed = 0

for _, file in ipairs(vim.fn.glob(root .. "/tests/integration/*_spec.lua", false, true)) do
	local name = vim.fn.fnamemodify(file, ":t:r")
	if not filter or name:find(filter, 1, true) then
		local ok, err = pcall(dofile, file)
		if not ok then
			failed = failed + 1
			print("  Failed to load spec -> " .. name .. ": " .. tostring(err))
		end
	end
end

local ok, result = pcall(require("krs.lib.krsnvim.test").run)
if not ok then
	print(tostring(result))
end

vim.cmd((failed > 0 or not ok or result.failed > 0) and "cq!" or "qa!")
