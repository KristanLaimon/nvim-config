-- ============================================================================
-- tests/spec/buffer_rename_spec.lua -- Buffer & bufferline tab rename tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

local buffer_rename = require("krs.core.buffer_rename")
local path = require("krs.core.path")

describe("buffer_rename.update_buffers_path", function()
	it("updates the name of an open buffer when its file is renamed", function()
		local old_file = path.normalize(vim.fn.tempname() .. "_old.lua")
		local new_file = path.normalize(vim.fn.tempname() .. "_new.lua")

		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, old_file)
		vim.bo[buf].buflisted = true

		expect(path.normalize(vim.api.nvim_buf_get_name(buf))).toBe(old_file)

		local count = buffer_rename.update_buffers_path(old_file, new_file)
		expect(count).toBe(1)
		expect(path.normalize(vim.api.nvim_buf_get_name(buf))).toBe(new_file)
		expect(vim.bo[buf].buflisted).toBe(true)

		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)

	it("updates all open buffers inside a directory when the directory is renamed", function()
		local tmp_dir = path.normalize(vim.fn.tempname() .. "_dir")
		local old_dir = path.join(tmp_dir, "old_folder")
		local new_dir = path.join(tmp_dir, "new_folder")

		local file1_old = path.join(old_dir, "sub", "test1.txt")
		local file2_old = path.join(old_dir, "test2.txt")
		local file1_new = path.join(new_dir, "sub", "test1.txt")
		local file2_new = path.join(new_dir, "test2.txt")

		local buf1 = vim.api.nvim_create_buf(true, false)
		local buf2 = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf1, file1_old)
		vim.api.nvim_buf_set_name(buf2, file2_old)
		vim.bo[buf1].buflisted = true
		vim.bo[buf2].buflisted = true

		local count = buffer_rename.update_buffers_path(old_dir, new_dir)
		expect(count).toBe(2)
		expect(path.normalize(vim.api.nvim_buf_get_name(buf1))).toBe(file1_new)
		expect(path.normalize(vim.api.nvim_buf_get_name(buf2))).toBe(file2_new)

		pcall(vim.api.nvim_buf_delete, buf1, { force = true })
		pcall(vim.api.nvim_buf_delete, buf2, { force = true })
	end)

	it("handles pre-existing duplicate target buffer handles gracefully", function()
		local old_file = path.normalize(vim.fn.tempname() .. "_src.txt")
		local new_file = path.normalize(vim.fn.tempname() .. "_dest.txt")

		local active_buf = vim.api.nvim_create_buf(true, false)
		local stale_buf = vim.api.nvim_create_buf(false, false)

		vim.api.nvim_buf_set_name(active_buf, old_file)
		vim.api.nvim_buf_set_name(stale_buf, new_file)

		local count = buffer_rename.update_buffers_path(old_file, new_file)
		expect(count).toBe(1)
		expect(path.normalize(vim.api.nvim_buf_get_name(active_buf))).toBe(new_file)

		pcall(vim.api.nvim_buf_delete, active_buf, { force = true })
		pcall(vim.api.nvim_buf_delete, stale_buf, { force = true })
	end)
end)
