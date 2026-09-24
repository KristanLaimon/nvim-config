-- ============================================================================
-- tests/spec/environments_spec.lua -- Environments manager unit tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local envs = require("plugins.krs.tools.environments")

describe("plugins.krs.tools.environments", function()
	local temp_dir
	local orig_storage_dir
	local orig_envs
	local orig_active_slot

	beforeEach(function()
		temp_dir = vim.fn.tempname()
		orig_storage_dir = envs.settings.storage_dir
		envs.settings.storage_dir = temp_dir

		orig_envs = vim.deepcopy(_G._krs_environments or {})
		orig_active_slot = _G._krs_active_env_slot or 1

		_G._krs_environments = {}
		_G._krs_active_env_slot = 1
	end)

	afterEach(function()
		envs.settings.storage_dir = orig_storage_dir
		_G._krs_environments = orig_envs
		_G._krs_active_env_slot = orig_active_slot

		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end
	end)

	it("manages slot creation and retrieval up to 9 slots", function()
		local slot1_dir = vim.fn.stdpath("config")
		local env1 = envs.create_environment(1, slot1_dir, "MyConfig", false)
		expect(env1 ~= nil).toBe(true)
		expect(env1.slot).toBe(1)
		expect(env1.name).toBe("MyConfig")

		local fetched = envs.get_environment(1)
		expect(fetched ~= nil).toBe(true)
		expect(fetched.name).toBe("MyConfig")
		expect(envs.get_active_count()).toBe(1)
		expect(envs.has_multiple_environments()).toBe(false)
		-- Indicator is empty when <= 1 environment
		expect(envs.indicator_status()).toBe("")
	end)

	it("shows statusline indicator only when > 1 environments are active", function()
		local dir1 = vim.fn.stdpath("config")
		local dir2 = vim.fn.stdpath("data")

		envs.create_environment(1, dir1, "Project1", false)
		envs.create_environment(2, dir2, "Project2", false)

		expect(envs.get_active_count()).toBe(2)
		expect(envs.has_multiple_environments()).toBe(true)

		_G._krs_active_env_slot = 1
		local ind1 = envs.indicator_status()
		expect(ind1:find("Project1") ~= nil).toBe(true)
		expect(ind1:find("%[1:") ~= nil).toBe(true)

		_G._krs_active_env_slot = 2
		local ind2 = envs.indicator_status()
		expect(ind2:find("Project2") ~= nil).toBe(true)
		expect(ind2:find("%[2:") ~= nil).toBe(true)
	end)

	it("renames an environment", function()
		local dir = vim.fn.stdpath("config")
		envs.create_environment(1, dir, "InitialName", false)

		envs.rename_environment(1, "UpdatedName")
		local env = envs.get_environment(1)
		expect(env.name).toBe("UpdatedName")
	end)

	it("filters buffers based on active environment slot", function()
		local dir1 = vim.fn.stdpath("config")
		local dir2 = vim.fn.stdpath("data")

		envs.create_environment(1, dir1, "SlotOne", false)
		envs.create_environment(2, dir2, "SlotTwo", false)

		local buf1 = vim.api.nvim_create_buf(true, false)
		vim.b[buf1].krs_env_slot = 1

		local buf2 = vim.api.nvim_create_buf(true, false)
		vim.b[buf2].krs_env_slot = 2

		_G._krs_active_env_slot = 1
		expect(envs.is_buffer_in_current_environment(buf1)).toBe(true)
		expect(envs.is_buffer_in_current_environment(buf2)).toBe(false)

		_G._krs_active_env_slot = 2
		expect(envs.is_buffer_in_current_environment(buf1)).toBe(false)
		expect(envs.is_buffer_in_current_environment(buf2)).toBe(true)

		pcall(vim.api.nvim_buf_delete, buf1, { force = true })
		pcall(vim.api.nvim_buf_delete, buf2, { force = true })
	end)

	it("closes an environment and cleans up its buffers and terminals", function()
		local dir = vim.fn.stdpath("config")
		local env = envs.create_environment(1, dir, "ToClose", false)

		local buf = vim.api.nvim_create_buf(true, false)
		vim.b[buf].krs_env_slot = 1

		local term_buf = vim.api.nvim_create_buf(true, false)
		env.terminals = { [1] = { buf = term_buf, win = nil } }

		local orig_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			return 1 -- Yes
		end

		envs.close_environment(1)
		vim.fn.confirm = orig_confirm

		expect(envs.get_environment(1)).toBe(nil)
		expect(envs.get_active_count()).toBe(0)
		expect(vim.api.nvim_buf_is_valid(buf)).toBe(false)
		expect(vim.api.nvim_buf_is_valid(term_buf)).toBe(false)
	end)

	it("persists environments state and restores correctly", function()
		local dir1 = vim.fn.stdpath("config")
		envs.create_environment(1, dir1, "PersistedEnv", false)
		envs.save_all(true)

		-- Verify index file was written
		local store = require("krs.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(index.slots["1"] ~= nil).toBe(true)
		expect(index.slots["1"].name).toBe("PersistedEnv")

		-- Clear memory
		_G._krs_environments = {}
		expect(envs.get_environment(1)).toBe(nil)

		-- Restore
		envs.restore_all()
		local restored = envs.get_environment(1)
		expect(restored ~= nil).toBe(true)
		expect(restored.name).toBe("PersistedEnv")
	end)
end)
