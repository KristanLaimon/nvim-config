-- ============================================================================
-- KRS PLUGIN: Context Help -- `?` shows the keys that work HERE.
-- ============================================================================
-- WHAT IT DOES
--   Detects what you are looking at (neo-tree, git center, a picker, or plain
--   code) and notifies the shortcuts for that surface. In a normal buffer `?`
--   keeps its native meaning (search backwards) instead of being stolen.
--
-- HOW TO EXTEND
--   Everything is data: add an entry to `M.settings.contexts` with a `detect`
--   predicate, a `title` and its `lines`. Order matters -- the first match wins,
--   and the last entry is the fallback.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION -- the help content itself
-- ============================================================================

M.settings = {
	keys = {
		--- Context help in normal mode. `?` falls through in ordinary buffers.
		show = { "?", "<F1>" },
	},

	--- Context name that keeps `?` as the native backwards-search.
	passthrough_context = "editor",

	--- Checked in order; the first `detect` that returns true wins.
	--- `detect(ft, buf_name)` receives the current filetype and buffer name.
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
				"1..4: Jump to Section 1, 2, 3, or 4",
				"Ctrl+Shift+J/K: Scroll right preview panel",
				"s/S : Stage File / Stage All",
				"u/U : Unstage File / Unstage All",
				"c : Edit Commit Title | C : Commit & Tag",
				"Tab: Toggle focus between list and preview",
				"d : View Full Diff Modal | q : Close panel",
			},
		},
		{
			name = "telescope",
			title = "📁 File Explorer",
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
				"Ctrl + Shift + Enter: Open Media (Image/Video) with OS Default App",
				"Ctrl + '        : Toggle Comment",
				"Alt + 1..9      : Terminal 1 to 9  |  Ctrl + ; : Toggle Terminal",
			},
		},
	},
}

-- ============================================================================
-- API
-- ============================================================================

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

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "context_help",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VeryLazy",
	config = M.setup,
}, { __index = M })
