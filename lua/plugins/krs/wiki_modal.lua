-- ============================================================================
-- KRS PLUGIN: Documentation Center & Wiki Modal (Ctrl + Shift + D).
-- ============================================================================
-- WHAT IT DOES
--   An interactive dual-pane Wikipedia modal for KrsVim documentation.
--   Left panel: Categorized index of every guide, how-to, and architecture doc.
--   Right panel: Live markdown document viewer with syntax highlighting.
-- ============================================================================

local ui = require("krs.core.ui")
local zindex = require("krs.core.z_index")
local path_util = require("krs.core.path")

local M = {}

M.settings = {
	keys = {
		-- <C-S-d> needs a terminal that reports Shift on Ctrl+letter combos
		-- (Neovide, or Windows Terminal 1.19+/kitty/wezterm/foot with the
		-- Kitty keyboard protocol). Plain terminals send the same byte for
		-- <C-d> and <C-S-d>, so <leader>? is kept as an always-works fallback.
		open = { "<C-S-d>", "<C-S-D>", "<C-S-,>" },
	},
	docs_dir = vim.fn.stdpath("config") .. "/docs",
	left_width_ratio = 0.32,
	min_left_width = 30,
}

--- Document category catalog matching docs/ layout.
M.categories = {
	{
		title = "🏁 Getting Started",
		docs = {
			{ name = "Wiki Home & Overview", file = "index.md" },
			{ name = "Neovim Basics (start here if new)", file = "neovim-basics.md" },
			{ name = "Installation & Setup", file = "installation.md" },
			{ name = "Keybinds Reference", file = "keybinds.md" },
			{ name = "Plugin Inventory", file = "plugins.md" },
		},
	},
	{
		title = "🎓 How-To & Extension",
		docs = {
			{ name = "How-To & Customization Guide", file = "how-to-customize-editor.md" },
			{ name = "How to Create Local Plugins", file = "how-to-create-local-plugin.md" },
			{ name = "How to Add a New Language", file = "adding-language.md" },
		},
	},
	{
		title = "📖 Explanations & Architecture",
		docs = {
			{ name = "System Architecture", file = "architecture.md" },
			{ name = "Module Architecture", file = "module-architecture.md" },
			{ name = "Dynamic Z-Index Stack", file = "z-index.md" },
			{ name = "Testing & QA Suite", file = "testing.md" },
		},
	},
	{
		title = "🚀 Building & Debugging",
		docs = {
			{ name = "Task Runner (tasks.json)", file = "tasks.md" },
			{ name = "Launch Profiles (launch.json)", file = "launch-profiles.md" },
			{ name = "Debug Adapters (DAP)", file = "debug-adapters.md" },
			{ name = "Persistent Breakpoints", file = "breakpoints.md" },
		},
	},
	{
		title = "🎨 UI & Workflow",
		docs = {
			{ name = "Git Control Center", file = "git-center.md" },
			{ name = "File Explorers & Neo-tree", file = "file-explorer.md" },
			{ name = "Multi-Terminal Manager", file = "terminals.md" },
			{ name = "Workspaces & Sessions", file = "workspaces.md" },
			{ name = "Command Palette", file = "command-palette.md" },
			{ name = "Color Palette & Themes", file = "color-palette.md" },
			{ name = "Editor Quality of Life", file = "editor-qol.md" },
		},
	},
	{
		title = "🧬 Code Helpers",
		docs = {
			{ name = "Tailwind Classes Organizer", file = "tailwind-organizer.md" },
			{ name = "Modular Type Injector", file = "type-injector.md" },
			{ name = "Input Modal Component", file = "input-modal.md" },
			{ name = "JSON Schemas Catalog", file = "schemas-json.md" },
			{ name = "TOML Schemas Catalog", file = "schemas-toml.md" },
		},
	},
}

--- Active session state.
local state = {
	is_open = false,
	left_buf = nil,
	left_win = nil,
	right_buf = nil,
	right_win = nil,
	active_doc_file = nil,
	items = {}, -- Flat list of { type = "header"|"doc", title = ..., file = ... }
	augroup = nil,
}

--- Flatten categories into list items for navigation index.
local function build_flat_items()
	local items = {}
	for _, cat in ipairs(M.categories) do
		table.insert(items, { type = "header", title = cat.title })
		for _, doc in ipairs(cat.docs) do
			table.insert(items, { type = "doc", title = "  📄 " .. doc.name, file = doc.file })
		end
	end
	return items
