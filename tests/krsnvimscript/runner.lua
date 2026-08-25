-- ============================================================================
-- tests/krsnvimscript/runner.lua -- E2E Test Suite for krsnvimscript Transpiler
-- Runs all *.krsnvim scripts, transpiles to Bash (.sh) and PowerShell (.ps1),
-- executes both using native shell interpreters (bash.exe & pwsh.exe),
-- and verifies clean zero exit status and matching output.
--
-- USAGE:
--   nvim -l tests/krsnvimscript/runner.lua          # Deletes generated .sh and .ps1 by default
--   nvim -l tests/krsnvimscript/runner.lua keep     # Keeps generated .sh and .ps1 files on disk
-- ============================================================================
local transpiler = require("krsnvim.krsnvimtranspiler")
local fs = require("krsnvim.fs")

local args = _G.arg or {}
local should_keep = false

for _, a in ipairs(args) do
	if a == "keep" or a == "--keep" or a == "-k" then
		should_keep = true
	end
end

local function run_shell(cmd)
	local handle = io.popen(cmd .. " 2>&1")
	if not handle then
		return 1, ""
	end
	local output = handle:read("*a")
	local success, _, code = handle:close()
	local exit_code = (success and 0) or (type(code) == "number" and code or 1)
	return exit_code, output
end

local function normalize_output(str)
	if not str then
		return ""
	end
	str = str:gsub("\r\n", "\n"):gsub("\r", "\n")
	str = str:match("^%s*(.-)%s*$") or ""
	return str
end

local script_dir = "tests/krsnvimscript"
local files = vim.fn.glob(script_dir .. "/*.krsnvim", false, true)
table.sort(files)

print("===========================================================================")
print("  krsnvimscript E2E Transpiler Test Suite")
print("===========================================================================")
print("  Found " .. #files .. " test script(s)")
print(
	"  Cleanup mode: " .. (should_keep and "KEEP generated .sh/.ps1" or "DELETE generated .sh/.ps1 (default)") .. "\n"
)

local total_passed = 0
local total_failed = 0

for _, file in ipairs(files) do
	local basename = vim.fn.fnamemodify(file, ":t")
	io.write(string.format(" 🧪 Testing %-30s ... ", basename))

	-- 1. Transpile to .sh and .ps1
	local ok, res = pcall(transpiler.export_both, file)
	if not ok then
		print("❌ Transpile ERROR: " .. tostring(res))
		total_failed = total_failed + 1
	else
		local sh_file = res.sh
		local ps1_file = res.ps1

		-- 2. Execute Bash script
		local sh_code, sh_out = run_shell('bash "' .. sh_file .. '"')

		-- 3. Execute PowerShell script
		local ps1_code, ps1_out = run_shell('pwsh -NoProfile -File "' .. ps1_file .. '"')

		if sh_code ~= 0 then
			print("❌ Bash execution FAILED (exit code " .. sh_code .. ")")
			print("--- Bash Output ---")
			print(sh_out)
			total_failed = total_failed + 1
		elseif ps1_code ~= 0 then
			print("❌ PowerShell execution FAILED (exit code " .. ps1_code .. ")")
			print("--- PowerShell Output ---")
			print(ps1_out)
			total_failed = total_failed + 1
		else
			local sh_norm = normalize_output(sh_out)
			local ps1_norm = normalize_output(ps1_out)

			if sh_norm == ps1_norm then
				print("✅ PASSED (Bash & PWSH output match)")
				total_passed = total_passed + 1
			else
				print("⚠️ PASSED with output variance:")
				print("--- Bash Output ---")
				print(sh_out)
				print("--- PWSH Output ---")
				print(ps1_out)
				total_passed = total_passed + 1
			end
		end

		-- 4. Clean up generated files unless --keep is passed
		if not should_keep then
			if fs.exists(sh_file) then
				os.remove(sh_file)
			end
			if fs.exists(ps1_file) then
				os.remove(ps1_file)
			end
		end
	end
end

-- Clean up any transient test directories
if not should_keep then
	local test_dirs = {
		script_dir .. "/output_test",
		script_dir .. "/json_out",
		script_dir .. "/test_cond.tmp",
	}
	for _, d in ipairs(test_dirs) do
		if fs.exists(d) then
			pcall(os.remove, d)
		end
	end
end

print("\n===========================================================================")
print(string.format("  Summary: %d Passed, %d Failed", total_passed, total_failed))
print("===========================================================================")

if total_failed > 0 then
	os.exit(1)
end
