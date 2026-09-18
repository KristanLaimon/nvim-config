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

	it("cleanly 3-way merges non-conflicting changes when importing zip into existing file", function()
		local f_name = "src/calculator.lua"

		local base_content =
			"local M = {}\n\nfunction M.add(a, b)\n\treturn a + b\nend\n\nfunction M.sub(a, b)\n\treturn a - b\nend\n\nreturn M\n"
		local incoming_content =
			"local M = {}\n\nfunction M.add(a, b)\n\t-- Added logging\n\treturn a + b\nend\n\nfunction M.sub(a, b)\n\treturn a - b\nend\n\nreturn M\n"
		local local_content =
			"local M = {}\n\nfunction M.add(a, b)\n\treturn a + b\nend\n\nfunction M.sub(a, b)\n\t-- Local sub comment\n\treturn a - b\nend\n\nreturn M\n"

		local staging = vim.fn.tempname() .. "_staging"
		vim.fn.mkdir(staging, "p")
		local inc_file = path_util.join(staging, f_name)
		local base_file = path_util.join(staging, ".krs_diff_base", f_name)
		vim.fn.mkdir(vim.fs.dirname(inc_file), "p")
		vim.fn.mkdir(vim.fs.dirname(base_file), "p")

		local h_inc = io.open(inc_file, "w")
		if h_inc then
			h_inc:write(incoming_content)
			h_inc:close()
		end
		local h_base = io.open(base_file, "w")
		if h_base then
			h_base:write(base_content)
			h_base:close()
		end

		local mf = {
			generator = "krs_git_diff_mode",
			version = "2.0",
			files = { f_name },
		}
		local h_mf = io.open(path_util.join(staging, ".krs_diff_manifest.json"), "w")
		if h_mf then
			h_mf:write(vim.json.encode(mf))
			h_mf:close()
		end

		diff_mode.zip_directory(staging, zip_dest)
		pcall(vim.fn.delete, staging, "rf")

		-- Target repo has local_content
		local target_file = path_util.join(target_import_repo, f_name)
		vim.fn.mkdir(vim.fs.dirname(target_file), "p")
		local h_target = io.open(target_file, "w")
		if h_target then
			h_target:write(local_content)
			h_target:close()
		end

		-- Import zip into target_import_repo
		local ok, err, stats = diff_mode.import_diff_files_from_zip(zip_dest, target_import_repo)
		expect(ok).toBeTruthy()
		expect(err).toBeNil()
		expect(stats).toBeDefined()
		expect(stats.merged_clean).toBe(1)
		expect(stats.conflicted).toBe(0)

		-- Verify both changes are merged and no conflict markers
		local merged_data = io.open(target_file, "r"):read("*a")
		expect(merged_data:match("Added logging") ~= nil).toBeTruthy()
		expect(merged_data:match("Local sub comment") ~= nil).toBeTruthy()
		expect(merged_data:match("<<<<<<<") == nil).toBeTruthy()
		expect(merged_data:match(">>>>>>>") == nil).toBeTruthy()
	end)

	it("generates conflict markers (<<<<<<< / ======= / >>>>>>>) when changes conflict", function()
		local f_name = "src/config.lua"

		local base_content = "return { version = '1.0.0', mode = 'dev' }\n"
		local incoming_content = "return { version = '2.0.0-incoming', mode = 'dev' }\n"
		local local_content = "return { version = '3.0.0-local', mode = 'dev' }\n"

		local staging = vim.fn.tempname() .. "_staging2"
		vim.fn.mkdir(staging, "p")
		local inc_file = path_util.join(staging, f_name)
		local base_file = path_util.join(staging, ".krs_diff_base", f_name)
		vim.fn.mkdir(vim.fs.dirname(inc_file), "p")
		vim.fn.mkdir(vim.fs.dirname(base_file), "p")

		local h_inc = io.open(inc_file, "w")
		if h_inc then
			h_inc:write(incoming_content)
			h_inc:close()
		end
		local h_base = io.open(base_file, "w")
		if h_base then
			h_base:write(base_content)
			h_base:close()
		end

		local mf = {
			generator = "krs_git_diff_mode",
			version = "2.0",
			files = { f_name },
		}
		local h_mf = io.open(path_util.join(staging, ".krs_diff_manifest.json"), "w")
		if h_mf then
			h_mf:write(vim.json.encode(mf))
			h_mf:close()
		end

		diff_mode.zip_directory(staging, zip_dest)
		pcall(vim.fn.delete, staging, "rf")

		-- Target repo has local_content
		local target_file = path_util.join(target_import_repo, f_name)
		vim.fn.mkdir(vim.fs.dirname(target_file), "p")
		local h_target = io.open(target_file, "w")
		if h_target then
			h_target:write(local_content)
			h_target:close()
		end

		-- Import zip into target_import_repo
		local ok, err, stats = diff_mode.import_diff_files_from_zip(zip_dest, target_import_repo)
		expect(ok).toBeTruthy()
		expect(err).toBeNil()
		expect(stats).toBeDefined()
		expect(stats.conflicted).toBe(1)
		expect(stats.total_conflicts >= 1).toBeTruthy()
		expect(#stats.conflicted_files).toBe(1)
		expect(stats.conflicted_files[1].file).toBe(f_name)

		-- Verify conflict markers are in target_file
		local merged_data = io.open(target_file, "r"):read("*a")
		expect(merged_data:match("<<<<<<<") ~= nil).toBeTruthy()
		expect(merged_data:match("=======") ~= nil).toBeTruthy()
		expect(merged_data:match(">>>>>>>") ~= nil).toBeTruthy()
		expect(merged_data:match("3%.0%.0%-local") ~= nil).toBeTruthy()
		expect(merged_data:match("2%.0%.0%-incoming") ~= nil).toBeTruthy()

		-- Verify .krs_diff_base is not in target_import_repo
		local base_in_target = path_util.join(target_import_repo, ".krs_diff_base")
		expect(vim.fn.isdirectory(base_in_target)).toBe(0)
	end)

	it("end-to-end: exports modified file from git repo with base and imports with merge", function()
		-- Initialize git repo in temp_repo
		vim.system({ "git", "-C", temp_repo, "init" }):wait()
		vim.system({ "git", "-C", temp_repo, "config", "user.email", "test@krs.dev" }):wait()
		vim.system({ "git", "-C", temp_repo, "config", "user.name", "KRS Tester" }):wait()

		local f_name = "hello.txt"
		local full_file = path_util.join(temp_repo, f_name)
		local h = io.open(full_file, "w")
		if h then
			h:write("line1\nline2\nline3\n")
			h:close()
		end

		vim.system({ "git", "-C", temp_repo, "add", f_name }):wait()
		vim.system({ "git", "-C", temp_repo, "commit", "-m", "initial" }):wait()

		-- Modify file in temp_repo (incoming changes on line 3)
		local h2 = io.open(full_file, "w")
		if h2 then
			h2:write("line1\nline2\nline3_incoming\n")
			h2:close()
		end

		diff_mode.state.cwd = temp_repo
		diff_mode.state.base_ref = "HEAD"
		diff_mode.state.target_ref = "WORKTREE"

		local out = diff_mode.export_diff_files_to_zip(zip_dest, { { file = f_name, status = "M" } }, temp_repo)
		expect(out).toBeDefined()

		-- Target repo has modification on line 1
		local target_file = path_util.join(target_import_repo, f_name)
		local h_t = io.open(target_file, "w")
		if h_t then
			h_t:write("line1_local\nline2\nline3\n")
			h_t:close()
		end

		-- Import zip into target_import_repo
		local ok, err, stats = diff_mode.import_diff_files_from_zip(out, target_import_repo)
		expect(ok).toBeTruthy()
		expect(err).toBeNil()
		expect(stats.merged_clean).toBe(1)
		expect(stats.conflicted).toBe(0)

		local content = io.open(target_file, "r"):read("*a")
		expect(content:match("line1_local") ~= nil).toBeTruthy()
		expect(content:match("line2") ~= nil).toBeTruthy()
		expect(content:match("line3_incoming") ~= nil).toBeTruthy()
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
