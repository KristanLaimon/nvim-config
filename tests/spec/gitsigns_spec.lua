-- ============================================================================
-- tests/spec/gitsigns_spec.lua -- GitSigns plugin specification and setup.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local gitsigns_spec = require("plugins.editor.gitsigns")

describe("plugins.editor.gitsigns", function()
	it("exports a lazy plugin specification for lewis6991/gitsigns.nvim", function()
		expect(gitsigns_spec[1]).toBe("lewis6991/gitsigns.nvim")
		expect(gitsigns_spec.opts).toBeDefined()
		expect(gitsigns_spec.opts.signcolumn).toBe(true)
	end)

	it("defines sign glyphs for add, change, delete and untracked", function()
		local signs = gitsigns_spec.opts.signs
		expect(signs.add.text).toBe("▎")
		expect(signs.change.text).toBe("▎")
		expect(signs.delete.text).toBe("")
		expect(signs.untracked.text).toBe("▎")
	end)

	it("provides an on_attach function for buffer keymapping", function()
		expect(type(gitsigns_spec.opts.on_attach)).toBe("function")
		-- Should safely return when package.loaded.gitsigns is nil
		expect(function()
			gitsigns_spec.opts.on_attach(0)
		end).not_.toThrow()
	end)
end)
