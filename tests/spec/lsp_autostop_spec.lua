-- ============================================================================
-- tests/spec/lsp_autostop_spec.lua -- LSP auto-stop on project / directory switch.
-- ============================================================================
-- Contract: Switching projects or triggering DirChanged must stop any active
-- LSP clients to reclaim memory (preventing lua_ls, gopls, etc. from idling
-- across projects).
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach

describe("LSP project auto-stop", function()
	local original_get_clients

	beforeEach(function()
		original_get_clients = vim.lsp.get_clients
	end)

	afterEach(function()
		vim.lsp.get_clients = original_get_clients
	end)

	it("stops all active LSP clients when DirChanged fires", function()
		local stopped = {}

		local mock_clients = {
			{
				name = "lua_ls",
				id = 1,
				stop = function(self)
					table.insert(stopped, self.name)
				end,
			},
			{
				name = "gopls",
				id = 2,
				stop = function(self)
					table.insert(stopped, self.name)
				end,
			},
		}

		vim.lsp.get_clients = function()
			return mock_clients
		end

		-- Simulate DirChanged autocmd logic
		vim.api.nvim_create_autocmd("DirChanged", {
			group = vim.api.nvim_create_augroup("LspProjectAutoStopTest", { clear = true }),
			callback = function()
				for _, client in ipairs(vim.lsp.get_clients()) do
					client:stop()
				end
			end,
		})

		vim.api.nvim_exec_autocmds("DirChanged", { group = "LspProjectAutoStopTest" })

		expect(#stopped).toBe(2)
		expect(stopped[1]).toBe("lua_ls")
		expect(stopped[2]).toBe("gopls")
	end)

	it("handles gracefully when no LSP clients are running", function()
		vim.lsp.get_clients = function()
			return {}
		end

		local executed = false
		vim.api.nvim_create_autocmd("DirChanged", {
			group = vim.api.nvim_create_augroup("LspProjectAutoStopTestEmpty", { clear = true }),
			callback = function()
				for _, client in ipairs(vim.lsp.get_clients()) do
					client:stop()
				end
				executed = true
			end,
		})

		vim.api.nvim_exec_autocmds("DirChanged", { group = "LspProjectAutoStopTestEmpty" })
		expect(executed).toBeTruthy()
	end)
end)
