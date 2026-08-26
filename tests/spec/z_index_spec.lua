-- ============================================================================
-- tests/spec/z_index_spec.lua -- Spec suite for krs.core.z_index manager.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach
local z_index = require("krs.core.z_index")

describe("krs.core.z_index", function()
	beforeEach(function()
		z_index.clear()
	end)

	it("allocates increasing base z-index layers for top-level UIs", function()
		local z1 = z_index.next_zindex("file_explorer")
		z_index.register("file_explorer")

		local z2 = z_index.next_zindex("git_center")
		z_index.register("git_center")

		local z3 = z_index.next_zindex("tasks")
		z_index.register("tasks")

		expect(z1).toBe(50)
		expect(z2).toBe(100)
		expect(z3).toBe(150)
		expect(z_index.active_stack()).toEqual({ "file_explorer", "git_center", "tasks" })
	end)

	it("derives child z-index relative to parent base z-index", function()
		z_index.register("git_center") -- base 50
		local log_z = z_index.next_zindex("git_center_log", { parent = "git_center", offset = 30 })

		expect(log_z).toBe(80)
	end)

	it("re-uses existing component base z-index if already registered", function()
		z_index.register("git_center")
		local z_again = z_index.next_zindex("git_center", { offset = 10 })

		expect(z_again).toBe(60)
	end)

	it("promotes component to top of stack when bring_to_front is called", function()
		z_index.register("git_center") -- base 50
		z_index.register("file_explorer") -- base 100
		expect(z_index.active_stack()).toEqual({ "git_center", "file_explorer" })

		z_index.bring_to_front("git_center")
		expect(z_index.active_stack()).toEqual({ "file_explorer", "git_center" })
		expect(z_index.get_zindex("git_center")).toBe(100)
		expect(z_index.get_zindex("file_explorer")).toBe(50)
	end)

	it("unregisters component and removes it from active stack", function()
		z_index.register("git_center")
		z_index.register("file_explorer")

		z_index.unregister("git_center")
		expect(z_index.active_stack()).toEqual({ "file_explorer" })

		-- Opening git_center again should get top layer
		local new_z = z_index.next_zindex("git_center")
		expect(new_z).toBe(150)
	end)

	it("supports re-export modules krs.core.zindex and krs.core.z-index", function()
		local mod1 = require("krs.core.zindex")
		local mod2 = require("krs.core.z-index")

		expect(mod1).toBe(z_index)
		expect(mod2).toBe(z_index)
	end)
end)
