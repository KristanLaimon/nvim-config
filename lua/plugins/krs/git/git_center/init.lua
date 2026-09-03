-- ============================================================================
-- KRS PLUGIN: Git Center (Ctrl + Shift + G) -- Stage, commit, push, review.
-- ============================================================================

local config = require("plugins.krs.git.git_center.config")
local queries = require("plugins.krs.git.git_center.queries")
local render = require("plugins.krs.git.git_center.render")
local modals = require("plugins.krs.git.git_center.modals")
local panel = require("plugins.krs.git.git_center.panel")

local M = config

-- Re-export queries
M.git_lines = queries.git_lines
M.git_run = queries.git_run
M.get_git_info = queries.get_git_info
M.raw_diff_for = queries.raw_diff_for
M.stage_all_with_modal = queries.stage_all_with_modal

-- Re-export render
M.submodule_statuses = render.submodule_statuses
M.fetching_submodules = render.fetching_submodules
M.toggle_colored_tab_indicators = render.toggle_colored_tab_indicators
M.render_tab_bar = render.render_tab_bar
M.build_panel_content = render.build_panel_content

-- Re-export modals
M.open_branch_modal = modals.open_branch_modal
M.open_commit_log_modal = modals.open_commit_log_modal
M.open_diff_modal = modals.open_diff_modal

-- Re-export panel & window controls
M.is_open = panel.is_open
M.resize_split = panel.resize_split
M.close_git_center = panel.close_git_center
M.open_file_in_tab = panel.open_file_in_tab
M.toggle_git_center = panel.toggle_git_center
M.open_git_center = panel.open_git_center

--- Registers user commands and global keymaps.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	pcall(vim.api.nvim_create_user_command, "GitCenter", function()
		M.toggle_git_center()
	end, { desc = "Toggle Git Control Center" })

	pcall(vim.api.nvim_create_user_command, "GitStageAll", function()
		M.stage_all_with_modal()
	end, { desc = "Stage All Unstaged & Untracked Changes with Modal Confirmation" })

	pcall(vim.api.nvim_create_user_command, "GitLog", function()
		M.open_commit_log_modal()
	end, { desc = "Open Git Commit Log & History Viewer" })

	pcall(vim.api.nvim_create_user_command, "GitHistory", function()
		M.open_commit_log_modal()
	end, { desc = "Open Git Commit Log & History Viewer" })

	local function reload()
		package.loaded["plugins.krs.git.git_center"] = nil
		package.loaded["plugins.krs.git.git_center.config"] = nil
		package.loaded["plugins.krs.git.git_center.queries"] = nil
		package.loaded["plugins.krs.git.git_center.render"] = nil
		package.loaded["plugins.krs.git.git_center.modals"] = nil
		package.loaded["plugins.krs.git.git_center.panel"] = nil
		_G.GitCenter = nil
		local reloaded = require("plugins.krs.git.git_center")
		if reloaded and reloaded.config then
			reloaded.config()
		end
		M.notify("🐙 Git Control Center reloaded successfully!")
	end

	for _, name in ipairs({ "GitCenterReload", "ReloadGitCenter" }) do
		pcall(vim.api.nvim_create_user_command, name, reload, { desc = "Reload Git Control Center" })
	end

	pcall(vim.api.nvim_create_user_command, "GitCenterToggleTabColors", function()
		M.toggle_colored_tab_indicators()
	end, { desc = "Toggle Git Center Colored Tab Indicators" })

	pcall(vim.api.nvim_create_user_command, "GitCenterToggle", function()
		M.toggle_git_center()
	end, { desc = "Toggle Git Control Center" })

	local function from_any_mode(fn)
		return function()
			local cur_buf = vim.api.nvim_get_current_buf()
			local is_term = vim.bo[cur_buf].buftype == "terminal" or vim.b[cur_buf].krs_is_multi_term
			local mode = vim.fn.mode()

			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end

			fn()

			if is_term and mode == "t" then
				vim.schedule(function()
					if vim.api.nvim_get_current_buf() == cur_buf then
						pcall(vim.cmd, "startinsert")
					end
				end)
			end
		end
	end

	for _, key in ipairs(M.settings.keys.toggle) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.toggle_git_center), {
			noremap = true,
			silent = true,
			desc = "Toggle Git Control Center",
		})
	end
	for _, key in ipairs(M.settings.keys.stage_all) do
		vim.keymap.set(
			{ "n", "i", "v", "t" },
			key,
			from_any_mode(function()
				M.stage_all_with_modal()
			end),
			{
				noremap = true,
				silent = true,
				desc = "Stage All Unstaged & Untracked Changes (Modal Confirmation)",
			}
		)
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.GitCenter = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_git_center",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "GitCenter", "GitCenterStage", "GitCenterCommit", "GitCenterPush", "GitCenterDiff" },
	keys = {
		{ "<C-S-g>", mode = { "n", "i", "v", "t" }, desc = "Open Git Control Center" },
		{ "<leader>gc", mode = { "n", "v" }, desc = "Open Git Control Center" },
		{ "<leader>gC", mode = { "n", "v" }, desc = "Open Git Control Center" },
		{ "<C-S-x>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<C-S-X>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<A-s>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<M-s>", mode = { "n", "i", "v", "t" }, desc = "Stage All Git Changes" },
		{ "<leader>gs", mode = { "n", "v" }, desc = "Stage All Git Changes" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"sindrets/diffview.nvim",
		"nvim-telescope/telescope.nvim",
	},
	config = M.setup,
}, { __index = M })
