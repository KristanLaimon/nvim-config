-- ============================================================================
-- tests/spec/git_simulate_spec.lua -- Tests for dry-run merge and rebase simulation.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local simulate = require("krs.git.simulate")
local path_util = require("krs.core.path")

describe("krs.git.simulate", function()
	local temp_repo

	beforeEach(function()
		temp_repo = vim.fn.tempname() .. "_sim"
		vim.fn.mkdir(temp_repo, "p")
		vim.system({ "git", "-C", temp_repo, "init", "-b", "main" }):wait()
		vim.system({ "git", "-C", temp_repo, "config", "user.email", "tester@krs.dev" }):wait()
		vim.system({ "git", "-C", temp_repo, "config", "user.name", "KRS Tester" }):wait()
	end)

	afterEach(function()
		if temp_repo and vim.fn.isdirectory(temp_repo) == 1 then
			pcall(vim.fn.delete, temp_repo, "rf")
		end
	end)

	it("simulates clean merge with zero conflicts and leaves working tree untouched", function()
		-- Initial commit on main
		local f1 = path_util.join(temp_repo, "file1.txt")
		local h = io.open(f1, "w")
		h:write("line1\nline2\n")
		h:close()
		vim.system({ "git", "-C", temp_repo, "add", "." }):wait()
		vim.system({ "git", "-C", temp_repo, "commit", "-m", "init" }):wait()

		-- Create feature branch
		vim.system({ "git", "-C", temp_repo, "branch", "feature-clean" }):wait()

		-- Commit on main
		local h_m = io.open(f1, "w")
		h_m:write("line1\nline2_main\n")
		h_m:close()
		vim.system({ "git", "-C", temp_repo, "commit", "-am", "commit on main" }):wait()

		-- Commit on feature (different file)
		vim.system({ "git", "-C", temp_repo, "checkout", "feature-clean" }):wait()
		local f2 = path_util.join(temp_repo, "file2.txt")
		local h_f = io.open(f2, "w")
		h_f:write("feature content\n")
		h_f:close()
		vim.system({ "git", "-C", temp_repo, "add", "." }):wait()
		vim.system({ "git", "-C", temp_repo, "commit", "-m", "commit on feature" }):wait()

		-- Run simulation: merge feature-clean into main
		local res = simulate.simulate_merge("main", "feature-clean", temp_repo)

		expect(res.error).toBeNil()
		expect(res.is_clean).toBe(true)
		expect(#res.conflicted_files).toBe(0)
		expect(res.commits_ahead).toBe(1)
		expect(res.commits_behind).toBe(1)
		expect(res.merge_base).toBeDefined()

		-- Verify working tree is clean and unchanged
		local st = vim.system({ "git", "-C", temp_repo, "status", "--porcelain" }):wait()
		expect(st.stdout).toBe("")

		local branch = vim.system({ "git", "-C", temp_repo, "rev-parse", "--abbrev-ref", "HEAD" }):wait()
		expect(vim.trim(branch.stdout)).toBe("feature-clean")
	end)

	it("detects merge conflicts accurately without modifying workspace", function()
		-- Initial commit
		local f1 = path_util.join(temp_repo, "conflict.txt")
		local h = io.open(f1, "w")
		h:write("base line A\nbase line B\n")
		h:close()
		vim.system({ "git", "-C", temp_repo, "add", "." }):wait()
		vim.system({ "git", "-C", temp_repo, "commit", "-m", "init" }):wait()

		-- Create feature branch
		vim.system({ "git", "-C", temp_repo, "branch", "feature-conflict" }):wait()

		-- Modify same lines on main
		local h_m = io.open(f1, "w")
		h_m:write("main change line A\nbase line B\n")
		h_m:close()
		vim.system({ "git", "-C", temp_repo, "commit", "-am", "change on main" }):wait()

		-- Modify same lines on feature
		vim.system({ "git", "-C", temp_repo, "checkout", "feature-conflict" }):wait()
		local h_f = io.open(f1, "w")
		h_f:write("feature change line A\nbase line B\n")
		h_f:close()
		vim.system({ "git", "-C", temp_repo, "commit", "-am", "change on feature" }):wait()

		-- Run simulation
		local res = simulate.simulate_merge("main", "feature-conflict", temp_repo)

		expect(res.error).toBeNil()
		expect(res.is_clean).toBe(false)
		expect(#res.conflicted_files).toBeGreaterThan(0)
		expect(res.conflicted_files).toContain("conflict.txt")

		-- Working tree check
		local st = vim.system({ "git", "-C", temp_repo, "status", "--porcelain" }):wait()
		expect(st.stdout).toBe("")
	end)

	it("simulates rebase and identifies conflicting commits", function()
		local f = path_util.join(temp_repo, "code.txt")
		local h = io.open(f, "w")
		h:write("initial\n")
		h:close()
		vim.system({ "git", "-C", temp_repo, "add", "." }):wait()
		vim.system({ "git", "-C", temp_repo, "commit", "-m", "init" }):wait()

		vim.system({ "git", "-C", temp_repo, "branch", "feature-rebase" }):wait()

		-- Commit on main
		local hm = io.open(f, "w")
		hm:write("main update\n")
		hm:close()
		vim.system({ "git", "-C", temp_repo, "commit", "-am", "main mod" }):wait()

		-- Commit on feature
		vim.system({ "git", "-C", temp_repo, "checkout", "feature-rebase" }):wait()
		local hf = io.open(f, "w")
		hf:write("feature update\n")
		hf:close()
		vim.system({ "git", "-C", temp_repo, "commit", "-am", "feat mod" }):wait()

		local res = simulate.simulate_rebase("main", "feature-rebase", temp_repo)
		expect(res.error).toBeNil()
		expect(res.mode).toBe("rebase")
		expect(res.is_clean).toBe(false)
		expect(res.first_conflicting_commit).toBeDefined()
		expect(res.first_conflicting_commit.index).toBe(1)
	end)
end)
