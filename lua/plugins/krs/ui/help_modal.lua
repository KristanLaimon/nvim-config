-- ============================================================================
-- KRS PLUGIN: Help Menu & Runtime Cheatsheet Manager (<F1>).
-- ============================================================================
-- WHAT IT DOES
--   An interactive dual-pane Cheatsheet Manager & Help Menu.
--   Left panel: Categorized index of editor features & domains.
--   Right panel: Live cheatsheet showing active runtime shortcuts dynamically
--                discovered from Neovim's keymap registry (NO hardcoded keys).
--
-- GUIDELINES RESPECTED
--   - Runtime discovery: Introspects vim.api.nvim_get_keymap across modes (n, v, i, t).
--   - Leader key filter: Omit all <leader>### shortcuts, keeping ONLY <leader>ee.
--   - Topics: Neo-tree, Environments, Git-Center, InTab, Terminal, and workflow tools.
--   - Usable with <F1> across Normal, Visual, Insert, and Terminal modes.
-- ============================================================================

local ui = require("krs.core.ui")
local zindex = require("krs.core.z_index")
local lazy_req = require("krs.core.lazy_require")

local M = {}

M.settings = {
	keys = {
		open = { "<F1>", "<leader>?", "<C-F1>" },
	},
	left_width_ratio = 0.32,
	min_left_width = 28,
}

--- Active session state.
local state = {
	is_open = false,
	left_buf = nil,
	left_win = nil,
	right_buf = nil,
	right_win = nil,
	active_topic_id = nil,
	topics = {},
	augroup = nil,
}

-- -----------------------------------------------------------------------------
-- 1. Topics Definition
-- -----------------------------------------------------------------------------

