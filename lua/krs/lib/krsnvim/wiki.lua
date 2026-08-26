--- @module "krsnvim.wiki"
--- Floating Interactive Wiki Documentation System for `krsnvimscript`.
--- Opens a styled floating markdown window inside Neovim with single-key navigation (1–6).
---
--- @example
--- local wiki = import("krsnvim.wiki")
--- wiki.open("fetch.md")
local M = {}

local docs_files = {
	{ name = "1. Index & Overview", file = "index.md" },
	{ name = "2. Terminal ($)", file = "terminal.md" },
	{ name = "3. JSON / YAML / TOML", file = "json_yaml_toml.md" },
	{ name = "4. CLI & Numeric Menu", file = "cli.md" },
	{ name = "5. Global import()", file = "import.md" },
	{ name = "6. Pure Lua Fetch API", file = "fetch.md" },
	{ name = "7. Vitest-like Testing", file = "test.md" },
}

local function get_docs_dir()
	local info = debug.getinfo(1, "S")
	local source = info.source:sub(2)
	local dir = vim.fn.fnamemodify(source, ":h")
	return dir .. "/docs"
end

--- Opens an interactive floating markdown wiki viewer inside Neovim.
---
--- @param doc_file string|nil Name of the documentation file to open (e.g. `"index.md"`, `"fetch.md"`). Defaults to `"index.md"`.
---
--- @note Features:
--- - Uses floating rounded window centered on screen.
--- - Single key switching: Press `1` through `6` to instantly switch wiki pages.
--- - Press `q` or `<Esc>` to close viewer.
---
--- @see krsnvim.wiki.open
---
--- @example
--- require("krs.lib.krsnvim").wiki.open("index.md")
function M.open(doc_file)
	doc_file = doc_file or "index.md"
	local docs_dir = get_docs_dir()
	local filepath = docs_dir .. "/" .. doc_file

	local f = io.open(filepath, "r")
	if not f then
		vim.notify("krsnvimscript wiki: File not found: " .. filepath, vim.log.levels.ERROR)
		return
	end
	local content = f:read("*a")
	f:close()

	local lines = {}
	for line in content:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	-- Window calculations
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " 🦊 krsnvimscript Wiki Documentation [Press 1-6 to switch, q to close] ",
		title_pos = "center",
	})

	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].breakindent = true
	vim.wo[win].conceallevel = 3
	vim.wo[win].concealcursor = "nvic"
	local ok, rm_ui = pcall(require, "render-markdown.core.ui")
	if ok and rm_ui and type(rm_ui.update) == "function" then
		rm_ui.update(buf, win, "UserCommand", true)
	end

	-- Keybindings inside wiki window
	local opts = { noremap = true, silent = true, buffer = buf }
	vim.keymap.set("n", "q", "<cmd>close<CR>", opts)
	vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", opts)
	vim.keymap.set("n", "w", function()
		vim.wo[win].wrap = not vim.wo[win].wrap
		local status = vim.wo[win].wrap and "ON (Text Wrap)" or "OFF (Table Grid View)"
		vim.notify("krsnvimscript wiki line wrap: " .. status, vim.log.levels.INFO)
	end, opts)

	for idx, doc in ipairs(docs_files) do
		vim.keymap.set("n", tostring(idx), function()
			vim.api.nvim_win_close(win, true)
			M.open(doc.file)
		end, opts)
	end
end

return M
