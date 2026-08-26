local M = {}

function M.run()
	local t = require("krs.lib.krsnvim.test")
	local describe, it, expect = t.describe, t.it, t.expect

	assert(type(_G.console) == "table" or type(_G.console) == "function", "global console should be available")
	assert(type(_G.fetch) == "table" or type(_G.fetch) == "function", "global fetch should be available")
	assert(type(_G.describe) == "function", "global describe should be available")
	assert(type(_G.test) == "function", "global test should be available")
	assert(type(_G.expect) == "function", "global expect should be available")

	describe("Vitest-like Testing Framework (krsnvim.test)", function()
		it("supports toBe and isNot.toBe", function()
			expect(5).toBe(5)
			expect("hello").toBe("hello")
			expect(10)["not"].toBe(20)
			expect(10).isNot.toBe(20)
			expect(true).isNot.toBe(false)
		end)

		it("supports toEqual deep comparison", function()
			expect({ a = 1, b = { 2, 3 } }).toEqual({ a = 1, b = { 2, 3 } })
			expect({ a = 1 }).isNot.toEqual({ a = 2 })
		end)

		it("supports truthy and falsy matchers", function()
			expect(true).toBeTruthy()
			expect("non-empty").toBeTruthy()
			expect(false).toBeFalsy()
			expect(nil).toBeFalsy()
		end)

		it("supports nil and defined matchers", function()
			expect(nil).toBeNil()
			expect(nil).toBeNull()
			expect(nil).toBeUndefined()
			expect("defined").toBeDefined()
		end)

		it("supports toContain for strings and arrays", function()
			expect("krsnvimscript").toContain("nvim")
			expect({ "apple", "banana" }).toContain("banana")
			expect("krsnvimscript").isNot.toContain("python")
		end)

		it("supports toHaveLength", function()
			expect("hello").toHaveLength(5)
			expect({ 1, 2, 3 }).toHaveLength(3)
		end)

		it("supports numeric comparison matchers", function()
			expect(10).toBeGreaterThan(5)
			expect(10).toBeGreaterThanOrEqual(10)
			expect(3).toBeLessThan(5)
			expect(5).toBeLessThanOrEqual(5)
		end)

		it("supports toThrow for functions", function()
			expect(function()
				error("custom error message")
			end).toThrow("custom error")

			expect(function()
				local x = 1 + 1
			end).isNot.toThrow()
		end)

		it("supports calling module directly when named local test", function()
			local test_mod = require("krs.lib.krsnvim.test")
			expect(type(test_mod)).toBe("table")
			-- Module table is callable thanks to __call metamethod
			test_mod("direct call test", function()
				expect(100).toBe(100)
			end)
		end)
	end)

	local results = t.run()
	assert(results.passed >= 8, "Expected at least 8 tests to pass in test_framework_spec")
	assert(results.failed == 0, "Expected 0 test failures in test_framework_spec")

	print("  ✅ test_framework_spec passed")
end

return M
