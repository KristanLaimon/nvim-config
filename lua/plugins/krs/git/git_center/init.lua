-- ============================================================================
-- KRS PLUGIN: Git Center (Ctrl + Shift + G) -- Stage, commit, push, review.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local config = lazy_req("plugins.krs.git.git_center.config")
local queries = lazy_req("plugins.krs.git.git_center.queries")
local render = lazy_req("plugins.krs.git.git_center.render")
local modals = lazy_req("plugins.krs.git.git_center.modals")
local panel = lazy_req("plugins.krs.git.git_center.panel")
local graph_viewer = lazy_req("plugins.krs.git.git_center.graph_viewer")
local diff_mode = lazy_req("plugins.krs.git.diff_mode")

local M = setmetatable({}, {
	__index = function(_, k)
		if k == "graph_viewer" then
			return graph_viewer
		elseif k == "open_graph_viewer" then
			return graph_viewer.open
		elseif k == "diff_mode" then
			return diff_mode
		elseif k == "open_diff_mode" then
			return diff_mode.open
		elseif k == "toggle_diff_mode" then
			return diff_mode.toggle
		elseif k == "close_diff_mode" then
			return diff_mode.close
		elseif config[k] ~= nil then
			return config[k]
		elseif queries[k] ~= nil then
			return queries[k]
		elseif render[k] ~= nil then
			return render[k]
		elseif modals[k] ~= nil then
			return modals[k]
		elseif panel[k] ~= nil then
			return panel[k]
		end
		return nil
	end,
	__newindex = function(_, k, v)
		config[k] = v
	end,
})

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

	pcall(vim.api.nvim_create_user_command, "GitGraph", function(cmd_opts)
		local mode = cmd_opts.args ~= "" and cmd_opts.args or nil
		graph_viewer.open(nil, mode)
	end, { nargs = "?", desc = "Open GitKraken-Style Commit Graph Viewer (Optional: 'branch' or 'all')" })

	pcall(vim.api.nvim_create_user_command, "GitCenterGraph", function(cmd_opts)
		local mode = cmd_opts.args ~= "" and cmd_opts.args or nil
		graph_viewer.open(nil, mode)
	end, { nargs = "?", desc = "Open GitKraken-Style Commit Graph Viewer" })

	pcall(vim.api.nvim_create_user_command, "GitDiffMode", function()
		diff_mode.open()
	end, { desc = "Open Git Diff Mode Manager (Same Branch / Between Branches)" })

	pcall(vim.api.nvim_create_user_command, "GitDiffSameBranch", function(cmd_opts)
		local n = cmd_opts.args ~= "" and tonumber(cmd_opts.args) or nil
		diff_mode.start_same_branch({ commits_behind = n })
	end, { nargs = "?", desc = "Start Git Diff Mode for Same Branch (HEAD vs HEAD~N)" })

	pcall(vim.api.nvim_create_user_command, "GitDiffBetweenBranches", function(cmd_opts)
		local args = cmd_opts.fargs or {}
		if #args >= 2 then
			diff_mode.start_between_branches(args[1], args[2])
		else
			diff_mode.open_branch_selector_modal()
		end
	end, { nargs = "*", desc = "Start Git Diff Mode Between 2 Branches (Side-by-Side)" })

	pcall(vim.api.nvim_create_user_command, "GitDiffClose", function()
		diff_mode.close()
	end, { desc = "Close Git Diff Mode" })

	pcall(vim.api.nvim_create_user_command, "GitDiffToggle", function()
		diff_mode.toggle()
	end, { desc = "Toggle Git Diff Mode (Same Branch)" })

	pcall(vim.api.nvim_create_user_command, "GitMergeSimulate", function(cmd_opts)
		local args = cmd_opts.fargs or {}
		local active_cwd = (config.get_active_target() and config.get_active_target().full_path) or vim.fn.getcwd()
		local current_branch = (queries.get_git_info(active_cwd) or {}).branch or "HEAD"
		local target = args[2] and args[1] or current_branch
		local incoming = args[2] or args[1]
		if not incoming or incoming == "" then
			modals.open_branch_modal(active_cwd)
			return
		end
		local res = queries.simulate_merge(target, incoming, active_cwd)
		modals.open_simulation_modal(res, active_cwd)
	end, { nargs = "*", desc = "Simulate Git Merge between 2 branches without altering CWD" })

	pcall(vim.api.nvim_create_user_command, "GitRebaseSimulate", function(cmd_opts)
		local args = cmd_opts.fargs or {}
		local active_cwd = (config.get_active_target() and config.get_active_target().full_path) or vim.fn.getcwd()
		local current_branch = (queries.get_git_info(active_cwd) or {}).branch or "HEAD"
		local upstream = args[2] and args[1] or current_branch
		local topic = args[2] or args[1]
		if not topic or topic == "" then
			modals.open_branch_modal(active_cwd)
			return
		end
		local res = queries.simulate_rebase(upstream, topic, active_cwd)
		modals.open_simulation_modal(res, active_cwd)
	end, { nargs = "*", desc = "Simulate Git Rebase of branch onto upstream without altering CWD" })

	pcall(vim.api.nvim_create_user_command, "GitDryRunMerge", function(cmd_opts)
		vim.cmd("GitMergeSimulate " .. (cmd_opts.args or ""))
	end, { nargs = "*", desc = "Dry-run Git Merge simulation without altering CWD" })

	pcall(vim.api.nvim_create_user_command, "GitDryRunRebase", function(cmd_opts)
		vim.cmd("GitRebaseSimulate " .. (cmd_opts.args or ""))
	end, { nargs = "*", desc = "Dry-run Git Rebase simulation without altering CWD" })

	local function reload()
		package.loaded["plugins.krs.git.git_center"] = nil
		package.loaded["plugins.krs.git.git_center.config"] = nil
		package.loaded["plugins.krs.git.git_center.queries"] = nil
		package.loaded["plugins.krs.git.git_center.render"] = nil
		package.loaded["plugins.krs.git.git_center.modals"] = nil
		package.loaded["plugins.krs.git.git_center.panel"] = nil
		package.loaded["plugins.krs.git.git_center.graph_viewer"] = nil
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
	cmd = {
		"GitCenter",
		"GitCenterStage",
		"GitCenterCommit",
		"GitCenterPush",
		"GitCenterDiff",
		"GitDiffMode",
		"GitDiffSameBranch",
		"GitDiffBetweenBranches",
		"GitDiffClose",
		"GitDiffToggle",
		"GitGraph",
		"GitCenterGraph",
		"GitMergeSimulate",
		"GitRebaseSimulate",
		"GitDryRunMerge",
	},
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