M.topic_catalog = {
	{
		id = "environments",
		icon = "🌐",
		title = "Environments",
		desc = "Multi-CWD project slots (1..9), isolated LSP runtimes, and scoped terminals.",
		match_patterns = { "environment", "environments", "env_slot" },
		primary_actions = {
			{
				name = "Environment Slots 1..9",
				desc = "Directly hop between project slots 1 to 9",
				patterns = { "<C-S-%d>", "<C-S-[1-9]>" },
				cmd = ":EnvironmentsSwitch <num>",
			},
			{
				name = "Environments CRUD Menu",
				desc = "Open full management modal (create, rename, switch, delete slots)",
				patterns = { "<C-S-E>", "<C-S-e>", "ee", "<leader>ee" },
				cmd = ":EnvironmentsMenu",
			},
		},
		tips = {
			"Each environment runs its own independent CWD and scoped language servers.",
			"When more than 1 environment is active, the statusline displays the active slot pill.",
			"Windows Terminal tab hotkeys (Ctrl+Shift+1..9) are hijacked to flow straight to Neovim.",
		},
	},
	{
		id = "git_center",
		icon = "🐙",
		title = "Git-Center",
		desc = "Visual version control, side-by-side diffs, branch management, and staging.",
		match_patterns = { "git", "diff", "stage", "conflict" },
		primary_actions = {
			{
				name = "Open Git Control Center",
				desc = "Toggle full Git Center dashboard modal",
				patterns = { "<C-S-G>", "<C-S-g>", "<C-G>", "<C-g>" },
				cmd = ":GitCenter",
			},
			{
				name = "Stage All Changes",
				desc = "Stage every unstaged and untracked file with confirmation",
				patterns = { "<C-S-X>", "<C-S-x>", "<M-s>", "<A-s>", "<M-S>", "<A-S>" },
				cmd = ":GitStageAll",
			},
			{
				name = "Jump Next Modification / Diff",
				desc = "Navigate forward between changed hunks in diff mode",
				patterns = { "%]d" },
				cmd = "[d / ]d",
			},
			{
				name = "Jump Prev Modification / Diff",
				desc = "Navigate backward between changed hunks in diff mode",
				patterns = { "%[d" },
				cmd = "[d / ]d",
			},
			{
				name = "Git Conflict 3-Way Resolver",
				desc = "Interactive merge conflict split editor",
				patterns = { "conflict" },
				cmd = ":GitConflictResolve",
			},
		},
		tips = {
			"Binary files (.zip, .img, .png, .exe, etc.) are safely blacklisted from text diffs.",
			"Press 'q' in any Git Center preview or diff modal to instantly dismiss it.",
		},
	},
	{
		id = "neotree",
		icon = "📁",
		title = "Neo-tree",
		desc = "Docked and floating file explorer sidebar with git status and file operations.",
		match_patterns = { "neo%-tree", "neotree", "explorer", "sidebar" },
		primary_actions = {
			{
				name = "Toggle Neo-tree Sidebar",
				desc = "Open or close left file explorer sidebar",
				patterns = { "<C-e>", "<C-E>", "<C-S-Space>" },
				cmd = ":Neotree toggle",
			},
			{
				name = "Reveal Current File",
				desc = "Reveal and highlight active buffer in file tree",
				patterns = { "reveal" },
				cmd = ":Neotree reveal",
			},
			{
				name = "Floating Desktop Explorer",
				desc = "Full-featured popup file manager window",
				patterns = { "<C-/>", "<C-_>" },
				cmd = ":DesktopExplorer",
			},
		},
		tips = {
			"Press 'a' inside Neo-tree to create files or folders (append '/' for folders).",
			"Press 'd' to delete, 'r' to rename, and 'c' to copy files.",
		},
	},
	{
		id = "intab",
		icon = "📑",
		title = "InTab",
		desc = "Tab bar management, buffer cycling, pinning, and automatic memory cleanup.",
		match_patterns = { "buffer", "bnext", "bprev", "bufferline", "pin_tab", "cleaner" },
		primary_actions = {
			{
				name = "Cycle Next Buffer Tab",
				desc = "Hop to the next buffer tab on the right",
				patterns = { "<A-l>", "<M-l>", "<A-Right>", "<M-Right>" },
				cmd = ":bnext",
			},
			{
				name = "Cycle Previous Buffer Tab",
				desc = "Hop to the previous buffer tab on the left",
				patterns = { "<A-h>", "<M-h>", "<A-Left>", "<M-Left>" },
				cmd = ":bprev",
			},
			{
				name = "Close Active Buffer Tab",
				desc = "Smart close without breaking window splits",
				patterns = { "<C-w>" },
				cmd = ":KrsQ / :bdelete",
			},
			{
				name = "Pin / Unpin Tab",
				desc = "Pin tab so it stays protected from automatic buffer cleanup",
				patterns = { "<C-A-p>", "<C-A-P>", "<C-p>", "<C-P>", "<A-p>", "<M-p>" },
				cmd = ":BufferLineTogglePin",
			},
		},
		tips = {
			"Pinned tabs stay permanently docked to the left of the tabline.",
			"When switching environments, InTab buffers automatically filter to the active CWD.",
		},
	},
	{
		id = "terminal",
		icon = "🖥️",
		title = "Terminal",
		desc = "9 persistent background terminal slots with height memory and auto-focus.",
		match_patterns = { "terminal", "multiterm", "term" },
		primary_actions = {
			{
				name = "Toggle Terminal Panel",
				desc = "Show / hide the active multi-terminal bottom drawer",
				patterns = { "<C-;>", "<M-;>", "<F4>" },
				cmd = ":TerminalToggle",
			},
			{
				name = "Terminal Slots 1..9",
				desc = "Instantly switch between background terminal instances 1 to 9",
				patterns = { "<A-%d>", "<M-%d>", "<A-[1-9]>" },
				cmd = ":TerminalSlot <num>",
			},
			{
				name = "Resize Terminal Height Up",
				desc = "Expand terminal drawer height by 2 rows",
				patterns = { "<C-Up>", "<C-S-Up>" },
				cmd = ":resize +2",
			},
			{
				name = "Resize Terminal Height Down",
				desc = "Shrink terminal drawer height by 2 rows",
				patterns = { "<C-Down>", "<C-S-Down>" },
				cmd = ":resize -2",
			},
			{
				name = "Paste OS Clipboard into Terminal",
				desc = "Directly paste system clipboard in terminal mode",
				patterns = { "<C-S-v>", "<C-S-V>", "<C-v>" },
				cmd = '"+p',
			},
		},
		tips = {
			"Terminals remain running in the background even when closed or toggled off.",
			"Each Environment slot can maintain its own scoped terminal session.",
		},
	},
	{
		id = "tasks",
		icon = "🛠️",
		title = "Task Runner",
		desc = "Auto-discovered project build & test tasks with 4 background output slots.",
		match_patterns = { "task", "run_me", "build", "output" },
		primary_actions = {
			{
				name = "Project Tasks Menu",
				desc = "Fuzzy picker for project package.json, Makefile, and custom tasks",
				patterns = { "<C-S-T>", "<C-S-t>" },
				cmd = ":TaskMenu",
			},
			{
				name = "Run Default Project Task",
				desc = "Quick-trigger the project's designated primary build task",
				patterns = { "<C-S-A>", "<C-S-a>", "<C-A>" },
				cmd = ":TaskDefault",
			},
			{
				name = "Task Output Slots 1..4",
				desc = "Toggle dedicated output drawers for background jobs 1 to 4",
				patterns = { "<C-%d>", "<C-[1-4]>" },
				cmd = ":TaskSlot <num>",
			},
			{
				name = "Toggle Last Task Output",
				desc = "Quickly inspect output from the most recent task run",
				patterns = { "<F7>" },
				cmd = ":TaskLastOutput",
			},
		},
		tips = {
			"Tasks are configured in .krsnvim/tasks.json or auto-detected from build tools.",
		},
	},
	{
		id = "launch",
		icon = "🚀",
		title = "Launch & Debug",
		desc = "VSCode-compatible launch.json profiles, DAP interactive stepping, and breakpoints.",
		match_patterns = { "launch", "dap", "debug", "breakpoint", "step" },
		primary_actions = {
			{
				name = "Launch Profiles Manager",
				desc = "Picker for .krsnvim/launch.json and .vscode/launch.json profiles",
				patterns = { "<C-S-Q>", "<C-S-q>", "<C-Q>" },
				cmd = ":LaunchProfiles",
			},
			{
				name = "Smart Launch / Default Profile",
				desc = "Execute the active runtime launch profile",
				patterns = { "<C-S-S>", "<C-S-s>", "<C-S>" },
				cmd = ":LaunchSmart",
			},
			{
				name = "DAP Continue / Start",
				desc = "Start interactive debugging session or continue execution",
				patterns = { "<F5>" },
				cmd = ":DapContinue",
			},
			{
				name = "Toggle Persistent Breakpoint",
				desc = "Set / unset breakpoint on active buffer line",
				patterns = { "<C-b>", "<C-B>" },
				cmd = ":DapToggleBreakpoint",
			},
			{
				name = "DAP Step Over / Into / Out",
				desc = "Step through code execution in debugger",
				patterns = { "<F10>", "<F11>", "<F12>" },
				cmd = "<F10> / <F11> / <F12>",
			},
		},
		tips = {
			"Breakpoints are persisted across editor restarts in .krsnvim/breakpoints.json.",
		},
	},
	{
		id = "workspaces",
		icon = "🗂️",
		title = "Workspaces",
		desc = "Session manager preserving tabs, splits, cursor positions, and project context.",
		match_patterns = { "workspace", "session" },
		primary_actions = {
			{
				name = "Workspaces UI",
				desc = "Open interactive workspace session switcher modal",
				patterns = { "<C-S-W>", "<C-S-w>" },
				cmd = ":WorkspaceOpen",
			},
			{
				name = "Save Current Workspace",
				desc = "Snapshot open files, window layouts, and active tabs",
				patterns = { "save" },
				cmd = ":WorkspaceSave",
			},
		},
		tips = {
			"Sessions are saved cleanly under stdpath('data')/sessions.",
		},
	},
	{
		id = "palette",
		icon = "🧰",
		title = "Command Palette",
		desc = "Fuzzy action center, recent files, and global editor navigation.",
		match_patterns = { "palette", "command", "picker" },
		primary_actions = {
			{
				name = "Open Command Palette",
				desc = "Global search & action runner for all KrsVim features",
				patterns = { "<C-S-P>", "<C-S-p>", "cp" },
				cmd = ":CommandPalette",
			},
			{
				name = "Find Files (Fuzzy)",
				desc = "Quickly search and jump to files in project",
				patterns = { "<C-_>", "<C-/>", "<C-k>", "<C-K>" },
				cmd = ":Telescope find_files",
			},
			{
				name = "Recent Projects UI",
				desc = "Browse and reopen recently visited workspace folders",
				patterns = { "<C-S-R>", "<C-S-r>", "<C-R>" },
				cmd = ":RecentProjects",
			},
		},
		tips = {
			"Prefer Command Palette (<C-S-p>) commands over memorizing leader shortcuts.",
		},
	},
	{
		id = "editor",
		icon = "✂️",
		title = "Editor & Navigation",
		desc = "Window splitting, clipboard synchronization, undo/redo, and folding.",
		match_patterns = { "window", "undo", "redo", "comment", "fold", "save" },
		primary_actions = {
			{
				name = "Save File",
				desc = "Write buffer to disk with automatic formatting",
				patterns = { "<C-s>", "<C-S>" },
				cmd = ":w",
			},
			{
				name = "System Clipboard Copy",
				desc = "Copy text directly to OS system clipboard",
				patterns = { "<C-c>", "<C-S-c>" },
				cmd = '"+y',
			},
			{
				name = "System Clipboard Paste",
				desc = "Paste text from OS system clipboard",
				patterns = { "<C-v>", "<C-S-v>" },
				cmd = '"+p',
			},
			{
				name = "Undo / Redo",
				desc = "Navigate edit history tree",
				patterns = { "<C-z>", "<C-y>", "<C-S-z>" },
				cmd = "u / Ctrl+R",
			},
			{
				name = "Toggle Comment",
				desc = "Comment or uncomment active line or visual block",
				patterns = { "<C-'>", '<C-">', "<C-`>", "<C-~>", "<C-/>" },
				cmd = "gcc",
			},
			{
				name = "Toggle Fold",
				desc = "Fold or unfold code blocks, HTML tags, or functions",
				patterns = { "<A-y>", "<M-y>", "<A-Y>", "<M-Y>" },
				cmd = "za",
			},
			{
				name = "Window Left / Right / Down / Up",
				desc = "Move cursor focus between editor splits",
				patterns = { "<C-h>", "<C-l>", "<C-j>", "<C-S-A-k>" },
				cmd = "Ctrl+h/j/k/l",
			},
		},
		tips = {
			"Smart Quit (<C-w>) safely closes floating windows, sidebars, and buffers in order.",
		},
	},
}

