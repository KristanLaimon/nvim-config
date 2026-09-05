-- ============================================================================
-- tests/spec/line_endings_spec.lua -- Line Endings Manager (LF / CRLF).
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local line_endings = require("plugins.krs.editor.line_endings")

local function read_file(path)
	local f = io.open(path, "rb")
	local content = f:read("*a")
	f:close()
	return content
end

local function make_tmp_files()
	local dir = vim.fn.tempname() .. "_le_test"
	vim.fn.mkdir(dir, "p")
	local f1 = dir .. "/file1.txt"
	local binary = dir .. "/blob.bin"

	local af = assert(io.open(f1, "wb"))
	af:write("hello\r\nworld\r\n")
	af:close()

	local bf = assert(io.open(binary, "wb"))
	bf:write("data\0\x01\x02")
	bf:close()

	return dir, f1, binary
end

describe("plugins.krs.editor.line_endings", function()
	it("registers the line endings user commands", function()
		line_endings.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["ChangeLineEndings"]).toBeDefined()
		expect(cmds["ChangeRepoLineEndings"]).toBeDefined()
	end)

	it("converts the whole repo to LF, skipping binary files", function()
		local dir, f1, binary = make_tmp_files()

		line_endings.change_repo("unix", dir)
		expect(read_file(f1)).toBe("hello\nworld\n")
		expect(read_file(binary)).toBe("data\0\x01\x02")
	end)

	it("converts the whole repo to CRLF (dos)", function()
		local dir, f1 = make_tmp_files()

		line_endings.change_repo("dos", dir)
		expect(read_file(f1)).toBe("hello\r\nworld\r\n")
	end)

	it("normalizes mixed line endings by majority vote (LF majority)", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].fileformat = "unix"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1\r", "line2", "line3" })

		line_endings.normalize_mixed_endings(buf)

		expect(vim.bo[buf].fileformat).toBe("unix")
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		expect(lines[1]).toBe("line1")
		expect(lines[2]).toBe("line2")
		expect(lines[3]).toBe("line3")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("normalizes mixed line endings by majority vote (CRLF majority)", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].fileformat = "unix"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1\r", "line2\r", "line3" })

		line_endings.normalize_mixed_endings(buf)

		expect(vim.bo[buf].fileformat).toBe("dos")
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		expect(lines[1]).toBe("line1")
		expect(lines[2]).toBe("line2")
		expect(lines[3]).toBe("line3")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("skips unmodifiable buffers cleanly when converting repo", function()
		local dir, f1 = make_tmp_files()
		local unmod_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(unmod_buf, f1)
		vim.bo[unmod_buf].modifiable = false

		expect(function()
			line_endings.change_repo("unix", dir)
		end).not_.toThrow()

		vim.api.nvim_buf_delete(unmod_buf, { force = true })
	end)
end)
