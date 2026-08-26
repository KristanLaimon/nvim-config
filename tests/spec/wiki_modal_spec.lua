-- ============================================================================
-- tests/spec/wiki_modal_spec.lua -- Documentation Center Wiki Modal.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local wiki_modal = require("plugins.krs.ui.wiki_modal")
local lsp_keymaps = require("keymaps.lsp")

describe("plugins.krs.ui.wiki_modal", function()
	it("exposes documentation categories and docs directory setting", function()
		expect(wiki_modal.categories).toBeDefined()
		expect(#wiki_modal.categories).toBeGreaterThan(0)
		expect(wiki_modal.settings.docs_dir).toBeDefined()
	end)

	it("registers KrsWiki and NvimWiki user commands", function()
		wiki_modal.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["KrsWiki"]).toBeDefined()
		expect(cmds["NvimWiki"]).toBeDefined()
	end)

	it("toggles open and closed cleanly", function()
		expect(function()
			wiki_modal.open()
			wiki_modal.close()
		end).not_.toThrow()
	end)

	-- Regression: <C-S-d> silently opened LSP "go to definition" instead of
	-- the wiki, because keymaps.lsp (loaded before lazy.nvim) and
	-- wiki_modal both claimed the same key. Whichever set it last won, so
	-- the wiki could vanish again the moment another module reused the key.
	it("does not share its open key with LSP go-to-definition", function()
		for _, wiki_key in ipairs(wiki_modal.settings.keys.open) do
			for _, lsp_key in ipairs(lsp_keymaps.settings.keys.goto_definition) do
				expect(wiki_key == lsp_key).toBe(false)
			end
		end
	end)

	-- Regression: many terminals (plain PowerShell/conhost, older Windows
	-- Terminal) can't distinguish <C-S-d> from <C-d> at all -- they only see
	-- "Ctrl is held", not Shift. Without a fallback that doesn't depend on
	-- that distinction, the wiki becomes unreachable by keyboard in those
	-- terminals no matter what <C-S-d> is bound to.
	it("resolves every open key to the wiki in normal mode", function()
		wiki_modal.setup()
		for _, key in ipairs(wiki_modal.settings.keys.open) do
			local map = vim.fn.maparg(key, "n", false, true)
			expect(map.buffer == nil or map.buffer == 0).toBe(true)
			expect(map.desc).toContain("Documentation Center Wiki")
		end
	end)

	it("registers Shift+Click (<S-LeftMouse>) and nowait close keymaps when opened", function()
		wiki_modal.open()
		local left_maps = vim.api.nvim_buf_get_keymap(0, "n")
		wiki_modal.close()

		local has_shift_click = false
		local has_nowait_close = false
		for _, map in ipairs(left_maps) do
			if map.lhs == "<S-LeftMouse>" then
				has_shift_click = true
			end
			if (map.lhs == "q" or map.lhs == "<Esc>") and map.nowait == 1 then
				has_nowait_close = true
			end
		end

		expect(has_shift_click).toBe(true)
		expect(has_nowait_close).toBe(true)
	end)

	it("defaults reader pane wrap option to true for mobile readability and binds w keymap to toggle", function()
		wiki_modal.open()
		local right_win = nil
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.bo[buf].filetype == "markdown" and vim.b[buf].krs_wiki_modal then
				right_win = win
				break
			end
		end

		expect(right_win).toBeDefined()
		expect(vim.wo[right_win].wrap).toBe(true)
		expect(vim.wo[right_win].conceallevel).toBe(3)

		local maps = vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(right_win), "n")
		local has_w_map = false
		for _, map in ipairs(maps) do
			if map.lhs == "w" and map.desc and map.desc:find("line wrapping") then
				has_w_map = true
				break
			end
		end

		wiki_modal.close()
		expect(has_w_map).toBe(true)
	end)
end)
