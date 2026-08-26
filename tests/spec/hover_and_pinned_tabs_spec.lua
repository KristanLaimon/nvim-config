-- ============================================================================
-- tests/spec/hover_and_pinned_tabs_spec.lua
-- Comprehensive unit tests for pinned_tabs plugin (.krsnvim pins & workspaces).
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach

local pinned_tabs = require("plugins.krs.ui.pinned_tabs")
local path = require("krs.core.path")
local project = require("krs.core.project")
local workspaces = require("plugins.krs.tools.workspaces")

local root
local orig_cwd

describe("plugins.krs.ui.pinned_tabs", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(path.join(root, ".krsnvim"), "p")
		orig_cwd = vim.fn.getcwd()
		vim.api.nvim_set_current_dir(root)
	end)

	afterEach(function()
		if orig_cwd then
			pcall(vim.api.nvim_set_current_dir, orig_cwd)
		end
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(b) then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end
		local scratch = vim.api.nvim_create_buf(true, true)
		pcall(vim.api.nvim_set_current_buf, scratch)
		vim.fn.delete(root, "rf")
	end)

	it("identifies code buffers vs non-code buffers", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, path.join(root, "test.go"))

		expect(pinned_tabs.is_code_buffer(buf)).toBeTruthy()

		vim.bo[buf].buftype = "nofile"
		expect(pinned_tabs.is_code_buffer(buf)).toBeFalsy()

		vim.bo[buf].buftype = ""
		vim.bo[buf].filetype = "neo-tree"
		expect(pinned_tabs.is_code_buffer(buf)).toBeFalsy()

		vim.bo[buf].filetype = "dashboard"
		expect(pinned_tabs.is_code_buffer(buf)).toBeFalsy()

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("saves and loads pinned files for normal project", function()
		local pins_file = project.config_path("pins.json", root)
		expect(path.is_file(pins_file)).toBeFalsy()

		pinned_tabs.save_pins({ "src/main.go", "src/server.go" })
		local loaded = pinned_tabs.load_pins()

		expect(#loaded).toBe(2)
		expect(loaded[1]).toBe("src/main.go")
		expect(loaded[2]).toBe("src/server.go")
	end)

	it("uses workspace-specific pins file when workspace is active", function()
		workspaces.set_active_workspace({ id = "ws_feature_auth", name = "Auth Feature" })

		local pins_file = pinned_tabs.get_pins_file()
		expect(pins_file:find("pins_ws_feature_auth", 1, true)).toBeTruthy()

		pinned_tabs.save_pins({ "auth/login.ts" })
		local loaded = pinned_tabs.load_pins()

		expect(#loaded).toBe(1)
		expect(loaded[1]).toBe("auth/login.ts")

		workspaces.set_active_workspace(nil)
	end)

	it("toggles pin status of current code buffer", function()
		local test_file = path.join(root, "app.ts")
		vim.fn.writefile({ "console.log('hi')" }, test_file)
		local buf = vim.fn.bufadd(test_file)
		vim.api.nvim_set_current_buf(buf)

		pinned_tabs.toggle_pin()
		local pins = pinned_tabs.load_pins()
		expect(#pins).toBe(1)

		pinned_tabs.toggle_pin()
		pins = pinned_tabs.load_pins()
		expect(#pins).toBe(0)
	end)

	it("restores pinned files into active buffer list", function()
		local file1 = path.join(root, "pinned_1.lua")
		local file2 = path.join(root, "pinned_2.lua")
		vim.fn.writefile({ "-- 1" }, file1)
		vim.fn.writefile({ "-- 2" }, file2)

		pinned_tabs.save_pins({ file1, file2 })
		pinned_tabs.restore_pins()

		local bufs = vim.api.nvim_list_bufs()
		local open_names = {}
		for _, b in ipairs(bufs) do
			if vim.api.nvim_buf_is_valid(b) then
				open_names[path.normalize(vim.api.nvim_buf_get_name(b))] = true
			end
		end

		expect(open_names[path.normalize(file1)]).toBeTruthy()
		expect(open_names[path.normalize(file2)]).toBeTruthy()
	end)

	it("auto-prunes deleted pinned files on restore", function()
		local file1 = path.join(root, "exists.lua")
		local file2 = path.join(root, "deleted.lua")
		vim.fn.writefile({ "-- exists" }, file1)

		pinned_tabs.save_pins({ file1, file2 })
		pinned_tabs.restore_pins()

		local loaded = pinned_tabs.load_pins()
		expect(#loaded).toBe(1)
		expect(loaded[1]).toBe(file1)
	end)

	it.skip("registers pinned buffers in bufferline.groups and focuses the first pinned tab on restore", function()
		local file1 = path.join(root, "pinned_first.lua")
		local file2 = path.join(root, "pinned_second.lua")
		vim.fn.writefile({ "-- 1" }, file1)
		vim.fn.writefile({ "-- 2" }, file2)

		pinned_tabs.save_pins({ file1, file2 })
		pinned_tabs.restore_pins({ focus = true })

		-- 1. Check bufferline groups pin status (pin emoji icon state)
		local ok_bg, groups = pcall(require, "bufferline.groups")
		if ok_bg and groups and groups._is_pinned then
			for _, b in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_valid(b) then
					local bname = path.normalize(vim.api.nvim_buf_get_name(b))
					if bname == path.normalize(file1) or bname == path.normalize(file2) then
						expect(groups._is_pinned({ id = b })).toBeTruthy()
					end
				end
			end
		end

		-- 2. Check active window buffer is the first (leftmost) pinned tab
		local cur_buf = vim.api.nvim_get_current_buf()
		local cur_name = path.normalize(vim.api.nvim_buf_get_name(cur_buf))
		expect(cur_name).toBe(path.normalize(file1))
	end)
end)
