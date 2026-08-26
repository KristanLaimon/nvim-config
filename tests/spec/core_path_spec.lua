-- ============================================================================
-- tests/spec/core_path_spec.lua -- Contract tests for krs.core.path.
-- ============================================================================
-- Path handling is the single most copy-pasted logic in this config, so its
-- edge cases (drive letters, trailing slashes, case sensitivity) are pinned here.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local path = require("krs.core.path")

describe("krs.core.path.normalize", function()
	it("converts backslashes to forward slashes", function()
		expect(path.normalize([[C:\Users\me\project]])).toBe("C:/Users/me/project")
	end)

	it("strips a trailing slash", function()
		expect(path.normalize("/home/me/")).toBe("/home/me")
	end)

	it("keeps a bare drive root intact", function()
		expect(path.normalize([[C:\]])).toBe("C:/")
	end)

	it("returns an empty string for nil or empty input", function()
		expect(path.normalize(nil)).toBe("")
		expect(path.normalize("")).toBe("")
	end)

	it("identifies absolute paths vs relative paths", function()
		expect(path.is_absolute("C:/Users/test")).toBeTruthy()
		expect(path.is_absolute("/usr/local/bin")).toBeTruthy()
		expect(path.is_absolute("src/main.lua")).toBeFalsy()
		expect(path.is_absolute("")).toBeFalsy()
	end)
end)

describe("krs.core.path.join", function()
	it("joins segments with a single separator", function()
		expect(path.join("root", ".krsnvim", "tasks.json")).toBe("root/.krsnvim/tasks.json")
	end)

	it("collapses separators contributed by the segments", function()
		expect(path.join("root/", "/sub/", "file")).toBe("root/sub/file")
	end)

	it("skips nil and empty segments", function()
		expect(path.join("root", nil, "", "file")).toBe("root/file")
	end)

	it("keeps a leading slash on the first segment", function()
		expect(path.join("/usr", "local")).toBe("/usr/local")
	end)
end)

describe("krs.core.path.equals", function()
	it("ignores separator style", function()
		expect(path.equals([[C:\a\b]], "C:/a/b")).toBeTruthy()
	end)

	it("follows platform case rules", function()
		expect(path.equals("C:/Project", "c:/project")).toBe(path.is_windows)
	end)

	it("rejects different paths", function()
		expect(path.equals("C:/a", "C:/b")).toBeFalsy()
	end)
end)

describe("krs.core.path.relative_to", function()
	it("returns the path below the root", function()
		expect(path.relative_to("C:/proj/src/main.lua", "C:/proj")).toBe("src/main.lua")
	end)

	it("returns an empty string when path equals root", function()
		expect(path.relative_to("C:/proj", "C:/proj/")).toBe("")
	end)

	it("returns nil when the path is outside the root", function()
		expect(path.relative_to("D:/other/file", "C:/proj")).toBeNil()
	end)

	it("does not treat a sibling prefix as a child", function()
		expect(path.relative_to("C:/project2/file", "C:/project")).toBeNil()
	end)
end)

describe("krs.core.path filesystem probes", function()
	it("reports directories and files apart", function()
		local dir = vim.fn.tempname()
		path.ensure_dir(dir)
		local file = dir .. "/probe.txt"
		vim.fn.writefile({ "x" }, file)

		expect(path.is_dir(dir)).toBeTruthy()
		expect(path.is_file(dir)).toBeFalsy()
		expect(path.is_file(file)).toBeTruthy()

		vim.fn.delete(dir, "rf")
	end)

	it("ensure_dir is idempotent and returns the path", function()
		local dir = vim.fn.tempname()
		expect(path.ensure_dir(dir)).toBe(dir)
		expect(path.ensure_dir(dir)).toBe(dir)
		expect(path.is_dir(dir)).toBeTruthy()
		vim.fn.delete(dir, "rf")
	end)
end)
