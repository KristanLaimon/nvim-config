-- ============================================================================
-- PLUGIN: nvim-dap -- the debugger, wired for every language this config knows.
-- ============================================================================
-- WHAT THIS FILE OWNS
--   1. mason-nvim-dap: which adapters get installed automatically.
--   2. Per-language DAP config, read from each krs.langs module's `dap_setup`
--      (function) and/or `dap_filetypes`/`dap_configs` (plain data) -- see
--      lua/krs/langs/php/init.lua for the plain-data shape and
--      lua/krs/langs/bash/init.lua for the function shape. ADD A LANGUAGE's
--      debugger there, not here; only cross-language modules (bun/node/browsers
--      -- they all debug the same JS/TS/web filetypes via js-debug, so no single
--      language owns them) stay as their own file in lua/plugins/krs/debuggers/.
--   3. `.vscode/launch.json` support: the `type` -> filetype table nvim-dap needs
--      to know which configurations apply to the file you are in.
--   4. dap-ui layout, ANSI colour in the repl, inline variable values, and the
--      breakpoint/stopped signs.
--   5. Several workarounds for js-debug and nvim 0.12 behaviour -- each is
--      commented in place with the exact reason.
--
-- KEYS
--   Bound in lua/config/keymaps/debug.lua, not here.
-- ============================================================================