-- -----------------------------------------------------------------------------
-- 2. Runtime Keymap Discovery & Normalization
-- -----------------------------------------------------------------------------

--- Cleans and formats a raw Neovim LHS key into a human-friendly string.
--- E.g., "<C-S-e>" -> "Ctrl+Shift+E", "<C-;>" -> "Ctrl+;", "<A-1>" -> "Alt+1".
--- @param lhs string
--- @return string
function M.format_key(lhs)
	if not lhs or lhs == "" then
		return ""
	end

	-- Handle <leader>ee specifically
	if lhs == " ee" or lhs:lower() == "<leader>ee" then
		return "Space + e + e"
	end

	local k = lhs
	-- Replace modifier tags with standardized display tokens
	k = k:gsub("<[cC]%-[sS]%-([%w%p])>", "Ctrl+Shift+%1")
	k = k:gsub("<[cC]%-([%w%p])>", "Ctrl+%1")
	k = k:gsub("<[aA]%-([%w%p])>", "Alt+%1")
	k = k:gsub("<[mM]%-([%w%p])>", "Alt+%1")
	k = k:gsub("<[sS]%-([%w%p])>", "Shift+%1")
	k = k:gsub("<[fF](%d+)>", "F%1")
	k = k:gsub("<[cC][rR]>", "Enter")
	k = k:gsub("<[eE][sS][cC]>", "Esc")
	k = k:gsub("<[sS][pP][aA][cC][eE]>", "Space")
	k = k:gsub("<[bB][sS][lL][aA][sS][hH]>", "\\")
	k = k:gsub("<[bB][aA][rR]>", "|")

	return k