end

--- Loads and renders doc file content in right preview window.
--- @param filename string
local function load_document(filename)
	if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
		return
	end

	if state.active_doc_file == filename then
		return
	end

	local filepath = path_util.join(M.settings.docs_dir, filename)
	local lines = {}
	local f = io.open(filepath, "r")
	if f then
		for line in f:lines() do
			table.insert(lines, line)
		end
		f:close()
	else
		table.insert(lines, "# Document Not Found")
		table.insert(lines, "")
		table.insert(lines, "Could not locate documentation file: " .. filepath)
	end

	vim.bo[state.right_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.right_buf, 0, -1, false, lines)
	vim.bo[state.right_buf].modifiable = false
	if vim.bo[state.right_buf].filetype ~= "markdown" then
		vim.bo[state.right_buf].filetype = "markdown"
	end

	state.active_doc_file = filename

	if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
		vim.wo[state.right_win].conceallevel = 3
		vim.wo[state.right_win].concealcursor = "nvic"
		local ok, rm_ui = pcall(require, "render-markdown.core.ui")
		if ok and rm_ui and type(rm_ui.update) == "function" then
			rm_ui.update(state.right_buf, state.right_win, "UserCommand", true)
		end
	end
end

--- Closes documentation modal cleanly.
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

	zindex.unregister("wiki_modal")

	state.is_open = false
	state.left_win = nil
	state.right_win = nil
	state.left_buf = nil
	state.right_buf = nil
	state.active_doc_file = nil
end

