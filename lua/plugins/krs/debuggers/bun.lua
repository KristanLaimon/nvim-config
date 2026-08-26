-- ============================================================================
-- 🐰 Bun — Bun's own WebKit-inspector adapter
-- ============================================================================
-- Bun speaks the WebKit inspector protocol, not CDP, so pwa-node cannot drive
-- it. `bun_dap` checks out Bun's own adapter and gives it the stdio entry point
-- the VSCode extension never shipped. See lua/plugins/krs/bun_dap.lua.
-- ============================================================================

local shared = require("plugins.krs.debuggers._shared")

return function(dap)
	local bun_dap = require("plugins.krs.dev.bun_dap")
	if bun_dap.installed() then
		dap.adapters.bun = {
			type = "executable",
			command = "bun",
			args = { bun_dap.server },
		}
	end

	shared.add(dap, shared.web_filetypes, {
		{
			-- Bun's adapter spawns `bun --inspect-wait` itself, so no
			-- runtimeExecutable/runtimeArgs here. .ts needs no loader either.
			type = "bun",
			request = "launch",
			name = "🐰 Launch Current File (Bun)",
			program = "${file}",
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
			watchMode = false,
		},
		{
			type = "bun",
			request = "attach",
			name = "🐰 Attach to Bun (--inspect)",
			-- `bun --inspect` prints the ws:// URL it is listening on; paste it.
			url = function()
				return vim.fn.input("Bun inspector URL: ", "ws://localhost:6499/", "file")
			end,
		},
	})
end
