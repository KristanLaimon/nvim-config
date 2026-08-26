-- ============================================================================
-- tests/spec/statusline_spec.lua -- Statusline engine & theme picker.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local statusline = require("plugins.krs.ui.statusline_picker")

describe("plugins.krs.ui.statusline_picker", function()
	it("formats modes into NvChad icon pills", function()
		expect(statusline.format_mode("NORMAL")).toBe(" NORMAL")
		expect(statusline.format_mode("INSERT")).toBe("󰏫 INSERT")
		expect(statusline.format_mode("VISUAL")).toBe("󰈈 VISUAL")
		expect(statusline.format_mode("COMMAND")).toBe("󰘳 COMMAND")
	end)

	it("formats current buffer line ending into LF / CRLF / CR labels", function()
		local buf = vim.api.nvim_get_current_buf()
		local saved = vim.bo[buf].fileformat

		vim.bo[buf].fileformat = "unix"
		expect(statusline.fileformat_status()).toBe("⏎ LF")

		vim.bo[buf].fileformat = "dos"
		expect(statusline.fileformat_status()).toBe("⏎ CRLF")

		vim.bo[buf].fileformat = "mac"
		expect(statusline.fileformat_status()).toBe("⏎ CR")

		vim.bo[buf].fileformat = saved
	end)

	it("is placed first in the left statusbar section for every theme", function()
		local themes = { "nvchad_pills", "nvchad_blocks", "nvchad_round", "nagatoro_classic", "vscode", "minimal" }
		for _, name in ipairs(themes) do
			local cfg = statusline.get_lualine_config(name)
			local secs = cfg.sections
			local left = name == "nagatoro_classic" and secs.lualine_a or secs.lualine_b
			expect(left[1]).toBe(statusline.fileformat_status)
		end
	end)

	it("returns formatted LSP status string", function()
		expect(statusline.lsp_status()).toBeDefined()
		expect(type(statusline.lsp_status())).toBe("string")
	end)

	it("cleans up raw terminal URLs into readable badges", function()
		expect(statusline.format_filename("term://~\\AppData\\Local\\nvim//14964:C:\\PROGRA~1\\Git\\bin\\bash.exe")).toBe(
			"󰞷 Terminal (bash)"
		)
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal (powershell)")
		expect(statusline.format_filename("lua/config/options.lua")).toBe("lua/config/options.lua")
	end)

	it("formats multi-terminal labels with process title (Terminal #number - process)", function()
		vim.b.krs_term_num = 2
		vim.b.term_title = nil
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal #2 - powershell")

		vim.b.term_title = "claude"
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal #2 - claude")

		vim.b.term_title = "Administrator: Windows PowerShell"
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal #2 - powershell")

		vim.b.krs_term_num = nil
		vim.b.term_title = nil
	end)

	it("returns valid lualine options for all supported themes", function()
		local themes = { "nvchad_pills", "nvchad_blocks", "nvchad_round", "nagatoro_classic", "vscode", "minimal" }
		for _, name in ipairs(themes) do
			local cfg = statusline.get_lualine_config(name)
			expect(cfg).toBeDefined()
			expect(cfg.options).toBeDefined()
			expect(cfg.sections).toBeDefined()
			expect(cfg.sections.lualine_a).toBeDefined()
		end
	end)

	it("registers KrsStatuslineTheme user command", function()
		statusline.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["KrsStatuslineTheme"]).toBeDefined()
	end)
end)
