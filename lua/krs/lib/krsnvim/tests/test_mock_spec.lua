-- Tests krsnvim.test's own mock()/spyOn() using plain assert() helpers,
-- not the test library's describe/it/expect (can't test the thing with itself).
local M = {}

local function check(cond, msg)
	assert(cond, "FAIL: " .. tostring(msg))
end

function M.run()
	local t = require("krs.lib.krsnvim.test")

	-- fn(): call tracking ------------------------------------------------
	do
		local fn = t.fn()
		check(type(fn) == "table", "t.fn() should return a table (callable via __call)")
		check(type(fn.mock) == "table" and type(fn.mock.calls) == "table", "mock.calls should exist")
		check(#fn.mock.calls == 0, "fresh mock should have zero calls")

		fn(1, 2)
		fn(3)
		check(#fn.mock.calls == 2, "expected 2 recorded calls, got " .. #fn.mock.calls)
		check(fn.mock.calls[1][1] == 1 and fn.mock.calls[1][2] == 2, "first call args not recorded correctly")
		check(fn.mock.calls[2][1] == 3, "second call args not recorded correctly")
	end

	-- fn(): mockReturnValue -----------------------------------------------
	do
		local fn = t.fn()
		fn.mockReturnValue(42)
		local result = fn()
		check(result == 42, "mockReturnValue should make mock return fixed value, got " .. tostring(result))
	end

	-- fn(): mockImplementation ---------------------------------------------
	do
		local fn = t.fn()
		fn.mockImplementation(function(x)
			return x * 2
		end)
		local result = fn(5)
		check(result == 10, "mockImplementation should run custom fn, got " .. tostring(result))
	end

	-- fn(impl): implementation passed at creation ---------------------------
	do
		local fn = t.fn(function(a, b)
			return a + b
		end)
		local result = fn(2, 3)
		check(result == 5, "t.fn(impl) should use impl as default implementation, got " .. tostring(result))
	end

	-- fn(): mockClear / mockReset --------------------------------------------
	do
		local fn = t.fn(function()
			return "x"
		end)
		fn(1)
		fn(2)
		check(#fn.mock.calls == 2, "expected 2 calls before clear")

		fn.mockClear()
		check(#fn.mock.calls == 0, "mockClear should wipe recorded calls")
		check(fn() == "x", "mockClear should NOT remove implementation")

		fn(1)
		fn.mockReset()
		check(#fn.mock.calls == 0, "mockReset should wipe recorded calls")
		check(fn() == nil, "mockReset should remove implementation/return value")
	end

	-- spyOn(): wraps original and records calls -----------------------------
	do
		local obj = {
			greet = function(name)
				return "hi " .. name
			end,
		}
		local original = obj.greet

		local spy = t.spyOn(obj, "greet")
		check(obj.greet ~= original, "spyOn should replace the method on the table")

		local result = obj.greet("bob")
		check(result == "hi bob", "spy should call through to original by default, got " .. tostring(result))
		check(#spy.mock.calls == 1, "spy should record the call")
		check(spy.mock.calls[1][1] == "bob", "spy should record call args")

		spy.mockRestore()
		check(obj.greet == original, "mockRestore should put back the original function")
		check(obj.greet("sue") == "hi sue", "restored function should behave like original")
	end

	-- spyOn(): mockImplementation overrides behavior while still tracking ---
	do
		local obj = {
			double = function(n)
				return n * 2
			end,
		}
		local spy = t.spyOn(obj, "double")
		spy.mockImplementation(function(n)
			return n * 100
		end)

		local result = obj.double(3)
		check(result == 300, "spy.mockImplementation should override call behavior, got " .. tostring(result))
		check(#spy.mock.calls == 1, "spy should still record calls after mockImplementation")

		spy.mockRestore()
		check(obj.double(3) == 6, "restored function should use original implementation")
	end

	print("  ✅ test_mock_spec passed")
end

return M