return {
	{
		"mfussenegger/nvim-dap",
		cmd = {
			"DapToggleBreakpoint",
			"DapContinue",
			"DapStepOver",
			"DapStepInto",
			"DapStepOut",
			"DapTerminate",
			"DapRestart",
			"DapShowLog",
			"DapSetLogLevel",
		},
		keys = {
			{ "<F5>", desc = "Debug: Start/Continue" },
			{ "<F10>", desc = "Debug: Step Over" },
			{ "<F11>", desc = "Debug: Step Into" },
			{ "<F12>", desc = "Debug: Step Out" },
			{ "<C-b>", desc = "Toggle Breakpoint" },
		},
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"nvim-neotest/nvim-nio",
			"jay-babu/mason-nvim-dap.nvim",
			"theHamsta/nvim-dap-virtual-text",
			"leoluz/nvim-dap-go",
			"m00qek/baleia.nvim",
		},
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")

			-- nvim 0.12 defaults switchbuf to "uselast", which only reuses the current
			-- window when its buftype is "". Stop with focus in the dapui console/repl
			-- and the source lands in winnr('#') instead of the code window. Prefer a
			-- window already showing the file, then any visible one.
			dap.defaults.fallback.switchbuf = "useopen,usevisible,uselast"

			local mason_dap_ok, mason_dap = pcall(require, "mason-nvim-dap")
			if mason_dap_ok then
				mason_dap.setup({
					-- These are nvim-dap adapter names, NOT mason package names.
					-- (js -> js-debug-adapter, python -> debugpy, coreclr -> netcoredbg)
					ensure_installed = {},
					automatic_installation = false,
					handlers = {
						function(config)
							require("mason-nvim-dap").default_setup(config)
						end,
					},
				})
			end

			-- ----------------------------------------------------------------------
			-- Cross-language adapters & configurations
			-- ----------------------------------------------------------------------
			-- bun/node/browsers all debug the same JS/TS/web filetypes through
			-- js-debug (or Bun's own adapter), shared by multiple krs.langs modules
			-- (typescript, web) -- no single language module owns them, so they stay
			-- as their own file in lua/plugins/krs/debuggers/. Order here is the
			-- order they appear in the picker, so the first entry of the first
			-- module is what <F5> runs by default.
			for _, generic in ipairs({ "bun", "node", "browsers" }) do
				local ok, err = pcall(function()
					require("plugins.krs.debuggers." .. generic)(dap)
				end)
				if not ok then
					vim.notify("DAP: failed to load debugger '" .. generic .. "': " .. tostring(err), vim.log.levels.WARN)
				end
			end

			-- ----------------------------------------------------------------------
			-- Per-language adapters & configurations
			-- ----------------------------------------------------------------------
			-- Each krs.langs module owns its own debugger: `dap_setup(dap)` for
			-- anything that needs to register an adapter or build configs at
			-- runtime (bash, go, lua/krsnvimscript), or plain `dap_filetypes` +
			-- `dap_configs` for a static list (php, csharp, python). This fixed
			-- order is what the picker shows -- krs.langs.langs itself is an
			-- unordered table, so it can't be walked directly here.
			local shared = require("plugins.krs.debuggers._shared")
			local langs = require("krs.langs").langs
			for _, key in ipairs({ "python", "csharp", "php", "bash", "go", "lua" }) do
				local lang = langs[key]
				if lang then
					if lang.dap_setup then
						local ok, err = pcall(lang.dap_setup, dap)
						if not ok then
							vim.notify("DAP: failed to set up '" .. key .. "': " .. tostring(err), vim.log.levels.WARN)
						end
					end
					if lang.dap_configs and lang.dap_filetypes then
						shared.add(dap, lang.dap_filetypes, lang.dap_configs)
					end
				end
			end

			-- Standard VS Code route: if the project has .vscode/launch.json, its
			-- configurations show up in the picker alongside the ones above.
			-- load_launchjs is deprecated — nvim-dap reads .vscode/launch.json on demand
			-- now. It still needs this table to know which filetypes a `type` applies to,
			-- otherwise a config is only offered when filetype == type (so `"type": "bun"`
			-- would only ever appear in a file of filetype "bun", i.e. never).
			local web_filetypes = require("plugins.krs.debuggers._shared").web_filetypes
			require("dap.ext.vscode").type_to_filetypes = {
				bun = web_filetypes,
				["pwa-node"] = web_filetypes,
				["pwa-chrome"] = web_filetypes,
				["pwa-msedge"] = web_filetypes,
				node = web_filetypes,
				chrome = web_filetypes,
				firefox = web_filetypes,
				coreclr = langs.csharp.dap_filetypes,
				python = langs.python.dap_filetypes,
				php = langs.php.dap_filetypes,
				go = { "go" },
				bashdb = langs.bash.lsp_config.bashls.filetypes,
				bash = langs.bash.lsp_config.bashls.filetypes,
			}

			dapui.setup({
				layouts = {
					{
						-- Right, not left: keeps the code window between the file tree and
						-- the debugger instead of sandwiched between two fixed-width panels.
						-- Fractional size scales with the terminal; the default was a flat
						-- 40 columns, which crushed the code window on narrow screens.
						elements = { "scopes", "stacks", "breakpoints", "watches" },
						size = 0.24,
						position = "right",
					},
					{
						elements = { "repl", "console" },
						size = 0.26,
						position = "bottom",
					},
				},
			})

			-- nvim-dap writes adapter `output` events into the repl as plain text, so
			-- runtimes that colorize (Bun, anything with FORCE_COLOR) show literal
			-- `[0m[33m1[0m`. baleia turns those escapes back into highlights.
			-- Global: every adapter's output goes through the same two buffers.
			local baleia_ok, baleia = pcall(require, "baleia")
			if baleia_ok then
				local colorize = baleia.setup({ line_starts_at = 1 })
				vim.api.nvim_create_autocmd("FileType", {
					group = vim.api.nvim_create_augroup("KrsDapAnsi", { clear = true }),
					pattern = { "dap-repl", "dapui_console" },
					callback = function(args)
						colorize.automatically(args.buf)
					end,
				})
			end

			local virtual_text_ok, virtual_text = pcall(require, "nvim-dap-virtual-text")
			if virtual_text_ok then
				virtual_text.setup({
					-- IntelliJ-style: values sit past the end of the line, aligned at a
					-- fixed column, so code is never pushed right (the plugin default on
					-- 0.10+ is "inline", which shifts the rest of the line).
					-- virt_text_win_col is a floor: longer lines push the value further
					-- right instead of overlapping their own code.
					virt_text_pos = "eol",
					virt_text_win_col = 80,
					commented = true,
					only_first_definition = false,
					all_references = true,
					clear_on_continue = true,
					display_callback = function(variable)
						local value = variable.value:gsub("%s+", " ")
						if #value > 60 then
							value = value:sub(1, 59) .. "…"
						end
						return variable.name .. " = " .. value
					end,
				})
				-- Faint by default; only values that changed on this step stand out.
				vim.api.nvim_set_hl(0, "NvimDapVirtualText", { link = "Comment", default = true })
			end

			-- nvim-dap only jumps to the stopped frame when
			-- `reason ~= "pause" or allThreadsStopped` (dap/session.lua). js-debug always
			-- reports allThreadsStopped=false, so every pause-type stop — a `debugger`
			-- statement, pause on entry, the pause button — leaves the session stopped
			-- with no source buffer, no cursor move and no stopped-line sign. Jump for it.
			-- js-debug returns a non-zero sourceReference for scripts node ran through
			-- in-memory TypeScript stripping, even though the file exists on disk.
			-- source_to_bufnr (dap/session.lua) checks sourceReference before path, so
			-- nvim-dap opens "dap-src://<session>/<ref>/<path>" with adapter-served
			-- content: a second buffer holding the same code, no breakpoint signs, and a
			-- junk entry in the bufferline. before.stackTrace runs before nvim-dap reads
			-- the response, so dropping the ref here sends it back to the real file.
			dap.listeners.before.stackTrace["krs_prefer_disk_source"] = function(_, _, response)
				for _, frame in ipairs((response or {}).stackFrames or {}) do
					local src = frame.source
					if
						src
						and src.sourceReference
						and src.sourceReference ~= 0
						and src.path
						and vim.fn.filereadable(src.path) == 1
					then
						src.sourceReference = 0
					end
				end
			end

			dap.listeners.after.event_stopped["krs_jump_on_pause"] = function(session, body)
				if body.reason ~= "pause" or body.allThreadsStopped or not body.threadId then
					return
				end
				session:request("stackTrace", { threadId = body.threadId, startFrame = 0, levels = 1 }, function(err, resp)
					local frame = resp and resp.stackFrames and resp.stackFrames[1]
					if not err and frame and frame.source and frame.source.path then
						session:_frame_set(frame)
					end
				end)
			end

			-- Auto open/close DAP UI when debugging starts/stops.
			-- Opening on launch/attach (not on event_initialized) shows the panels
			-- immediately, so a session that never reaches "initialized" is visible.
			dap.listeners.before.launch["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.attach["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.after.event_initialized["krs_notify_status"] = function()
				vim.notify("✅ Debugger connected! Session active.", vim.log.levels.INFO, { title = "DAP Debugger" })
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_terminated["krs_notify_status"] = function()
				vim.notify("🏁 Debug session terminated.", vim.log.levels.INFO, { title = "DAP Debugger" })
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end

			-- Custom Breakpoint and Execution line signs.
			-- DapBreakpointRejected ("R") is what nvim-dap shows when the adapter refuses
			-- to bind a breakpoint — usually the file never got loaded by the running
			-- program, or its source map does not line up.
			vim.fn.sign_define("DapBreakpoint", { text = "🦊", texthl = "DapBreakpoint", linehl = "", numhl = "" })
			vim.fn.sign_define("DapBreakpointCondition", { text = "🔶", texthl = "DapBreakpoint", linehl = "", numhl = "" })
			vim.fn.sign_define(
				"DapBreakpointRejected",
				{ text = "⭕", texthl = "DapBreakpointRejected", linehl = "", numhl = "" }
			)
			vim.fn.sign_define("DapLogPoint", { text = "💬", texthl = "DapLogPoint", linehl = "", numhl = "" })
			vim.fn.sign_define("DapStopped", { text = "🟡", texthl = "DapStopped", linehl = "DebugHighlight", numhl = "" })

			-- These highlight groups were referenced above but never defined, so the
			-- stopped line rendered with no highlight at all. Re-applied on colorscheme
			-- changes because :colorscheme clears user-defined groups.
			local function define_dap_highlights()
				vim.api.nvim_set_hl(0, "DebugHighlight", { bg = "#3a2f1b", default = true })
				vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#e06c75", default = true })
				vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = "#7f848e", default = true })
				vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef", default = true })
				vim.api.nvim_set_hl(0, "DapStopped", { fg = "#e5c07b", default = true })
			end
			define_dap_highlights()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("KrsDapHighlights", { clear = true }),
				callback = define_dap_highlights,
			})
		end,
	},
}
