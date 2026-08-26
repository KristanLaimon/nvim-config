-- ============================================================================
-- PLUGIN: nvim-notify -- Beautiful floating toast notifications.
-- ============================================================================
-- Features:
--   * Original `rcarriga/nvim-notify` visual look, icons, highlights & borders.
--   * Native `fade_in_slide_out` stages: ease-in-out slide entry/exit & auto slide-UP.
--   * Mobile focus protection: `on_open` enforces `focusable = false` so toasts
--     NEVER steal keyboard/touch input or freeze Neovim.
--   * Autocmd instantly restores editor focus if cursor ever touches a notify buffer.
-- ============================================================================

return {
	{
		"rcarriga/nvim-notify",
		event = "VeryLazy",
		priority = 1000,
		opts = function()
			local is_mobile = false
			local env_ok, env_mod = pcall(require, "krs.core.environment")
			if env_ok then
				local env = env_mod.detect()
				is_mobile = env.is_mobile or env.is_termux or env.is_proot
			else
				is_mobile = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
			end

			return {
				stages = is_mobile and "static" or "fade_in_slide_out",
				timeout = is_mobile and 1800 or 3000,
				top_down = true,
				render = is_mobile and "compact" or "default",
				fps = is_mobile and 5 or 30,
				max_width = function()
					local cols = vim.o.columns or 80
					if is_mobile then
						return math.max(25, math.min(45, math.floor(cols * 0.7)))
					end
					return math.max(40, math.min(120, math.floor(cols * 0.8)))
				end,
				max_height = function()
					local lines_cnt = vim.o.lines or 24
					if is_mobile then
						return math.max(3, math.min(6, math.floor(lines_cnt * 0.25)))
					end
					return math.max(8, math.min(20, math.floor(lines_cnt * 0.4)))
				end,
				background_colour = "Normal",
				on_open = function(win)
					pcall(vim.api.nvim_win_set_config, win, { focusable = false })
					pcall(vim.api.nvim_set_option_value, "wrap", true, { win = win })
					pcall(vim.api.nvim_set_option_value, "linebreak", true, { win = win })
					local buf = vim.api.nvim_win_get_buf(win)
					if buf and vim.api.nvim_buf_is_valid(buf) then
						local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
						local full_text = table.concat(lines, "\n")
						local copy_fn = function()
							local ok_hist, history = pcall(function()
								return require("notify").history()
							end)
							local text_to_copy = full_text
							if ok_hist and type(history) == "table" and #history > 0 then
								local last = history[#history]
								if last and last.message then
									text_to_copy = type(last.message) == "table" and table.concat(last.message, "\n")
										or tostring(last.message)
								end
							end
							vim.fn.setreg("+", text_to_copy)
							vim.fn.setreg("*", text_to_copy)
							vim.api.nvim_echo({ { "📋 Notification text copied to clipboard!", "DiagnosticInfo" } }, true, {})
						end

						vim.keymap.set({ "n", "v", "i" }, "<LeftMouse>", copy_fn, { buffer = buf, silent = true, noremap = true })
						vim.keymap.set({ "n", "v", "i" }, "<2-LeftMouse>", copy_fn, { buffer = buf, silent = true, noremap = true })
					end
				end,
			}
		end,
		config = function(_, opts)
			local ok, notify = pcall(require, "notify")
			if ok then
				local final_opts = type(opts) == "function" and opts() or opts
				notify.setup(final_opts)
				vim.notify = notify

				-- Autocmd: Bind single-click copy and focus protection for notify floating windows
				vim.api.nvim_create_autocmd("FileType", {
					pattern = "notify",
					callback = function(args)
						local buf = args.buf
						if buf and vim.api.nvim_buf_is_valid(buf) then
							local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
							local full_text = table.concat(lines, "\n")
							local copy_fn = function()
								local ok_hist, history = pcall(function()
									return require("notify").history()
								end)
								local text_to_copy = full_text
								if ok_hist and type(history) == "table" and #history > 0 then
									local last = history[#history]
									if last and last.message then
										text_to_copy = type(last.message) == "table" and table.concat(last.message, "\n")
											or tostring(last.message)
									end
								end
								vim.fn.setreg("+", text_to_copy)
								vim.fn.setreg("*", text_to_copy)
								vim.api.nvim_echo({ { "📋 Notification text copied to clipboard!", "DiagnosticInfo" } }, true, {})
							end

							vim.keymap.set({ "n", "v", "i" }, "<LeftMouse>", copy_fn, { buffer = buf, silent = true, noremap = true })
							vim.keymap.set(
								{ "n", "v", "i" },
								"<2-LeftMouse>",
								copy_fn,
								{ buffer = buf, silent = true, noremap = true }
							)
						end

						local win = vim.fn.bufwinid(args.buf)
						if win and win ~= -1 then
							pcall(vim.api.nvim_win_set_config, win, { focusable = false })
							pcall(vim.api.nvim_set_option_value, "wrap", true, { win = win })
							pcall(vim.api.nvim_set_option_value, "linebreak", true, { win = win })
							if vim.api.nvim_get_current_win() == win then
								local prev_win = vim.fn.win_getid(vim.fn.winnr("#"))
								vim.schedule(function()
									if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win then
										if prev_win and prev_win ~= 0 and vim.api.nvim_win_is_valid(prev_win) then
											pcall(vim.api.nvim_set_current_win, prev_win)
										else
											pcall(vim.cmd, "wincmd p")
										end
									end
								end)
							end
						end
					end,
				})

				local copy_last_notification = function()
					local ok_hist, history = pcall(function()
						return require("notify").history()
					end)
					local text_to_copy = nil
					if ok_hist and type(history) == "table" and #history > 0 then
						local last = history[#history]
						if last and last.message then
							text_to_copy = type(last.message) == "table" and table.concat(last.message, "\n")
								or tostring(last.message)
						end
					end
					if text_to_copy and text_to_copy ~= "" then
						vim.fn.setreg("+", text_to_copy)
						vim.fn.setreg("*", text_to_copy)
						vim.notify("📋 Last notification text copied to clipboard!", vim.log.levels.INFO, { title = "Clipboard" })
					else
						vim.notify("⚠️ No recent notification history found", vim.log.levels.WARN, { title = "Clipboard" })
					end
				end

				-- User commands to copy or dismiss notifications
				vim.api.nvim_create_user_command(
					"NotifyCopyLast",
					copy_last_notification,
					{ desc = "Copy last notification full text to system clipboard" }
				)

				vim.api.nvim_create_user_command("NotifyDismiss", function()
					notify.dismiss({ silent = true })
				end, { desc = "Dismiss all floating toast notifications" })

				vim.api.nvim_create_user_command("ClearToasts", function()
					notify.dismiss({ silent = true })
				end, { desc = "Dismiss all floating toast notifications" })

				-- Quick keymap to copy last notification or clear toasts
				vim.keymap.set("n", "<leader>nc", copy_last_notification, { desc = "Copy last notification full text" })

				vim.keymap.set("n", "<leader>nd", function()
					notify.dismiss({ silent = true })
				end, { desc = "Dismiss active notifications" })

				vim.keymap.set("n", "<leader>un", function()
					notify.dismiss({ silent = true })
				end, { desc = "Dismiss active notifications" })
			else
				-- Fallback to krs.core.notify
				require("krs.core.notify").setup()
			end
		end,
	},
}
