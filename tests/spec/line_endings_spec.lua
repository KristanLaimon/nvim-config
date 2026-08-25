-- ============================================================================
-- tests/spec/line_endings_spec.lua -- Line Endings Manager (LF / CRLF).
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local line_endings = require("plugins.krs.line_endings")

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

describe("plugins.krs.line_endings", function()
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
end)