end

--- Collects all active runtime keymaps across modes without hardcoding.
--- Enforces user rule: discard <leader>### shortcuts, allowing only <leader>ee.
--- @return table[] keymaps
function M.collect_runtime_keymaps()
	local all_maps = {}
	local seen = {}
	local modes = { "n", "v", "i", "t" }

	for _, mode in ipairs(modes) do
		local maps = vim.api.nvim_get_keymap(mode)
		for _, km in ipairs(maps) do
			local lhs = km.lhs or ""
			local desc = km.desc or ""
			local rhs = km.rhs or ""

			-- Rule: Avoid <leader>### shortcuts, just leave <leader>ee
			local is_leader = lhs:find("^ ") or lhs:lower():find("^<leader>") or lhs:lower():find("^<space>")
			local is_allowed_leader = (lhs == " ee" or lhs:lower() == "<leader>ee")

			if not is_leader or is_allowed_leader then
				-- Skip raw escape aliases like <Esc>[46;5u
				local is_raw_escape = lhs:find("^<Esc>%[") or lhs:find("^<M-%[") or lhs:find("^<Esc>%.")
				if not is_raw_escape then
					local uniq_key = mode .. ":" .. lhs
					if not seen[uniq_key] then
						seen[uniq_key] = true
						table.insert(all_maps, {
							lhs = lhs,
							display_key = M.format_key(lhs),
							desc = desc,
							rhs = rhs,
							mode = mode,
						})
					end
				end
			end
		end
	end

	return all_maps
end

--- Finds active runtime keymaps matching an action's pattern criteria.
--- @param all_maps table[]
--- @param patterns string[]
--- @return table[] matches
local function find_matching_runtime_keys(all_maps, patterns)
	local matches = {}
	local seen_display = {}

	for _, km in ipairs(all_maps) do
		for _, pat in ipairs(patterns) do
			local matched = false
			if pat:find("^<") then
				-- Pattern targeting LHS
				if km.lhs:lower():match(pat:lower()) then
					matched = true
				end
			else
				-- Pattern targeting description or rhs
				if (km.desc and km.desc:lower():match(pat:lower())) or (km.rhs and km.rhs:lower():match(pat:lower())) then
					matched = true
				end
			end

			if matched and not seen_display[km.display_key] then
				seen_display[km.display_key] = true
				table.insert(matches, km)
				break
			end
		end
	end

	return matches
end

--- Builds runtime cheatsheet items for a specific topic.
--- @param topic table
--- @param all_maps table[]
--- @return table[] items
function M.build_topic_cheatsheet(topic, all_maps)
	local items = {}

	-- 1. Primary curated actions resolved with runtime keys
	for _, action in ipairs(topic.primary_actions or {}) do
		local matched_keys = find_matching_runtime_keys(all_maps, action.patterns)
		local key_labels = {}
		local mode_labels = {}

		for _, mk in ipairs(matched_keys) do
			table.insert(key_labels, mk.display_key)
			local m_name = mk.mode == "n" and "Normal" or (mk.mode == "t" and "Terminal" or mk.mode:upper())
			if not vim.tbl_contains(mode_labels, m_name) then
				table.insert(mode_labels, m_name)
			end
		end

		local display_chord = #key_labels > 0 and table.concat(key_labels, " / ")
			or "(No shortcut bound)"

		table.insert(items, {
			name = action.name,
			desc = action.desc,
			chord = display_chord,
			modes = #mode_labels > 0 and table.concat(mode_labels, ", ") or "Normal",
			cmd = action.cmd or "",
			is_primary = true,
		})
	end

	-- 2. Auto-discovered extra runtime keymaps matching this topic
	local extra_seen = {}
	for _, km in ipairs(all_maps) do
		local text_to_check = (km.desc .. " " .. km.rhs):lower()
		for _, kw in ipairs(topic.match_patterns or {}) do
			if text_to_check:find(kw) then
				if not extra_seen[km.display_key] then
					extra_seen[km.display_key] = true
					-- Check if already included in primary actions
					local already_in_primary = false
					for _, it in ipairs(items) do
						if it.chord:find(km.display_key, 1, true) then
							already_in_primary = true
							break
						end
					end

					if not already_in_primary and km.desc ~= "" then
						table.insert(items, {
							name = km.desc,
							desc = km.rhs ~= "" and ("Command: " .. km.rhs) or "Runtime action",
							chord = km.display_key,
							modes = km.mode == "n" and "Normal" or (km.mode == "t" and "Terminal" or km.mode:upper()),
							cmd = km.rhs ~= "" and km.rhs or "",
							is_primary = false,
						})
					end
				end
				break
			end
		end
	end

	return items
end

-- -----------------------------------------------------------------------------
-- 3. Cheatsheet Rendering (Right Pane)
-- -----------------------------------------------------------------------------

--- Renders formatted topic cheatsheet in the right preview buffer.
--- @param topic table
local function render_cheatsheet(topic)
	if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
		return
	end

	local all_maps = M.collect_runtime_keymaps()
	local items = M.build_topic_cheatsheet(topic, all_maps)

	local lines = {}
	local highlights = {} -- { line = 0-indexed, col_start, col_end, hl_group }

	local function add_line(text, hl_group)
		table.insert(lines, text)
		if hl_group then
			table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = hl_group })
		end
	end

	-- Header Banner
	local title_str = string.format(" %s %s Cheatsheet (Runtime Shortcuts) ", topic.icon or "📌", topic.title)
	local banner_pad = math.max(0, 68 - #title_str)
	local banner = "╭─" .. title_str .. string.rep("─", banner_pad) .. "╮"
	add_line(banner, "GitCenterDiffHeader")
	add_line("│ " .. topic.desc, "Comment")
	add_line("╰" .. string.rep("─", 68) .. "╯", "GitCenterDiffHeader")
	add_line("")

	-- Primary Shortcuts Section
	add_line(" ⚡ Active Runtime Shortcuts (Introspected Live)", "Title")
	add_line(" ───────────────────────────────────────────────────────────────────", "Comment")

	local primary_count = 0
	for _, it in ipairs(items) do
		if it.is_primary then
			primary_count = primary_count + 1
			local key_pill = string.format("  [%-22s]", it.chord)
			local line_txt = string.format("%s  %-30s │ %s", key_pill, it.name, it.cmd)
			add_line(line_txt)

			-- Highlight key chord pill in DiagnosticInfo / Special
			local line_idx = #lines - 1
			table.insert(highlights, { line = line_idx, col_start = 2, col_end = #key_pill, hl_group = "Special" })
			table.insert(highlights, { line = line_idx, col_start = #key_pill + 2, col_end = #key_pill + 32, hl_group = "Normal" })
			table.insert(highlights, { line = line_idx, col_start = #key_pill + 35, col_end = -1, hl_group = "DiagnosticHint" })

			if it.desc and it.desc ~= "" then
				add_line(string.format("      ↳ %s [%s]", it.desc, it.modes), "Comment")
			end
		end
	end

	if primary_count == 0 then
		add_line("  (No direct shortcuts registered for this section)", "Comment")
	end

	add_line("")

	-- Extra Discovered Keymaps
	local extra_items = {}
	for _, it in ipairs(items) do
		if not it.is_primary then
			table.insert(extra_items, it)
		end
	end

	if #extra_items > 0 then
		add_line(" 🔍 Additional Context & Mode Mappings", "Title")
		add_line(" ───────────────────────────────────────────────────────────────────", "Comment")
		for _, it in ipairs(extra_items) do
			local key_pill = string.format("  [%-18s]", it.chord)
			local line_txt = string.format("%s  %-30s [%s]", key_pill, it.name, it.modes)
			add_line(line_txt)

			local line_idx = #lines - 1
			table.insert(highlights, { line = line_idx, col_start = 2, col_end = #key_pill, hl_group = "Special" })
			table.insert(highlights, { line = line_idx, col_start = -1 - #it.modes - 2, col_end = -1, hl_group = "DiagnosticWarn" })
		end
		add_line("")
	end

	-- Tips section
	if topic.tips and #topic.tips > 0 then
		add_line(" 💡 Pro-Tips & Workflow Notes", "Title")
		add_line(" ───────────────────────────────────────────────────────────────────", "Comment")
		for _, tip in ipairs(topic.tips) do
			add_line("  • " .. tip, "Normal")
		end
		add_line("")
	end

	add_line("────────────────────────────────────────────────────────────────────", "Comment")
	add_line(" [Tab/Right]: Focus reader │ [/]: Search │ [q/Esc]: Close │ [<F1>]: Toggle", "DiagnosticHint")

	vim.bo[state.right_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.right_buf, 0, -1, false, lines)
	vim.bo[state.right_buf].modifiable = false

	-- Apply highlights
	local ns = vim.api.nvim_create_namespace("krs_help_modal_hl")
	vim.api.nvim_buf_clear_namespace(state.right_buf, ns, 0, -1)
	for _, hl in ipairs(highlights) do
		pcall(vim.api.nvim_buf_add_highlight, state.right_buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
	end

	state.active_topic_id = topic.id
end

-- -----------------------------------------------------------------------------
-- 4. Modal Window Lifecycle
-- -----------------------------------------------------------------------------

--- Closes help modal cleanly.
function M.close()
	if not state.is_open then
		return
	end

	if state.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
		state.augroup = nil
	end

	if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
		pcall(vim.api.nvim_win_close, state.left_win, true)
	end
	if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
		pcall(vim.api.nvim_win_close, state.right_win, true)
	end

	if state.left_buf and vim.api.nvim_buf_is_valid(state.left_buf) then
		pcall(vim.api.nvim_buf_delete, state.left_buf, { force = true })
	end
	if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
		pcall(vim.api.nvim_buf_delete, state.right_buf, { force = true })
	end

	zindex.unregister("help_modal")

	state.is_open = false
	state.left_win = nil
	state.right_win = nil
	state.left_buf = nil
	state.right_buf = nil
	state.active_topic_id = nil
end

--- Returns whether help modal is currently open.
--- @return boolean
function M.is_open()
	return state.is_open
end

--- Opens Cheatsheet & Help modal.
function M.open()
	if state.is_open then
		M.close()
		return
	end

	state.topics = M.topic_catalog

	local geo = ui.compute_dual_panel({
		left_ratio = M.settings.left_width_ratio or 0.32,
		width_ratio = 0.90,
		height_ratio = 0.86,
		gap = 2,
		min_left_width = M.settings.min_left_width,
	})

	local z_base = zindex.get_zindex("help_modal")

	-- Create Left Index Buffer & Win
	state.left_buf = ui.scratch_buffer({ modifiable = true, filetype = "krshelpindex" })
	vim.b[state.left_buf].krs_help_modal = true

	local index_lines = {}
	table.insert(index_lines, " 📖 KrsVim Help Categories")
	table.insert(index_lines, " ──────────────────────────────")
	for _, topic in ipairs(state.topics) do
		table.insert(index_lines, string.format("  %s %-18s", topic.icon, topic.title))
	end

	vim.api.nvim_buf_set_lines(state.left_buf, 0, -1, false, index_lines)
	vim.bo[state.left_buf].modifiable = false

	state.left_win = vim.api.nvim_open_win(state.left_buf, true, {
		relative = "editor",
		row = geo.row,
		col = geo.left_col,
		width = geo.left_width,
		height = geo.total_height,
		style = "minimal",
		border = "rounded",
		title = " 💡 Help & Cheatsheet Index (/ to search) ",
		title_pos = "center",
		zindex = z_base,
	})

	-- Create Right Cheatsheet Buffer & Win
	state.right_buf = ui.scratch_buffer({ modifiable = true, filetype = "krscheatsheet" })
	vim.b[state.right_buf].krs_help_modal = true
	state.right_win = vim.api.nvim_open_win(state.right_buf, false, {
		relative = "editor",
		row = geo.row,
		col = geo.right_col,
		width = geo.right_width,
		height = geo.total_height,
		style = "minimal",
		border = "rounded",
		title = " ⌨️ Live Cheatsheet (Runtime Shortcuts) ",
		title_pos = "center",
		zindex = z_base,
	})

	vim.wo[state.left_win].cursorline = true
	vim.wo[state.right_win].cursorline = false
	vim.wo[state.right_win].wrap = true

	state.is_open = true

	-- Position cursor on first topic (line 3)
	pcall(vim.api.nvim_win_set_cursor, state.left_win, { 3, 2 })
	render_cheatsheet(state.topics[1])

	state.augroup = vim.api.nvim_create_augroup("KrsHelpModal", { clear = true })

	-- Live cheatsheet preview on CursorMoved
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = state.augroup,
		buffer = state.left_buf,
		callback = function()
			if not state.is_open or not state.left_win or not vim.api.nvim_win_is_valid(state.left_win) then
				return
			end
			local cursor = vim.api.nvim_win_get_cursor(state.left_win)
			local topic_idx = cursor[1] - 2 -- header takes 2 lines
			if topic_idx >= 1 and topic_idx <= #state.topics then
				local topic = state.topics[topic_idx]
				if topic and topic.id ~= state.active_topic_id then
					render_cheatsheet(topic)
				end
			end
		end,
	})

	-- Keybindings inside modal
	local function map_keys(buf, win)
		local function make_opts(desc)
			return { noremap = true, silent = true, buffer = buf, nowait = true, desc = desc }
		end

		vim.keymap.set("n", "q", M.close, make_opts("Close help modal"))
		vim.keymap.set("n", "<Esc>", M.close, make_opts("Close help modal"))
		vim.keymap.set("n", "<F1>", M.close, make_opts("Close help modal"))

		-- Focus switching between left and right panes
		vim.keymap.set("n", "<Tab>", function()
			if vim.api.nvim_get_current_win() == state.left_win then
				if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
					vim.api.nvim_set_current_win(state.right_win)
				end
			else
				if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
					vim.api.nvim_set_current_win(state.left_win)
				end
			end
		end, make_opts("Toggle focus between index and cheatsheet"))

		vim.keymap.set("n", "<S-Tab>", function()
			if vim.api.nvim_get_current_win() == state.right_win then
				if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
					vim.api.nvim_set_current_win(state.left_win)
				end
			end
		end, make_opts("Focus left index"))

		vim.keymap.set("n", "<Right>", function()
			if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
				vim.api.nvim_set_current_win(state.right_win)
			end
		end, make_opts("Focus cheatsheet pane"))

		vim.keymap.set("n", "<Left>", function()
			if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
				vim.api.nvim_set_current_win(state.left_win)
			end
		end, make_opts("Focus index pane"))

		vim.keymap.set("n", "<C-f>", "/", make_opts("Search within help pane"))
	end

	map_keys(state.left_buf, state.left_win)
	map_keys(state.right_buf, state.right_win)
end

-- -----------------------------------------------------------------------------
-- 5. Setup & Registration
-- -----------------------------------------------------------------------------

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("KrsHelp", M.open, { desc = "Open KrsVim Cheatsheet & Help Modal (<F1>)" })
	vim.api.nvim_create_user_command("Cheatsheet", M.open, { desc = "Open KrsVim Cheatsheet & Help Modal (<F1>)" })
	vim.api.nvim_create_user_command("HelpMenu", M.open, { desc = "Open KrsVim Cheatsheet & Help Modal (<F1>)" })
	vim.api.nvim_create_user_command("KrsCheatsheet", M.open, { desc = "Open KrsVim Cheatsheet & Help Modal (<F1>)" })

	for _, k in ipairs(M.settings.keys.open) do
		local modes = { "n", "v", "i", "t" }
		vim.keymap.set(modes, k, M.open, { desc = "Open KrsVim Cheatsheet & Help Menu" })
	end
end

-- LAZY.NVIM SPEC
local lazy_keys = {}
for _, k in ipairs(M.settings.keys.open) do
	table.insert(lazy_keys, { k, mode = { "n", "v", "i", "t" }, desc = "Open KrsVim Cheatsheet & Help Menu" })
end

local plugin_spec = {
	name = "krs_help_modal",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "KrsHelp", "Cheatsheet", "HelpMenu", "KrsCheatsheet" },
	keys = lazy_keys,
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
