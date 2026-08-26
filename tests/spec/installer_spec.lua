-- ============================================================================
-- tests/spec/installer_spec.lua -- KRS System Setup Installer spec.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local installer = require("krs.core.installer")

describe("krs.core.installer", function()
	it("renders unicode progress bar correctly", function()
		expect(installer.render_bar(0, 10)).toBe("░░░░░░░░░░")
		expect(installer.render_bar(50, 10)).toBe("█████░░░░░")
		expect(installer.render_bar(100, 10)).toBe("██████████")
	end)

	it("scans system status and reports component counts", function()
		local scan = installer.scan_status()
		expect(scan).toBeDefined()
		expect(type(scan.percentage)).toBe("number")
		expect(type(scan.installed_count)).toBe("number")
		expect(type(scan.total_count)).toBe("number")
		expect(scan.total_count > 0).toBe(true)
	end)

	it("saves, loads, and resets completion state", function()
		installer.save_state(true)
		local state = installer.load_state()
		expect(state.completed).toBe(true)

		installer.reset_state()
		local reset_state = installer.load_state()
		expect(reset_state.completed).toBe(false)
	end)

	it("opens Live Setup Floating Modal UI cleanly", function()
		installer.open_ui()
		local win = vim.api.nvim_get_current_win()
		expect(vim.api.nvim_win_is_valid(win)).toBe(true)
		local buf = vim.api.nvim_win_get_buf(win)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		expect(#lines > 5).toBe(true)
		vim.api.nvim_win_close(win, true)
	end)

	it("registers user commands on init()", function()
		installer.init()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["KrsSetup"]).toBeDefined()
		expect(cmds["KrsInstallAll"]).toBeDefined()
		expect(cmds["KrsSetupStatus"]).toBeDefined()
		expect(cmds["KrsSetupReset"]).toBeDefined()
		expect(cmds["KrsInstallDependencies"]).toBeDefined()
		expect(cmds["LanguageManager"]).toBeDefined()
	end)

	-- ------------------------------------------------------------------------
	-- Bundle manager: read-only / in-memory logic only. None of these call
	-- install_language_bundle, uninstall_language_bundle,
	-- install_bundle_components, or uninstall_bundle_components -- those
	-- trigger real Mason/Treesitter/dotnet installs and are intentionally
	-- never exercised by the test suite.
	-- ------------------------------------------------------------------------

	it("builds language bundles with resolvable per-component metadata", function()
		local bundles = installer.language_bundles
		expect(#bundles > 0).toBe(true)

		local core
		for _, b in ipairs(bundles) do
			if b.is_minimal then
				core = b
			end
		end
		expect(core).toBeDefined()
		expect(#core.mason_components).toBe(#core.mason_pkgs)

		for _, comp in ipairs(core.mason_components) do
			expect(type(comp.pkg)).toBe("string")
			expect(type(comp.type)).toBe("string")
			expect(type(comp.label)).toBe("string")
		end
	end)

	it("computes bundle status as a pure read of on-disk/PATH state", function()
		local bundle = installer.language_bundles[1]
		local status_a = installer.get_bundle_status(bundle)
		local status_b = installer.get_bundle_status(bundle)

		expect(type(status_a.badge)).toBe("string")
		expect(type(status_a.blocked)).toBe("boolean")
		expect(type(status_a.installed_count)).toBe("number")
		expect(type(status_a.total_count)).toBe("number")
		-- Same bundle, no state change between calls -> identical counts.
		expect(status_a.installed_count).toBe(status_b.installed_count)
		expect(status_a.total_count).toBe(status_b.total_count)
	end)

	it("counts and bulk-sets per-component selection purely in memory", function()
		local item = {
			bundle = { name = "Fake Bundle" },
			comp = {
				mason = { pkg_a = true, pkg_b = false },
				ts = { parser_a = false },
				dotnet = {},
			},
		}

		local sel, tot = installer.count_selected_components(item)
		expect(sel).toBe(1)
		expect(tot).toBe(3)

		installer.set_item_components(item, true)
		local sel_all, tot_all = installer.count_selected_components(item)
		expect(sel_all).toBe(tot_all)
		expect(item.selected).toBe(true)

		installer.set_item_components(item, false)
		local sel_none = installer.count_selected_components(item)
		expect(sel_none).toBe(0)
		expect(item.selected).toBe(false)
	end)

	it("checks Mason/Treesitter install state without installing anything", function()
		expect(type(installer.is_mason_pkg_installed("definitely-not-a-real-package"))).toBe("boolean")

		local installed_parsers = installer.get_installed_ts_parsers()
		expect(type(installed_parsers)).toBe("table")
	end)
end)
