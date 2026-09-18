-- ============================================================================
-- tests/spec/git_diff_export_zip_spec.lua -- Tests for exporting & importing git diff zips
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local diff_mode = require("plugins.krs.git.diff_mode")
local path_util = require("krs.core.path")

describe("plugins.krs.git.diff_mode.export_zip", function()
	local temp_repo
	local zip_dest
	local target_import_repo

	beforeEach(function()
		temp_repo = vim.fn.tempname() .. "_diff_repo"
		vim.fn.mkdir(temp_repo, "p")
		target_import_repo = vim.fn.tempname() .. "_target_repo"
		vim.fn.mkdir(target_import_repo, "p")
		zip_dest = vim.fn.tempname() .. "_export.zip"

		if diff_mode.is_open() then
			diff_mode.close()
		end
	end)

	afterEach(function()
		if diff_mode.is_open() then
			diff_mode.close()
		end
		pcall(vim.fn.delete, temp_repo, "rf")
		pcall(vim.fn.delete, target_import_repo, "rf")
		pcall(vim.fn.delete, zip_dest)
	end)

	it("computes default export zip filename from commit or branch", function()
		local name = diff_mode.get_default_export_name(vim.fn.getcwd())
		expect(type(name)).toBe("string")
		expect(name:match("%.zip$") ~= nil).toBeTruthy()
		expect(name:match('[\\/:*?"<>|]') == nil).toBeTruthy()
	end)

	it("compresses directory into zip archive preserving relative structure", function()
		local staging = path_util.join(temp_repo, "staging")
		local sub = path_util.join(staging, "src", "components")
		vim.fn.mkdir(sub, "p")

		local f1 = path_util.join(sub, "Button.lua")
		local f2 = path_util.join(staging, "config.json")
		local h1 = io.open(f1, "w")
		if h1 then
			h1:write("return { name = 'button' }")
			h1:close()
		end
		local h2 = io.open(f2, "w")
		if h2 then
			h2:write('{"version": 1}')
			h2:close()
		end

		local ok, err = diff_mode.zip_directory(staging, zip_dest)
		expect(ok).toBeTruthy()
		expect(err).toBeNil()
		expect(vim.fn.filereadable(zip_dest)).toBe(1)
		expect(vim.fn.getfsize(zip_dest)).toBeGreaterThan(0)
	end)

	it("exports diff files to zip, omitting deleted files and including manifest", function()
		-- Create mock files in temp_repo
		local f_added = "src/modules/feature.lua"
		local f_mod = "README.md"
		local f_deleted = "old_file.txt"

		local full_added = path_util.join(temp_repo, f_added)
		local full_mod = path_util.join(temp_repo, f_mod)
		vim.fn.mkdir(vim.fs.dirname(full_added), "p")

		local h_added = io.open(full_added, "w")
		if h_added then
			h_added:write("print('new feature')")
			h_added:close()
		end
		local h_mod = io.open(full_mod, "w")
		if h_mod then
			h_mod:write("# Updated Readme")
			h_mod:close()
		end

		local mock_files = {
			{ file = f_added, status = "A" },
			{ file = f_mod, status = "M" },
			{ file = f_deleted, status = "D" },
		}

		diff_mode.state.cwd = temp_repo
		diff_mode.state.target_ref = "WORKTREE"

		local out = diff_mode.export_diff_files_to_zip(zip_dest, mock_files, temp_repo)
		expect(out).toBeDefined()
		expect(vim.fn.filereadable(out)).toBe(1)
		expect(vim.fn.getfsize(out)).toBeGreaterThan(0)

		-- Verify clipboard gets the exported path
		local reg_plus = vim.fn.getreg("+")
		expect(path_util.equals(reg_plus, out)).toBeTruthy()

		-- Verify manifest exists and is valid
		local manifest, err = diff_mode.read_zip_manifest(out)
		expect(err).toBeNil()
		expect(manifest).toBeDefined()
		expect(manifest.generator).toBe("krs_git_diff_mode")
		expect(#manifest.files).toBe(2)
		expect(manifest.files[1]).toBe(f_added)
		expect(manifest.files[2]).toBe(f_mod)
	end)

	it("rejects zip archives that lack .krs_diff_manifest.json", function()
		-- Create a regular non-KRS zip file
		local non_krs_zip = vim.fn.tempname() .. "_random.zip"
		local dummy_dir = vim.fn.tempname() .. "_dummy"
		vim.fn.mkdir(dummy_dir, "p")
		local df = path_util.join(dummy_dir, "test.txt")
		local dh = io.open(df, "w")
		if dh then
			dh:write("hello")
			dh:close()
		end

		diff_mode.zip_directory(dummy_dir, non_krs_zip)
		pcall(vim.fn.delete, dummy_dir, "rf")

		local manifest, err = diff_mode.read_zip_manifest(non_krs_zip)
		expect(manifest).toBeNil()
		expect(err:match("Incompatible zip archive") ~= nil).toBeTruthy()
		pcall(vim.fn.delete, non_krs_zip)
	end)

	it("rejects zip archives with mismatched generator signature", function()
		local fake_zip = vim.fn.tempname() .. "_fake.zip"
		local dummy_dir = vim.fn.tempname() .. "_dummy2"
		vim.fn.mkdir(dummy_dir, "p")
		local mf = path_util.join(dummy_dir, ".krs_diff_manifest.json")
		local mh = io.open(mf, "w")
		if mh then
			mh:write(vim.json.encode({ generator = "other_tool", files = {} }))
			mh:close()
		end

		diff_mode.zip_directory(dummy_dir, fake_zip)
		pcall(vim.fn.delete, dummy_dir, "rf")

		local manifest, err = diff_mode.read_zip_manifest(fake_zip)
		expect(manifest).toBeNil()
		expect(err:match("signature mismatch") ~= nil).toBeTruthy()
		pcall(vim.fn.delete, fake_zip)
	end)

	it("imports diff files into target directory and preserves contents", function()
		-- 1. Create files in source repo
		local f_name = "src/services/api.lua"
		local full_src = path_util.join(temp_repo, f_name)
		vim.fn.mkdir(vim.fs.dirname(full_src), "p")
		local h = io.open(full_src, "w")
		if h then
			h:write("return { endpoint = '/api/v1' }")
			h:close()
		end

		diff_mode.state.cwd = temp_repo
		diff_mode.state.target_ref = "WORKTREE"
		local out = diff_mode.export_diff_files_to_zip(zip_dest, { { file = f_name, status = "A" } }, temp_repo)
		expect(out).toBeDefined()

		-- 2. Import into target_import_repo
		local ok, err = diff_mode.import_diff_files_from_zip(out, target_import_repo)
		expect(ok).toBeTruthy()
		expect(err).toBeNil()

		-- 3. Verify file was imported and has matching content
		local imported_file = path_util.join(target_import_repo, f_name)
		expect(vim.fn.filereadable(imported_file)).toBe(1)
		local content = io.open(imported_file, "r"):read("*a")
		expect(content:match("/api/v1") ~= nil).toBeTruthy()

		-- 4. Verify .krs_diff_manifest.json was NOT extracted to target_import_repo
		local manifest_in_target = path_util.join(target_import_repo, ".krs_diff_manifest.json")
		expect(vim.fn.filereadable(manifest_in_target)).toBe(0)
	end)

	it("registers GitDiffExportZip and GitDiffImportZip user commands and palette entries", function()
		diff_mode.setup()
		expect(vim.fn.exists(":GitDiffExportZip")).toBe(2)
		expect(vim.fn.exists(":GitDiffImportZip")).toBe(2)

		local cp = require("plugins.krs.tools.command_palette")
		local has_export = false
		local has_import = false
		for _, cmd in ipairs(cp.commands) do
			if cmd.cmd == "GitDiffExportZip" then
				has_export = true
			end
			if cmd.cmd == "GitDiffImportZip" then
				has_import = true
			end
		end
		expect(has_export).toBeTruthy()
		expect(has_import).toBeTruthy()
	end)

	it("binds export and import shortcuts in diff sidebar window", function()
		local win, buf = diff_mode.open_file_list_window({
			{ file = "test.lua", status = "M" },
		}, 1)

		expect(win ~= nil and vim.api.nvim_win_is_valid(win)).toBeTruthy()
		expect(buf ~= nil and vim.api.nvim_buf_is_valid(buf)).toBeTruthy()

		-- Check buffer lines contain [e]: Export | [i]: Import
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local full_text = table.concat(lines, "\n")
		expect(full_text:match("%[e%]: Export") ~= nil).toBeTruthy()
		expect(full_text:match("%[i%]: Import") ~= nil).toBeTruthy()
	end)
end)
