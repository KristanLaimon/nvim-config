-- ============================================================================
-- tests/spec/keymap_registry_spec.lua -- Keymap collision toast test.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("keymap_registry", function()
	local function with_stub_notify(fn)
		local calls = {}
		local raw_notify = vim.notify
		vim.notify = function(msg, level, opts)
			table.insert(calls, { msg = msg, level = level, opts = opts })
		end
		local ok, err = pcall(fn, calls)
		vim.notify = raw_notify
		if not ok then
			error(err, 0)
		end
	end

	it("toasts on a real mode+lhs+scope collision", function()
		with_stub_notify(function(calls)
			local registry = require("krs.core.keymap_registry")
			registry.install()

			vim.keymap.set("n", "<F13>", function() end, { desc = "first" })
			vim.keymap.set("n", "<F13>", function() end, { desc = "second" })

			-- The toast fires via vim.schedule (safe from fast event contexts),
			-- so it lands on the next event loop tick, not synchronously here.
			vim.wait(100, function()
				return #calls > 0
			end)
            if #calls ~= 1 then
                for i, c in ipairs(calls) do
                    print("CALL", i, c.msg)
                end
            end
			expect(#calls).toBe(1)
			expect(calls[1].opts.title).toBe("Keymap collision")
			expect(calls[1].opts.max_width).toBe(120)
			expect(type(calls[1].opts.on_open)).toBe("function")
			expect(calls[1].opts.timeout).toBe(nil)
			expect(calls[1].level).toBe(vim.log.levels.WARN)

			vim.keymap.del("n", "<F13>")
		end)
	end)

	it("does not toast for different modes or different buffers", function()
		with_stub_notify(function(calls)
			local registry = require("krs.core.keymap_registry")
			registry.install()

			vim.keymap.set("n", "<F14>", function() end, {})
			vim.keymap.set("i", "<F14>", function() end, {})
			vim.keymap.set("n", "<F14>", function() end, { buffer = 0 })

			expect(#calls).toBe(0)

			vim.keymap.del("n", "<F14>", { buffer = 0 })
			vim.keymap.del("n", "<F14>")
			vim.keymap.del("i", "<F14>")
		end)
	end)

	it("silences a collision whose source matches the lazy stub handler pattern", function()
		with_stub_notify(function(calls)
			local registry = require("krs.core.keymap_registry")
			registry.install()
			local raw_patterns = registry.ALLOWLIST_SOURCE_PATTERNS
			registry.ALLOWLIST_SOURCE_PATTERNS = { "keymap_registry_spec%.lua" }

			vim.keymap.set("n", "<F15>", function() end, {})
			vim.keymap.set("n", "<F15>", function() end, {})

			expect(#calls).toBe(0)

			registry.ALLOWLIST_SOURCE_PATTERNS = raw_patterns
			vim.keymap.del("n", "<F15>")
		end)
	end)

	it("still binds the key even when a collision is detected", function()
		with_stub_notify(function()
			local registry = require("krs.core.keymap_registry")
			registry.install()

			vim.keymap.set("n", "<F16>", "<Nop>", {})
			vim.keymap.set("n", "<F16>", "<Nop>", { desc = "override" })

			local maps = vim.api.nvim_get_keymap("n")
			local found = false
			for _, m in ipairs(maps) do
				if m.lhs == "<F16>" then
					found = true
				end
			end
			expect(found).toBe(true)

			vim.keymap.del("n", "<F16>")
			vim.wait(50)
		end)
	end)

	it("clears tracked state when reset() is called so reloads do not toast", function()
		with_stub_notify(function(calls)
			local registry = require("krs.core.keymap_registry")
			registry.install()
			registry.reset()

			vim.keymap.set("n", "<F17>", function() end, { desc = "first bind" })
			registry.reset()
			vim.keymap.set("n", "<F17>", function() end, { desc = "after reload" })

			expect(#calls).toBe(0)
			expect(#registry.collisions).toBe(0)

			vim.keymap.del("n", "<F17>")
		end)
	end)

	it("allowlists runtime ftplugin and string chunk keymaps", function()
		with_stub_notify(function(calls)
			local registry = require("krs.core.keymap_registry")
			registry.install()

			-- Simulate keymap bind from runtime/ftplugin/markdown.lua
			local has_runtime = false
			for _, pat in ipairs(registry.ALLOWLIST_SOURCE_PATTERNS) do
				if ("share/nvim/runtime/ftplugin/markdown.lua"):find(pat) or ('[string "?"]:750'):find(pat) then
					has_runtime = true
				end
			end
			expect(has_runtime).toBe(true)
		end)
	end)

	it("safely handles nil or non-string lhs without crashing", function()
		with_stub_notify(function()
			local registry = require("krs.core.keymap_registry")
			registry.install()

			-- Nil shortcut
			local ok_nil, err_nil = pcall(function()
				vim.keymap.set("n", nil, function() end)
			end)
			expect(ok_nil).toBe(true)
			expect(err_nil).toBe(nil)

			-- Empty string shortcut
			local ok_empty, err_empty = pcall(function()
				vim.keymap.set("n", "", function() end)
			end)
			expect(ok_empty).toBe(true)
			expect(err_empty).toBe(nil)

			-- False shortcut
			local ok_false, err_false = pcall(function()
				vim.keymap.set("n", false, function() end)
			end)
			expect(ok_false).toBe(true)
			expect(err_false).toBe(nil)

			-- Table containing valid shortcut along with nil and empty string
			local ok_table, err_table = pcall(function()
				vim.keymap.set("n", { "<F18>", nil, "" }, function() end, { desc = "mixed table" })
			end)
			expect(ok_table).toBe(true)
			expect(err_table).toBe(nil)

			local maps = vim.api.nvim_get_keymap("n")
			local found_f18 = false
			for _, m in ipairs(maps) do
				if m.lhs == "<F18>" then
					found_f18 = true
				end
			end
			expect(found_f18).toBe(true)
			vim.keymap.del("n", "<F18>")
		end)
	end)
end)
