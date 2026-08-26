-- ============================================================================
-- tests/spec/hover_links_spec.lua
-- Unit tests for hover_links plugin (LSP hover doc link navigation & parsing).
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach

local hover_links = require("plugins.krs.editor.hover_links")
local path = require("krs.core.path")

local temp_dir

describe("plugins.krs.editor.hover_links link navigation and parsing", function()
	beforeEach(function()
		temp_dir = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(temp_dir, "p")
	end)

	afterEach(function()
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(b) then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end
		local scratch = vim.api.nvim_create_buf(true, true)
		pcall(vim.api.nvim_set_current_buf, scratch)
		vim.fn.delete(temp_dir, "rf")
	end)

	it("attaches keymaps to floating hover buffer", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].filetype = "markdown"
		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			width = 40,
			height = 10,
			row = 2,
			col = 2,
		})

		hover_links.attach_hover_keymaps(buf, win)

		local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
		local mapped_keys = {}
		for _, k in ipairs(keymaps) do
			mapped_keys[k.lhs] = true
		end

		expect(mapped_keys["<CR>"]).toBeTruthy()
		expect(mapped_keys["gx"]).toBeTruthy()
		expect(mapped_keys["K"]).toBeTruthy()
		expect(mapped_keys["q"]).toBeTruthy()
		expect(mapped_keys["<Esc>"]).toBeTruthy()

		vim.api.nvim_win_close(win, true)
	end)

	it("jumps to local file link with line and column numbers from hover buffer", function()
		local target_file = path.join(temp_dir, "target.go")
		vim.fn.writefile({ "package main", "func Handle() {}", "func Main() {}" }, target_file)

		local link_str = string.format("See [Handle](file:///%s#2,6) for details.", target_file:gsub("\\", "/"))

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { link_str })

		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = 60,
			height = 5,
			row = 5,
			col = 5,
		})

		-- Place cursor on line with link
		vim.api.nvim_win_set_cursor(win, { 1, 10 })

		hover_links.follow_link_at_cursor()

		-- Verify main window opened the target file at line 2
		local active_buf = vim.api.nvim_get_current_buf()
		local active_name = path.normalize(vim.api.nvim_buf_get_name(active_buf))
		local cursor = vim.api.nvim_win_get_cursor(0)

		expect(active_name).toBe(path.normalize(target_file))
		expect(cursor[1]).toBe(2)
		expect(cursor[2]).toBe(5) -- 0-indexed column 5 corresponds to col 6
	end)

	it("shows warning when line contains no link", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Plain text with no links here" })

		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = 40,
			height = 5,
			row = 5,
			col = 5,
		})

		local handled = hover_links.follow_link_at_cursor()

		expect(handled).toBe(false)
		expect(vim.api.nvim_win_is_valid(win)).toBeTruthy()
		vim.api.nvim_win_close(win, true)
	end)

	it("jumps to file links referenced inside code comments", function()
		local target_file = path.join(temp_dir, "helper.lua")
		vim.fn.writefile({ "local M = {}", "function M.init() end", "return M" }, target_file)

		local comment_line = string.format("-- @see %s:2:1", target_file:gsub("\\", "/"))

		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 10", comment_line })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 2, 5 })

		local handled = hover_links.follow_link_at_cursor()

		expect(handled).toBe(true)

		local active_buf = vim.api.nvim_get_current_buf()
		local active_name = path.normalize(vim.api.nvim_buf_get_name(active_buf))
		local cursor = vim.api.nvim_win_get_cursor(0)

		expect(active_name).toBe(path.normalize(target_file))
		expect(cursor[1]).toBe(2)
	end)
end)
