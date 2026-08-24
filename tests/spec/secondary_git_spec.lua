-- ============================================================================
-- tests/spec/secondary_git_spec.lua -- Secondary Git Repos (Dotfiles Pattern)
-- ============================================================================
-- Tests path resolution, config loading/saving, alias generation, and argument
-- construction for secondary decoupled repositories.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local sec_git = require("krs.git.secondary")
local store = require("krs.core.store")
local path_util = require("krs.core.path")

describe("krs.git.secondary path resolution", function()
	it("expands $HOME and ~ to absolute user home directory", function()
		local home = (vim.env.HOME or vim.env.USERPROFILE or "~"):gsub("\\", "/")
		local res1 = sec_git.resolve_path("$HOME/.secrets-repo.git", "/tmp/project")
		local res2 = sec_git.resolve_path("~/.secrets-repo.git", "/tmp/project")

		expect(res1).toBe(path_util.normalize(home .. "/.secrets-repo.git"))
		expect(res2).toBe(path_util.normalize(home .. "/.secrets-repo.git"))
	end)

	it("resolves relative path '.' to the working directory", function()
		local cwd = "/tmp/my-project"
		local res = sec_git.resolve_path(".", cwd)
		expect(res).toBe(path_util.normalize(cwd))
	end)

	it("normalizes relative git_dir to dotfile format (e.g. git-krs -> ./.git-krs)", function()
		expect(sec_git.normalize_git_dir("git-krs")).toBe("./.git-krs")
		expect(sec_git.normalize_git_dir("./git-krs")).toBe("./.git-krs")
		expect(sec_git.normalize_git_dir("./.git-krs")).toBe("./.git-krs")
		expect(sec_git.normalize_git_dir("$HOME/.secrets-repo.git")).toBe("$HOME/.secrets-repo.git")
	end)
end)

describe("krs.git.secondary alias generation", function()
	it("generates PowerShell function syntax for ps1", function()
		local repo = {
			alias = "secgit",
			git_dir = "$HOME/.secrets-repo.git",
			work_tree = ".",
		}
		local cwd = "/tmp/project"
		local ps1 = sec_git.generate_alias(repo, "ps1", cwd)

		expect(ps1).toContain("function secgit {")
		expect(ps1).toContain("add $args")
		expect(ps1).toContain("--git-dir=")
	end)

	it("generates POSIX function syntax for sh", function()
		local repo = {
			alias = "secgit",
			git_dir = "$HOME/.secrets-repo.git",
			work_tree = ".",
		}
		local cwd = "/tmp/project"
		local sh = sec_git.generate_alias(repo, "sh", cwd)

		expect(sh).toContain("secgit() {")
		expect(sh).toContain("add \"$@\"")
		expect(sh).toContain("--git-dir=")
	end)
end)

describe("krs.git.secondary config management", function()
	local test_dir

	beforeEach(function()
		test_dir = path_util.normalize(vim.fn.tempname())
		vim.fn.mkdir(test_dir .. "/.krsnvim", "p")
	end)

	afterEach(function()
		if test_dir and vim.fn.isdirectory(test_dir) == 1 then
			pcall(vim.fn.delete, test_dir, "rf")
		end
	end)

	it("returns empty repositories table when config file is missing", function()
		local config = sec_git.load(test_dir)
		expect(config.version).toBe(1)
		expect(config.repositories).toEqual({})
	end)

	it("adds, updates and removes secondary repository entries cleanly", function()
		local ok_add = sec_git.add_repo({
			alias = "secgit",
			git_dir = "$HOME/.secrets-repo.git",
			work_tree = ".",
			show_untracked = false,
			remote = "git@github.com:user/secrets.git",
		}, test_dir)

		expect(ok_add).toBeTruthy()

		local repo, idx = sec_git.find_repo("secgit", test_dir)
		expect(repo).not_.toBeNil()
		expect(idx).toBe(1)
		expect(repo.alias).toBe("secgit")
		expect(repo.show_untracked).toBeFalsy()

		-- Verify helper scripts were created in .krsnvim
		local sh_exists = vim.fn.filereadable(test_dir .. "/.krsnvim/secondary_aliases.sh") == 1
		local ps1_exists = vim.fn.filereadable(test_dir .. "/.krsnvim/secondary_aliases.ps1") == 1
		expect(sh_exists).toBeTruthy()
		expect(ps1_exists).toBeTruthy()

		-- Remove repo
		local ok_rem = sec_git.remove_repo("secgit", test_dir)
		expect(ok_rem).toBeTruthy()

		local repo_after = sec_git.find_repo("secgit", test_dir)
		expect(repo_after).toBeNil()
	end)

	it("builds git argv with --git-dir and --work-tree flags", function()
		sec_git.add_repo({
			alias = "secgit",
			git_dir = "$HOME/.secrets-repo.git",
			work_tree = ".",
		}, test_dir)

		local argv = sec_git.build_cmd_args("secgit", { "status" }, test_dir)
		expect(argv).not_.toBeNil()

		local argv_str = table.concat(argv, " ")
		expect(argv_str).toContain("--git-dir=")
		expect(argv_str).toContain("--work-tree=")
		expect(argv_str).toContain("status")
	end)

	it("builds standard git add commands without forced -f flag", function()
		sec_git.add_repo({
			alias = "secgit",
			git_dir = "$HOME/.secrets-repo.git",
			work_tree = ".",
		}, test_dir)

		local argv = sec_git.build_cmd_args("secgit", { "add", ".env.local" }, test_dir)
		expect(argv).not_.toBeNil()
		local argv_str = table.concat(argv, " ")
		expect(argv_str).toContain("add .env.local")
		expect(argv_str).not_.toContain("add -f .env.local")
	end)

	it("cleans up stray bare git repository files in a temporary directory", function()
		store.write_file(test_dir .. "/HEAD", "ref: refs/heads/main\n")
		store.write_file(test_dir .. "/config", "[core]\n")
		vim.fn.mkdir(test_dir .. "/objects", "p")

		local cleaned = sec_git.cleanup_stray_bare_files(test_dir)
		expect(cleaned).toBeTruthy()
		expect(vim.fn.filereadable(test_dir .. "/HEAD") == 0).toBeTruthy()
		expect(vim.fn.filereadable(test_dir .. "/config") == 0).toBeTruthy()
		expect(vim.fn.isdirectory(test_dir .. "/objects") == 0).toBeTruthy()
	end)
end)
