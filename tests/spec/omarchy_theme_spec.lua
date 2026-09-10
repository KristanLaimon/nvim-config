-- ============================================================================
-- tests/spec/omarchy_theme_spec.lua -- Omarchy theme synchronization tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local omarchy = require("plugins.krs.ui.omarchy_theme")
local cp = require("plugins.krs.tools.command_palette")
local theme_picker = require("plugins.krs.ui.theme_picker")

local original_store_file
local original_sync_data_file

describe("plugins.krs.ui.omarchy_theme", function()
	beforeEach(function()
		original_store_file = omarchy.settings.store_file
		original_sync_data_file = omarchy.settings.sync_data_file
		omarchy.settings.store_file = vim.fn.tempname() .. ".json"
		omarchy.settings.sync_data_file = vim.fn.tempname() .. ".json"
	end)

	afterEach(function()
		omarchy.stop_watcher()
		if omarchy.settings.store_file and vim.fn.filereadable(omarchy.settings.store_file) == 1 then
			vim.fn.delete(omarchy.settings.store_file)
		end
		if omarchy.settings.sync_data_file and vim.fn.filereadable(omarchy.settings.sync_data_file) == 1 then
			vim.fn.delete(omarchy.settings.sync_data_file)
		end
		omarchy.settings.store_file = original_store_file
		omarchy.settings.sync_data_file = original_sync_data_file
	end)

	it("parses TOML color key-value pairs accurately", function()
		local sample_toml = [[
mode = "dark"
accent = "#89b4fa"
selection = "#45475a"
background = "#1e1e2e"
foreground = "#cdd6f4"
red = "#f38ba8"
green = "#a6e3a1"
blue = "#89b4fa"
]]
		local parsed = omarchy.parse_colors_toml(sample_toml)
		expect(parsed.mode).toBe("dark")
		expect(parsed.accent).toBe("#89b4fa")
		expect(parsed.background).toBe("#1e1e2e")
		expect(parsed.foreground).toBe("#cdd6f4")
		expect(parsed.red).toBe("#f38ba8")
		expect(parsed.green).toBe("#a6e3a1")
		expect(parsed.blue).toBe("#89b4fa")
	end)

	it("builds a dark mode palette with proper fallback defaults", function()
		local colors = {
			mode = "dark",
			background = "#1e1e2e",
			dark_background = "#161622",
			foreground = "#cdd6f4",
			accent = "#89b4fa",
			red = "#f38ba8",
			green = "#a6e3a1",
		}
		local p = omarchy.build_palette(colors)
		expect(p.bg).toBe("#1e1e2e")
		expect(p.bg_dark).toBe("#161622")
		expect(p.fg).toBe("#cdd6f4")
		expect(p.accent).toBe("#89b4fa")
		expect(p.error).toBe("#f38ba8")
		expect(p.string).toBe("#a6e3a1")
		expect(p.none).toBe("NONE")
	end)

	it("builds a light mode palette when mode is light", function()
		local colors = {
			mode = "light",
			background = "#fafafa",
			foreground = "#2a2a2a",
			accent = "#1e66f5",
		}
		local p = omarchy.build_palette(colors)
		expect(p.bg).toBe("#fafafa")
		expect(p.fg).toBe("#2a2a2a")
		expect(p.accent).toBe("#1e66f5")
	end)

	it("builds complete highlight definitions table", function()
		local colors = {
			mode = "dark",
			background = "#1e1e2e",
			dark_background = "#161622",
			foreground = "#cdd6f4",
			accent = "#89b4fa",
		}
		local p = omarchy.build_palette(colors)
		local hl = omarchy.build_highlights(p, colors)

		expect(hl.Normal).toBeDefined()
		expect(hl.Normal.bg).toBe(p.bg)
		expect(hl.Normal.fg).toBe(p.fg)
		expect(hl.StatusLine).toBeDefined()
		expect(hl.TelescopeBorder).toBeDefined()
		expect(hl.NeoTreeNormal).toBeDefined()
		expect(hl["@function"]).toBeDefined()
		expect(hl.CmpKindBg_Function).toBeDefined()
	end)

	it("defaults sync enabled to false", function()
		expect(omarchy.is_sync_enabled()).toBe(false)
	end)

	it("persists toggle state correctly in store", function()
		expect(omarchy.is_sync_enabled()).toBe(false)

		-- Enabling when Omarchy is available
		if omarchy.is_omarchy_available() then
			local ok = omarchy.set_sync_enabled(true)
			expect(ok).toBe(true)
			expect(omarchy.is_sync_enabled()).toBe(true)

			-- Disabling reverts state
			omarchy.set_sync_enabled(false)
			expect(omarchy.is_sync_enabled()).toBe(false)
		end
	end)

	it("registers user commands upon setup", function()
		omarchy.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["KrsOmarchySyncToggle"]).toBeDefined()
		expect(cmds["KrsOmarchySyncNow"]).toBeDefined()
		expect(cmds["KrsOmarchySyncStatus"]).toBeDefined()
	end)

	it("includes omarchy sync toggle in command palette UI section", function()
		local found = false
		for _, cmd in ipairs(cp.commands) do
			if cmd.cmd == "KrsOmarchySyncToggle" and cmd.category == "UI" then
				found = true
				break
			end
		end
		expect(found).toBe(true)
	end)

	it("strictly gates out non-Omarchy environments like Windows and WSL", function()
		local real_env = package.loaded["krs.core.environment"]
		local windows_env = {
			detect = function()
				return { is_windows = true, is_wsl = false, is_mac = false, is_termux = false, is_omarchy = false }
			end,
		}
		package.loaded["krs.core.environment"] = windows_env

		expect(omarchy.is_omarchy_available()).toBe(false)
		local ok = omarchy.set_sync_enabled(true)
		expect(ok).toBe(false)
		expect(omarchy.is_sync_enabled()).toBe(false)

		local wsl_env = {
			detect = function()
				return { is_windows = false, is_wsl = true, is_mac = false, is_termux = false, is_omarchy = false }
			end,
		}
		package.loaded["krs.core.environment"] = wsl_env
		expect(omarchy.is_omarchy_available()).toBe(false)

		package.loaded["krs.core.environment"] = real_env
	end)

	it("discovers omarchy-krs in theme_picker", function()
		local themes = theme_picker.discover_themes()
		expect(themes).toContain("omarchy-krs")
	end)
end)