--- Opens Documentation Center modal.
function M.open()
	if state.is_open then
		M.close()
		return
	end

	state.items = build_flat_items()

	local geo = ui.compute_dual_panel({
		left_ratio = M.settings.left_width_ratio or 0.35,
		width_ratio = 0.88,
		height_ratio = 0.85,
		gap = 2,
		min_left_width = M.settings.min_left_width,
	})

	local z_base = zindex.get_zindex("wiki_modal")

	-- Create Left Index Buffer & Win
	state.left_buf = ui.scratch_buffer({ modifiable = true, filetype = "krsdocindex" })
	vim.b[state.left_buf].krs_wiki_modal = true
	local index_lines = {}
	for _, item in ipairs(state.items) do
		table.insert(index_lines, item.title)
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
		title = " 📚 KrsVim Wiki Index (/ or Ctrl+F to search) ",
		title_pos = "center",
		zindex = z_base,
	})

	-- Create Right Document Reader Buffer & Win
	state.right_buf = ui.scratch_buffer({ modifiable = true, filetype = "markdown" })
	vim.b[state.right_buf].krs_wiki_modal = true
	state.right_win = vim.api.nvim_open_win(state.right_buf, false, {
		relative = "editor",
		row = geo.row,
		col = geo.right_col,
		width = geo.right_width,
		height = geo.total_height,
		style = "minimal",
		border = "rounded",
		title = " 📖 Document Reader (Press w to toggle wrap, / to search) ",
		title_pos = "center",
		zindex = z_base,
	})

	vim.wo[state.left_win].cursorline = true
	vim.wo[state.right_win].cursorline = false
	vim.wo[state.right_win].wrap = true
	vim.wo[state.right_win].linebreak = true
	vim.wo[state.right_win].breakindent = true
	vim.wo[state.right_win].conceallevel = 3
	vim.wo[state.right_win].concealcursor = "nvic"

	state.is_open = true

	-- Load initial document (index.md)
	load_document("index.md")

	state.augroup = vim.api.nvim_create_augroup("KrsWikiModal", { clear = true })

	-- Set up cursor movement listener on index list for live document preview
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = state.augroup,
		buffer = state.left_buf,
		callback = function()
			if not state.is_open or not state.left_win or not vim.api.nvim_win_is_valid(state.left_win) then
				return
			end
			local cursor = vim.api.nvim_win_get_cursor(state.left_win)
			local line = cursor[1]
			local item = state.items[line]
			if item and item.type == "doc" and item.file then
				load_document(item.file)
			end
		end,
	})

	-- Keybindings for Modal Navigation
	local function follow_link_in_reader()
		local cur_win = vim.api.nvim_get_current_win()
		if cur_win ~= state.right_win then
			return
		end

		local cursor = vim.api.nvim_win_get_cursor(state.right_win)
		local row, col = cursor[1], cursor[2] + 1
		local lines = vim.api.nvim_buf_get_lines(state.right_buf, row - 1, row, false)
		local line = lines[1] or ""

		local links = {}
		local s_pos = 1
		while true do
			local m_start, m_end, label, target = line:find("(%[[^%]]+%]%(([^%)]+)%))", s_pos)
			if not m_start then
				break
			end
			table.insert(links, { start_col = m_start, end_col = m_end, target = target })
			s_pos = m_end + 1
		end

		local url_patterns = { "https?://%S+", "file://%S+" }
		for _, pat in ipairs(url_patterns) do
			s_pos = 1
			while true do
				local u_start, u_end, target = line:find("(" .. pat .. ")", s_pos)
				if not u_start then
					break
				end
				target = target:gsub("[%),.]+$", "")
				local inside = false
				for _, l in ipairs(links) do
					if u_start >= l.start_col and u_end <= l.end_col then
						inside = true
						break
					end
				end
				if not inside then
					table.insert(links, { start_col = u_start, end_col = u_end, target = target })
				end
				s_pos = u_end + 1
			end
		end

		local chosen_target = nil
		for _, l in ipairs(links) do
			if col >= l.start_col and col <= l.end_col then
				chosen_target = l.target
				break
			end
		end
		if not chosen_target and #links > 0 then
			chosen_target = links[1].target
		end

		if not chosen_target then
			vim.notify("No markdown link found on this line", vim.log.levels.WARN, { title = "Wiki Reader" })
			return
		end

		if chosen_target:match("^https?://") then
			pcall(vim.ui.open, chosen_target)
			vim.notify("🌐 Opening web link: " .. chosen_target, vim.log.levels.INFO)
			return
		end

		local clean_file = chosen_target:gsub("^file:///", ""):gsub("#.*$", ""):gsub("^.*/", "")
		if clean_file:match("%.md$") then
			load_document(clean_file)
			-- Sync left index selection if match found
			for idx, item in ipairs(state.items) do
				if item.file == clean_file then
					pcall(vim.api.nvim_win_set_cursor, state.left_win, { idx, 0 })
					break
				end
			end
		end
	end

	local function follow_link_at_mouse()
		local mouse_pos = vim.fn.getmousepos()
		if mouse_pos and mouse_pos.winid == state.right_win and vim.api.nvim_win_is_valid(mouse_pos.winid) then
			vim.api.nvim_set_current_win(mouse_pos.winid)
			pcall(vim.api.nvim_win_set_cursor, mouse_pos.winid, { mouse_pos.line, math.max(0, mouse_pos.column - 1) })
		end
		follow_link_in_reader()
	end

	--- Resizes the split ratio between left index pane and right reader pane.
	--- @param delta number Fraction to adjust left ratio (e.g. -0.03 or 0.03).
	function M.resize_split(delta)
		if not state.is_open or not state.left_win or not vim.api.nvim_win_is_valid(state.left_win) then
			return
		end

		M.settings.left_width_ratio = ui.resize_dual_panel({
			left_win = state.left_win,
			right_win = state.right_win,
			delta = delta,
			left_ratio = M.settings.left_width_ratio or 0.35,
			width_ratio = 0.88,
			height_ratio = 0.85,
			gap = 2,
			min_ratio = 0.15,
			max_ratio = 0.70,
			min_left_width = M.settings.min_left_width,
		})
	end

	local function map_keys(buf, win)
		local function make_opts(desc)
			return { noremap = true, silent = true, buffer = buf, nowait = true, desc = desc }
		end

		-- Close keys (Esc/q plus whatever opens the modal, so it toggles shut too)
		local close_keys = { "q", "<Esc>" }
		for _, k in ipairs(M.settings.keys.open) do
			table.insert(close_keys, k)
		end
		for _, k in ipairs(close_keys) do
			vim.keymap.set({ "n", "v", "i", "t" }, k, M.close, make_opts("Close wiki modal"))
		end

		-- Panel Switch
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
		end, make_opts("Switch wiki modal panel"))

		vim.keymap.set("n", "<C-h>", function()
			if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
				vim.api.nvim_set_current_win(state.left_win)
			end
		end, make_opts("Focus left wiki index panel"))

		vim.keymap.set("n", "<C-l>", function()
			if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
				vim.api.nvim_set_current_win(state.right_win)
			end
		end, make_opts("Focus right document reader panel"))

		-- Split Resizing (<C-Left> / <C-Right>, <C-S-Left> / <C-S-Right>, < / >)
		for _, k in ipairs({ "<C-Left>", "<C-S-Left>" }) do
			vim.keymap.set({ "n", "v", "i", "t" }, k, function()
				M.resize_split(-0.03)
			end, make_opts("Resize wiki split left"))
		end
		vim.keymap.set("n", "<", function()
			M.resize_split(-0.03)
		end, make_opts("Resize wiki split left"))

		for _, k in ipairs({ "<C-Right>", "<C-S-Right>" }) do
			vim.keymap.set({ "n", "v", "i", "t" }, k, function()
				M.resize_split(0.03)
			end, make_opts("Resize wiki split right"))
		end
		vim.keymap.set("n", ">", function()
			M.resize_split(0.03)
		end, make_opts("Resize wiki split right"))

		-- <C-f> mirrors "/": both start native Neovim search in this pane
		-- (repeat matches with n/N). Vim's own <C-f> page-scroll isn't
		-- useful in these small panes, so it's free to reuse.
		vim.keymap.set("n", "<C-f>", "/", make_opts("Search within wiki panel"))
	end

	map_keys(state.left_buf, state.left_win)
	map_keys(state.right_buf, state.right_win)

	-- Link follow keymaps inside right reader buffer
	local function reader_opts(desc)
		return { noremap = true, silent = true, buffer = state.right_buf, nowait = true, desc = desc }
	end
	vim.keymap.set("n", "<CR>", follow_link_in_reader, reader_opts("Follow wiki link under cursor"))
	vim.keymap.set("n", "<C-k>", follow_link_in_reader, reader_opts("Follow wiki link under cursor"))
	vim.keymap.set("n", "gx", follow_link_in_reader, reader_opts("Follow wiki link under cursor"))
	vim.keymap.set("n", "K", follow_link_in_reader, reader_opts("Follow wiki link under cursor"))
	vim.keymap.set({ "n", "v" }, "<S-LeftMouse>", follow_link_at_mouse, reader_opts("Follow wiki link at mouse click"))

	local function toggle_wrap()
		if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
			vim.wo[state.right_win].wrap = not vim.wo[state.right_win].wrap
			local status = vim.wo[state.right_win].wrap and "ON (Text Wrap)" or "OFF (Table Grid View)"
			vim.notify("Wiki Reader line wrap: " .. status, vim.log.levels.INFO)
		end
	end
	vim.keymap.set("n", "w", toggle_wrap, reader_opts("Toggle line wrapping in reader"))
	vim.keymap.set("n", "<A-w>", toggle_wrap, reader_opts("Toggle line wrapping in reader"))

	-- Index click selection keymap in left buffer
	local function left_opts(desc)
		return { noremap = true, silent = true, buffer = state.left_buf, nowait = true, desc = desc }
	end
	local function select_index_at_mouse()
		local mouse_pos = vim.fn.getmousepos()
		if mouse_pos and mouse_pos.winid == state.left_win and vim.api.nvim_win_is_valid(mouse_pos.winid) then
			vim.api.nvim_set_current_win(mouse_pos.winid)
			pcall(vim.api.nvim_win_set_cursor, mouse_pos.winid, { mouse_pos.line, math.max(0, mouse_pos.column - 1) })
			local item = state.items[mouse_pos.line]
			if item and item.type == "doc" and item.file then
				load_document(item.file)
			end
		end
	end
	vim.keymap.set(
		{ "n", "v" },
		"<S-LeftMouse>",
		select_index_at_mouse,
		left_opts("Select wiki index item at mouse click")
	)
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("KrsWiki", M.open, { desc = "Open KrsVim Wiki Documentation Modal" })
	vim.api.nvim_create_user_command("NvimWiki", M.open, { desc = "Open KrsVim Wiki Documentation Modal" })

	for _, k in ipairs(M.settings.keys.open) do
		local modes = k:lower():find("<leader>") and { "n", "v" } or { "n", "v", "i", "t" }
		vim.keymap.set(modes, k, M.open, { desc = "Open Documentation Center Wiki" })
	end
end

-- LAZY.NVIM SPEC
local lazy_keys = {}
for _, k in ipairs(M.settings.keys.open) do
	local modes = k:lower():find("<leader>") and { "n", "v" } or { "n", "v", "i", "t" }
	table.insert(lazy_keys, { k, mode = modes, desc = "Open Documentation Center Wiki" })
end

local plugin_spec = {
	name = "krs_wiki_modal",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "KrsWiki", "NvimWiki" },
	keys = lazy_keys,
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
