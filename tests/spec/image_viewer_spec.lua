-- ============================================================================
-- tests/spec/image_viewer_spec.lua -- Tests for Media / Image Viewer plugin.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("plugins.krs.ui.image_viewer", function()
	it("executes setup without throwing errors when preview key is configured or nil", function()
		local viewer = require("plugins.krs.ui.image_viewer")

		-- Test setup with valid preview key
		viewer.settings.keys.preview = "<leader>i"
		local ok1, err1 = pcall(viewer.setup)
		expect(ok1).toBe(true, tostring(err1))

		-- Test setup with nil preview key
		viewer.settings.keys.preview = nil
		local ok2, err2 = pcall(viewer.setup)
		expect(ok2).toBe(true, tostring(err2))

		-- Restore default preview key
		viewer.settings.keys.preview = "<leader>i"
	end)
end)
