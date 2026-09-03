-- ============================================================================
-- KRSNVIMSCRIPT TRANSPILER -- Main Entry Point & Exporters
-- ============================================================================

local fs = require("krs.lib.krsnvim.fs")
local sh = require("krs.lib.krsnvim.krsnvimtranspiler.sh")
local ps1 = require("krs.lib.krsnvim.krsnvimtranspiler.ps1")

local M = {}

M.to_sh = sh.to_sh
M.to_ps1 = ps1.to_ps1

--- Exports a given .krsnvim script file to .sh (Bash) script.
--- @param filepath string Path to source .krsnvim script file.
--- @param outpath string|nil Target .sh file path. Defaults to replacing .krsnvim with .sh.
--- @return string generated_path Path of generated .sh file.
function M.export_sh(filepath, outpath)
	if not filepath or filepath == "" then
		error("krsnvimtranspiler: No source file provided for export")
	end
	outpath = outpath or filepath:gsub("%.krsnvim$", ".sh")
	if outpath == filepath then
		outpath = filepath .. ".sh"
	end
	local code = fs.read(filepath)
	local sh_code = M.to_sh(code)
	fs.write(outpath, sh_code)
	if vim.fn.has("win32") == 0 then
		pcall(vim.fn.system, { "chmod", "+x", outpath })
	end
	return outpath
end

--- Exports a given .krsnvim script file to .ps1 (PowerShell) script.
--- @param filepath string Path to source .krsnvim script file.
--- @param outpath string|nil Target .ps1 file path. Defaults to replacing .krsnvim with .ps1.
--- @return string generated_path Path of generated .ps1 file.
function M.export_ps1(filepath, outpath)
	if not filepath or filepath == "" then
		error("krsnvimtranspiler: No source file provided for export")
	end
	outpath = outpath or filepath:gsub("%.krsnvim$", ".ps1")
	if outpath == filepath then
		outpath = filepath .. ".ps1"
	end
	local code = fs.read(filepath)
	local ps1_code = M.to_ps1(code)
	fs.write(outpath, ps1_code)
	return outpath
end

--- Exports a given .krsnvim script file to BOTH .sh and .ps1 scripts side-by-side.
--- @param filepath string Path to source .krsnvim script file.
--- @return string sh_path, string ps1_path
function M.export_both(filepath)
	local sh_path = M.export_sh(filepath)
	local ps1_path = M.export_ps1(filepath)
	return sh_path, ps1_path
end

return M
