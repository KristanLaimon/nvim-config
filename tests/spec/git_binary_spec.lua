-- ============================================================================
-- TESTS: Git Center Binary Blacklist & Safe Diff Preview
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local diff = require("krs.git.diff")
local queries = require("plugins.krs.git.git_center.queries")

describe("git_center binary blacklist and safe diff", function()
	it("identifies common binary extensions via is_binary_file", function()
		expect(diff.is_binary_file("bundle.zip")).toBe(true)
		expect(diff.is_binary_file("archive.tar.gz")).toBe(true)
		expect(diff.is_binary_file("snapshot.img")).toBe(true)
		expect(diff.is_binary_file("photo.png")).toBe(true)
		expect(diff.is_binary_file("photo.JPG")).toBe(true)
		expect(diff.is_binary_file("binary.exe")).toBe(true)
		expect(diff.is_binary_file("lib.dll")).toBe(true)
		expect(diff.is_binary_file("package.deb")).toBe(true)
		expect(diff.is_binary_file("document.pdf")).toBe(true)
		expect(diff.is_binary_file("audio.mp3")).toBe(true)
		expect(diff.is_binary_file("video.mp4")).toBe(true)
		expect(diff.is_binary_file("database.sqlite3")).toBe(true)
	end)

	it("identifies code and text files as non-binary", function()
		expect(diff.is_binary_file("init.lua")).toBe(false)
		expect(diff.is_binary_file("server.ts")).toBe(false)
		expect(diff.is_binary_file("index.html")).toBe(false)
		expect(diff.is_binary_file("README.md")).toBe(false)
		expect(diff.is_binary_file("style.css")).toBe(false)
		expect(diff.is_binary_file("config.json")).toBe(false)
		expect(diff.is_binary_file("Cargo.toml")).toBe(false)
		expect(diff.is_binary_file("")).toBe(false)
		expect(diff.is_binary_file(nil)).toBe(false)
	end)

	it("detects git binary diff messages and raw null bytes", function()
		expect(diff.is_binary_diff({ "Binary files a/test.zip and b/test.zip differ" })).toBe(true)
		expect(diff.is_binary_diff({ "GIT binary patch", "literal 500" })).toBe(true)
		expect(diff.is_binary_diff({ "raw\0binary\0data" })).toBe(true)
		expect(diff.is_binary_diff({ "--- a/file.lua", "+++ b/file.lua", "@@ -1,2 +1,3 @@" })).toBe(false)
	end)

	it("formats binary files safely in format_side_by_side_dual without hanging or error", function()
		local raw = { "Binary files a/archive.zip and b/archive.zip differ" }
		local l_lines, l_kinds, r_lines, r_kinds = diff.format_side_by_side_dual(raw, false, "archive.zip")

		expect(type(l_lines)).toBe("table")
		expect(type(r_lines)).toBe("table")
		expect(#l_lines > 0).toBe(true)
		expect(#r_lines > 0).toBe(true)
		expect(l_lines[1]:find("archive%.zip") ~= nil).toBe(true)
		expect(r_lines[1]:find("archive%.zip") ~= nil).toBe(true)
		expect(l_lines[2]:find("Binary file") ~= nil).toBe(true)
		expect(l_kinds[1]).toBe("header")
		expect(r_kinds[1]).toBe("header")
	end)

	it("formats binary files safely in format_side_by_side_single for live preview", function()
		local raw = { "Binary files a/disk.img and b/disk.img differ" }
		local combined, l_kinds, r_kinds, col_w = diff.format_side_by_side_single(raw, false, 80, "disk.img")

		expect(type(combined)).toBe("table")
		expect(#combined > 0).toBe(true)
		expect(type(col_w)).toBe("number")
		expect(combined[1]:find("disk%.img") ~= nil).toBe(true)
		expect(combined[2]:find("Binary file") ~= nil).toBe(true)
	end)

	it("prevents reading raw bytes for untracked or staged binary files in raw_diff_for", function()
		local lines, is_untracked = queries.raw_diff_for("build/output.zip", "unstaged")
		expect(type(lines)).toBe("table")
		expect(is_untracked).toBe(false)
		expect(lines[1]:find("binary blacklist") ~= nil).toBe(true)
	end)
end)
