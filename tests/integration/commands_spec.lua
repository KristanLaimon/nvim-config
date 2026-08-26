-- ============================================================================
-- tests/integration/commands_spec.lua -- The editor's public surface.
-- ============================================================================
-- Every feature in this config is reached through a command or a keymap. A
-- refactor that quietly stops registering one is invisible until the day you
-- press the key, so the whole surface is asserted here after a real startup.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

--- True when a user command exists.
--- @param name string Command name, without the colon.
--- @return boolean
local function has_command(name)
	return vim.fn.exists(":" .. name) > 0
end

--- True when a mapping exists in any of the given modes.
--- @param lhs string Key sequence.
--- @param modes string[]|nil Defaults to normal mode.
--- @return boolean
local function has_keymap(lhs, modes)
	for _, mode in ipairs(modes or { "n" }) do
		if vim.fn.maparg(lhs, mode) ~= "" then
			return true
		end
	end
	return false
end

pcall(function()
	vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
	require("plugins.krs.tools.workspaces").setup()
	require("plugins.krs.git.git_center").setup()
	require("plugins.krs.dev.tasks").setup()
end)

describe("user commands", function()
	it("registers the task runner commands", function()
		for _, name in ipairs({ "TaskRunner", "TaskMenu", "TaskRestart", "TaskKill", "TaskRunDefault" }) do
			expect({ name, has_command(name) }).toEqual({ name, true })
		end
	end)

	it("registers the workspace commands", function()
		for _, name in ipairs({
			"WorkspaceSave",
			"WorkspaceLoad",
			"WorkspaceDelete",
			"WorkspaceRename",
			"WorkspaceSelect",
			"Workspaces",
			"WorkspaceClose",
			"WorkspaceMenu",
		}) do
			expect({ name, has_command(name) }).toEqual({ name, true })
		end
	end)

	it("registers the breakpoint commands", function()
		for _, name in ipairs({
			"DapBreakpointToggleEnabled",
			"DapBreakpointsEnableAll",
			"DapBreakpointsDisableAll",
			"DapBreakpointsRemoveAll",
		}) do
			expect({ name, has_command(name) }).toEqual({ name, true })
		end
	end)

	it("registers the type injector and transpiler commands", function()
		for _, name in ipairs({
			"TypeInjector",
			"KrsTypes",
			"KrsGitignoreGenerated",
			"KrsExport",
			"KrsExportSh",
			"KrsExportPs1",
		}) do
			expect({ name, has_command(name) }).toEqual({ name, true })
		end
	end)

	it("registers the remaining feature commands", function()
		for _, name in ipairs({
			"GitCenter",
			"GitStageAll",
			"GitCenterReload",
			"CommandPalette",
			"TelescopeFileBrowserDesktop",
			"TelescopeFileBrowserWSL",
			"FontSizeIncrease",
			"FontSizeDecrease",
			"FontSizeReset",
			"NugetManager",
			"TailwindOrganize",
			"TailwindOrganizerToggle",
			"NvimWiki",
			"ReloadConfig",
			"KrsTest",
		}) do
			expect({ name, has_command(name) }).toEqual({ name, true })
		end
	end)
end)

describe("keymaps", function()
	it("binds the KRS panels", function()
		for _, key in ipairs({ "<C-S-g>", "<C-S-t>", "<C-S-w>", "<C-S-p>", "<C-S-f>", "<C-S-s>", "<C-S-q>" }) do
			expect({ key, has_keymap(key, { "n", "i", "v", "t" }) }).toEqual({ key, true })
		end
	end)

	it("binds the editor essentials", function()
		for _, key in ipairs({ "<C-s>", "<C-w>", "<C-q>", "<C-z>" }) do
			expect({ key, has_keymap(key, { "n", "i", "v", "t" }) }).toEqual({ key, true })
		end
	end)

	it("binds the debugger", function()
		for _, key in ipairs({ "<C-b>", "<F5>", "<F10>", "<F11>", "<F12>" }) do
			expect({ key, has_keymap(key, { "n", "i", "v" }) }).toEqual({ key, true })
		end
	end)

	it("binds every terminal slot", function()
		local terminal = require("plugins.krs.dev.terminal")
		for slot = 1, terminal.settings.count do
			local key = "<A-" .. slot .. ">"
			expect({ key, has_keymap(key, { "n", "i", "t" }) }).toEqual({ key, true })
		end
	end)

	it("binds every task output slot", function()
		local tasks = require("plugins.krs.dev.tasks")
		for slot = 1, tasks.settings.max_slots do
			local key = "<C-A-S-" .. slot .. ">"
			expect({ key, has_keymap(key, { "n", "i", "t" }) }).toEqual({ key, true })
		end
	end)
end)

describe("global helpers other modules rely on", function()
	it("exposes the buffer helpers used by the bufferline and terminals", function()
		expect(type(_G.Neotree_Smart_Quit)).toBe("function")
		expect(type(_G.Smart_Close_Buffer)).toBe("function")
		expect(type(_G.AddOpenedFolder)).toBe("function")
		expect(type(_G.Is_File_Deleted)).toBe("function")
	end)

	it("replaces vim.ui.input with the shared modal", function()
		expect(type(vim.ui.input)).toBe("function")
		expect(type(require("plugins.krs.ui.input_modal").open)).toBe("function")
	end)
end)
