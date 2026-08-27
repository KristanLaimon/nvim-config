-- ============================================================================
-- tests/spec/wsl_spec.lua -- WSL path parsing and shell command building.
-- ============================================================================
-- These are pure string transformations, but getting them wrong is expensive:
-- a mis-parsed UNC path makes the integrated terminal open in the wrong distro,
-- or makes the project picker stat a network path and boot WSL for no reason.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach
local wsl = require("plugins.krs.tools.wsl")

describe("wsl.parse_wsl_path", function()
	it("splits a wsl.localhost path into distro and linux path", function()
		local distro, path = wsl.parse_wsl_path([[\\wsl.localhost\Ubuntu\home\me\project]])

		expect(distro).toBe("Ubuntu")
		expect(path).toBe("/home/me/project")
	end)

	it("accepts the older wsl$ prefix", function()
		local distro, path = wsl.parse_wsl_path([[\\wsl$\Debian\srv]])

		expect(distro).toBe("Debian")
		expect(path).toBe("/srv")
	end)

	it("accepts forward slashes", function()
		expect(wsl.parse_wsl_path("//wsl.localhost/Ubuntu/home")).toBe("Ubuntu")
	end)

	it("matches the prefix case-insensitively", function()
		expect(wsl.parse_wsl_path([[\\WSL.LOCALHOST\Ubuntu\home]])).toBe("Ubuntu")
	end)

	it("returns the root for a bare distro path", function()
		local distro, path = wsl.parse_wsl_path([[\\wsl.localhost\Ubuntu]])

		expect(distro).toBe("Ubuntu")
		expect(path).toBe("/")
	end)

	it("rejects ordinary local and network paths", function()
		expect(wsl.parse_wsl_path([[C:\Users\me\project]])).toBeNil()
		expect(wsl.parse_wsl_path([[\\server\share\folder]])).toBeNil()
		expect(wsl.parse_wsl_path("")).toBeNil()
		expect(wsl.parse_wsl_path(nil)).toBeNil()
	end)
end)

describe("wsl.is_wsl_path", function()
	it("is true only for distro paths", function()
		expect(wsl.is_wsl_path([[\\wsl.localhost\Ubuntu\home]])).toBeTruthy()
		expect(wsl.is_wsl_path("C:/projects/app")).toBeFalsy()
	end)
end)

describe("wsl.distro_root", function()
	it("builds a browsable UNC root", function()
		expect(wsl.distro_root("Ubuntu")).toBe("//wsl.localhost/Ubuntu")
	end)
end)

describe("wsl.shell_command_for_cwd", function()
	it("starts the shell in the right distro and directory", function()
		local cmd = wsl.shell_command_for_cwd([[\\wsl.localhost\Ubuntu\home\me\app]])

		expect(cmd).toBe('wsl.exe -d Ubuntu --cd "/home/me/app"')
	end)

	it("falls back to the distro root", function()
		expect(wsl.shell_command_for_cwd([[\\wsl.localhost\Ubuntu]])).toBe('wsl.exe -d Ubuntu --cd "/"')
	end)

	it("drops a trailing slash", function()
		expect(wsl.shell_command_for_cwd([[\\wsl.localhost\Ubuntu\opt\]])).toBe('wsl.exe -d Ubuntu --cd "/opt"')
	end)

	it("returns nil outside WSL, so the caller uses the normal shell", function()
		expect(wsl.shell_command_for_cwd("C:/projects/app")).toBeNil()
	end)
end)

describe("wsl recent projects", function()
	local original_file = wsl.settings.recent_projects_file

	afterEach(function()
		vim.fn.delete(wsl.settings.recent_projects_file)
		wsl.settings.recent_projects_file = original_file
	end)

	--- Points the recent list at a throwaway file.
	local function use_temp_store()
		wsl.settings.recent_projects_file = vim.fn.tempname() .. ".json"
	end

	it("records a WSL project, most recent first", function()
		use_temp_store()

		wsl.add_recent_project([[\\wsl.localhost\Ubuntu\home\a]])
		wsl.add_recent_project([[\\wsl.localhost\Ubuntu\home\b]])

		local recent = wsl.get_recent_projects(false)
		expect(recent[1]).toBe("//wsl.localhost/Ubuntu/home/b")
		expect(recent).toHaveLength(2)
	end)

	it("moves an existing project back to the front instead of duplicating it", function()
		use_temp_store()

		wsl.add_recent_project([[\\wsl.localhost\Ubuntu\home\a]])
		wsl.add_recent_project([[\\wsl.localhost\Ubuntu\home\b]])
		wsl.add_recent_project([[\\wsl.localhost\Ubuntu\home\a]])

		local recent = wsl.get_recent_projects(false)
		expect(recent).toHaveLength(2)
		expect(recent[1]).toBe("//wsl.localhost/Ubuntu/home/a")
	end)

	it("ignores non-WSL paths", function()
		use_temp_store()

		wsl.add_recent_project("C:/projects/app")

		expect(wsl.get_recent_projects(false)).toEqual({})
	end)

	it("removes a project", function()
		use_temp_store()

		wsl.add_recent_project([[\\wsl.localhost\Ubuntu\home\a]])
		wsl.remove_recent_project([[\\wsl.localhost\Ubuntu\home\a]])

		expect(wsl.get_recent_projects(false)).toEqual({})
	end)
end)

describe("PHP tool checks", function()
	local original_has, original_executable, original_system

	afterEach(function()
		vim.fn.has, vim.fn.executable, vim.fn.system = original_has, original_executable, original_system
	end)

	it("only probes WSL when explicitly requested", function()
		local modal = require("plugins.krs.tools.php_tools_modal")
		original_has, original_executable, original_system = vim.fn.has, vim.fn.executable, vim.fn.system
		local calls = 0

		vim.fn.has = function(feature)
			return feature == "win32" and 1 or original_has(feature)
		end
		vim.fn.executable = function(command)
			return (command == "wsl.exe" or command == "wsl") and 1 or 0
		end
		vim.fn.system = function()
			calls = calls + 1
			return ""
		end

		modal.check_tools(true)
		expect(calls).toBe(0)
		modal.check_tools(true, true)
		expect(calls).toBe(2)
	end)
end)

describe("git.cmd.build with WSL paths", function()
	local git = require("krs.git.cmd")

	it("constructs wsl.exe command for WSL UNC path on Windows", function()
		local argv = git.build({ "status", "--porcelain=v1" }, [[\\wsl.localhost\Ubuntu\home\me\repo]])
		if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
			expect(argv[1]).toBe("wsl.exe")
			expect(argv[2]).toBe("-d")
			expect(argv[3]).toBe("Ubuntu")
			expect(argv[4]).toBe("--cd")
			expect(argv[5]).toBe("/home/me/repo")
			expect(argv[6]).toBe("git")
		end
	end)
end)
