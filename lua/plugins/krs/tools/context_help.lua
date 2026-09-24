-- ============================================================================
-- KRS PLUGIN: Context Help -- `?` / `<F1>` / `<Ctrl+?>` shows the keys that work HERE.
-- ============================================================================
-- WHAT IT DOES
--   Detects what you are looking at (neo-tree, git center, a picker, or plain
--   code) and notifies the shortcuts for that surface. In a normal buffer `?`
--   keeps its native meaning (search backwards) instead of being stolen, while
--   <F1> or <Ctrl+?> always shows the editor shortcuts.
-- ============================================================================

local M = {}

M.settings = {
	keys = {
		--- Context help in normal mode. `?` falls through in ordinary buffers.
		show = { "?", "<F1>", "<C-?>", "<C-/>", "<C-_>", "<C-S-/>", "<leader>?" },
	},

	--- Context name that keeps `?` as the native backwards-search.
	passthrough_context = "editor",

	contexts = {
		{
			name = "neotree",
			title = "🌳 Neo-Tree (Explorer)",
			detect = function(ft, _)
				return ft == "neo-tree"
			end,
			lines = {
				"Ctrl+N / a : Create File | Ctrl+Shift+N / A : Create Folder",
				"r : Rename               | d : Delete",
				"c : Copy            | x : Cut | p : Paste",
				"Ctrl + Shift + Enter : Reveal selected file/folder in System Explorer",
				"q : Close explorer",
			},
		},
		{
			name = "git",
			title = "🦊 Git Center",
			detect = function(ft, buf_name)
				return ft:find("Neogit") ~= nil
					or ft:find("Diffview") ~= nil
					or ft:find("git") ~= nil
					or buf_name:find("Git") ~= nil
			end,
			lines = {
				"1..6: Jump to Sections (1 Commit, 2 Staged, 3 Changes, 4 Branches, 5 Commits, 6 Stash)",
				"Tab: Toggle focus between panel and preview",
				"s/S : Stage File / Stage All  |  u/U : Unstage File / Unstage All",
				"c : Edit Commit Title         |  C : Execute Commit & Tag",
				"l / L: GitKraken Graph Viewer (Current / All branches)",
				"t / T: 🧪 Simulate Merge / Rebase (Dry-Run Conflict Check)",
				"z : Stash Menu (Save / Pop / Apply / Drop)",
				"d : View Side-by-Side Diff Modal",
				"? / F1: Open Keyboard Shortcuts Overlay",
				"q / Esc: Close Git Center",
			},
		},
		{
			name = "telescope",
			title = "📁 File Explorer & Pickers",
			detect = function(ft, buf_name)
				return ft == "TelescopePrompt"
					or ft == "TaskRunner"
					or buf_name:find("Telescope") ~= nil
					or buf_name:find("project_tasks") ~= nil
			end,
			lines = {
				"a : Create (file.txt or folder/)",
				"r : Rename          | d : Delete",
				"c : Copy            | m : Move / Cut",
				"o : Open Folder as Active Project (CWD)",
				"f / Ctrl + F : Toggle Favorite folder/file",
				"Tab: Multi-select items",
			},
		},
		{
			-- Fallback: no `detect`, so it always matches last.
			name = "editor",
			title = "⚡ Key Editor Shortcuts",
			lines = {
				"Ctrl + K        : Find File by Name",
				"Ctrl + Shift + H/J/K/L : Find File & Open in Split (← ↓ ↑ →)",
				"Ctrl + F        : Live Grep Text in Project",
				"Ctrl + Shift + F: Floating Desktop Explorer",
				"Ctrl + Shift + T: Project Task Menu",
				"Ctrl + Shift + G: Git Control Center",
				"Ctrl + Shift + Enter: Open Media with OS Default App",
				"Ctrl + '        : Toggle Comment",
				"Alt + 1..9      : Terminal 1 to 9  |  Ctrl + ; : Toggle Terminal",
				"F1 / Ctrl + ?   : Show Context Shortcuts Help",
			},
		},
	},
}

--- Context entry matching the current buffer.
--- @return table context Entry from `M.settings.contexts`.
local function current_context()
	local ft = vim.bo.filetype
	local buf_name = vim.api.nvim_buf_get_name(0)

	for _, context in ipairs(M.settings.contexts) do
		if not context.detect or context.detect(ft, buf_name) then
			return context
		end
	end
	return M.settings.contexts[#M.settings.contexts]
end

--- Name of the current context, e.g. "neotree" or "editor".
--- @return string name
function M.get_context()
	return current_context().name
end

--- Notifies the shortcuts of the current context.
function M.show_help()
	local context = current_context()
	vim.notify(table.concat(context.lines, "\n"), vim.log.levels.INFO, { title = context.title })
end

--- Binds the help keys. `?` is an expression mapping so it can fall through to
--- the native backwards search in ordinary buffers.
function M.setup()
	pcall(vim.api.nvim_create_user_command, "ContextHelp", function()
		M.show_help()
	end, { desc = "Show Context-Aware Keyboard Shortcuts Help" })

	pcall(vim.api.nvim_create_user_command, "HelpShortcuts", function()
		M.show_help()
	end, { desc = "Show Context-Aware Keyboard Shortcuts Help" })

	for _, key in ipairs(M.settings.keys.show) do
		vim.keymap.set("n", key, function()
			if key == "?" and M.get_context() == M.settings.passthrough_context then
				return "?"
			end
			M.show_help()
			return ""
		end, { noremap = true, silent = true, expr = true, desc = "Context Help" })
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.ContextHelp = M

return setmetatable({
	name = "context_help",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VeryLazy",
	cmd = { "ContextHelp", "HelpShortcuts" },
	config = M.setup,
}, { __index = M })
