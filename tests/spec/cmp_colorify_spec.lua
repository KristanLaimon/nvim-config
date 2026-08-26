-- ============================================================================
-- tests/spec/cmp_colorify_spec.lua -- Colorify engine & CMP kind formatting.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local colorify = require("krs.lsp.colorify")

describe("krs.lsp.colorify", function()
	describe("extract_hex_color", function()
		it("extracts 6-digit hex color strings", function()
			expect(colorify.extract_hex_color("#e06c75")).toBe("#e06c75")
			expect(colorify.extract_hex_color("bg-color: #123456;")).toBe("#123456")
		end)

		it("expands 3-digit hex color strings", function()
			expect(colorify.extract_hex_color("#f00")).toBe("#ff0000")
			expect(colorify.extract_hex_color("#abc")).toBe("#aabbcc")
		end)

		it("converts rgb() syntax to hex format", function()
			expect(colorify.extract_hex_color("rgb(255, 0, 128)")).toBe("#ff0080")
		end)

		it("returns nil for non-color strings or nil", function()
			expect(colorify.extract_hex_color("function foo()")).toBeNil()
			expect(colorify.extract_hex_color(nil)).toBeNil()
		end)
	end)

	describe("get_contrast_fg", function()
		it("returns dark text for light background hex values", function()
			expect(colorify.get_contrast_fg("#ffffff")).toBe("#151515")
			expect(colorify.get_contrast_fg("#e5c07b")).toBe("#151515")
		end)

		it("returns bright white text for dark background hex values", function()
			expect(colorify.get_contrast_fg("#000000")).toBe("#ffffff")
			expect(colorify.get_contrast_fg("#1e222a")).toBe("#ffffff")
		end)
	end)

	describe("get_or_create_color_hl", function()
		it("creates a dynamic highlight group name based on hex color", function()
			local hl = colorify.get_or_create_color_hl("#e06c75")
			expect(hl).toBe("CmpColor_e06c75")
		end)
	end)

	describe("get_kind_hl", function()
		it("returns CmpKindBg_ highlight name for completion kinds", function()
			expect(colorify.get_kind_hl("Function")).toBe("CmpKindBg_Function")
			expect(colorify.get_kind_hl("Snippet")).toBe("CmpKindBg_Snippet")
		end)
	end)

	describe("format_kind_label", function()
		it("wraps kind text in angle brackets", function()
			expect(colorify.format_kind_label("Snippet")).toBe("<Snippet>")
			expect(colorify.format_kind_label("Function")).toBe("<Function>")
			expect(colorify.format_kind_label("Variable")).toBe("<Variable>")
		end)

		it("handles missing or empty kind values", function()
			expect(colorify.format_kind_label(nil)).toBe("<Item>")
			expect(colorify.format_kind_label("")).toBe("<Item>")
		end)
	end)

	describe("get_kind_icon", function()
		it("returns padded icon string for known kinds", function()
			expect(colorify.get_kind_icon("Function")).toBe(" 󰊕 ")
			expect(colorify.get_kind_icon("Snippet")).toBe(" 󰩫 ")
		end)
	end)
end)
