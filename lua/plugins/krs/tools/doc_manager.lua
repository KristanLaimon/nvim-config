-- ============================================================================
-- KRS PLUGIN: Offline Documentation Manager -- Plug in & search language docs offline.
-- ============================================================================
-- WHAT IT DOES
--   Stores offline documentation files inside `stdpath("config")/docs/offline/<language>/<version>/`
--   and provides full CRUD (Create, Read/View, Update, Delete) and Telescope
--   fuzzy searching so you never need internet to check language docs.
--
--   Real documentation can be pulled straight from devdocs.io (same source as
--   https://devdocs.io) with `:KrsDocDownload` -- every language/framework it
--   lists is fetchable, one HTML page per topic, saved under the same offline
--   store so search/view/delete all just work on it.
--
-- COMMANDS
--   :DocManager / :KrsDocManager          Open the Offline Doc Manager UI.
--   :KrsDocSearch [query]                 Fuzzy search offline documentation.
--   :KrsDocView [lang] [version]          Browse docs for language and version.
--   :KrsDocAdd [lang] [version] [topic]   Create a new offline doc file.
--   :KrsDocDownload [slug]                Download real docs from devdocs.io
--                                          (e.g. "python~3.12", "lua~5.4"); with
--                                          no slug, opens a picker of everything
--                                          devdocs.io serves.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

M.settings = {
	docs_dir = vim.fn.stdpath("config") .. "/docs/offline",
	lang_docs_dir = vim.fn.stdpath("config") .. "/docs/languages",
	notify_title = "KRS Offline Doc Manager",

	--- devdocs.io endpoints. `documents_base .. "/" .. slug .. "/db.json"` is the
	--- content bundle for one doc set: a flat `{ [page_path] = html_string }` map.
	devdocs_index_url = "https://devdocs.io/docs/docs.json",
	devdocs_documents_base = "https://documents.devdocs.io",
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

--- Opens a styled Telescope picker (matching the rest of KRS's menus) for a
--- flat list of items, falling back to `vim.ui.select` when Telescope isn't
--- available -- so the caller never has to branch on it themselves.
--- @param prompt_title string
--- @param items any[] Arbitrary entries (strings, tables, whatever `display` handles).
--- @param display fun(item: any): string Label shown per entry.
--- @param on_select fun(item: any) Called with the chosen entry.
--- @param default_index integer|nil Row to pre-select (Telescope only), 1-based.
local function pick(prompt_title, items, display, on_select, default_index)
	if #items == 0 then
		return
	end

	local has_telescope, pickers = pcall(require, "telescope.pickers")
	if not has_telescope then
		local labels, by_label = {}, {}
		for _, item in ipairs(items) do
			local label = display(item)
			table.insert(labels, label)
			by_label[label] = item
		end
		vim.ui.select(labels, { prompt = prompt_title }, function(choice)
			if choice then
				on_select(by_label[choice])
			end
		end)
		return
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = prompt_title,
			default_selection_index = default_index,
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					return { value = item, display = display(item), ordinal = display(item) }
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						on_select(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Ensures the offline docs directory exists.
--- @return string dir_path
function M.ensure_dir()
	local dir = M.settings.docs_dir
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir
end

--- Gets current filetype or defaults to "lua".
--- @param lang string|nil
--- @return string
local function resolve_lang(lang)
	if lang and lang ~= "" then
		return lang:lower()
	end
	local ft = vim.bo.filetype
	if ft and ft ~= "" then
		return ft:lower()
	end
	return "lua"
end

--- Lists available languages in the offline docs store.
--- @return string[]
function M.list_languages()
	M.ensure_dir()
	local langs = {}
	local handle = vim.loop.fs_scandir(M.settings.docs_dir)
	if handle then
		while true do
			local name, type_str = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end
			if type_str == "directory" then
				table.insert(langs, name)
			end
		end
	end
	return langs
end

--- Lists available versions for a given language.
--- @param lang string
--- @return string[]
function M.list_versions(lang)
	local lang_dir = M.settings.docs_dir .. "/" .. lang
	local versions = {}
	if vim.fn.isdirectory(lang_dir) == 1 then
		local handle = vim.loop.fs_scandir(lang_dir)
		if handle then
			while true do
				local name, type_str = vim.loop.fs_scandir_next(handle)
				if not name then
					break
				end
				if type_str == "directory" then
					table.insert(versions, name)
				end
			end
		end
	end
	return versions
end

--- Fuzzy searches across all offline docs using Telescope.
--- @param query string|nil
function M.search_docs(query)
	M.ensure_dir()
	local has_telescope, builtin = pcall(require, "telescope.builtin")
	if not has_telescope then
		notify("Telescope is required for doc search", vim.log.levels.WARN)
		return
	end

	local search_dirs = {}
	if vim.fn.isdirectory(M.settings.docs_dir) == 1 then
		table.insert(search_dirs, M.settings.docs_dir)
	end
	if vim.fn.isdirectory(M.settings.lang_docs_dir) == 1 then
		table.insert(search_dirs, M.settings.lang_docs_dir)
	end

	if #search_dirs == 0 then
		notify("No offline docs directories found!", vim.log.levels.WARN)
		return
	end

	if query and query ~= "" then
		builtin.live_grep({
			prompt_title = "📚 Search Offline Docs (" .. query .. ")",
			search_dirs = search_dirs,
			default_text = query,
		})
	else
		builtin.live_grep({
			prompt_title = "📚 Search Offline Docs",
			search_dirs = search_dirs,
		})
	end
end

--- Interactively browse doc files for a specific language and version.
--- @param lang string|nil
--- @param version string|nil
function M.view_docs(lang, version)
	lang = resolve_lang(lang)
	local versions = M.list_versions(lang)

	if not version or version == "" then
		if #versions == 0 then
			notify("No offline docs found for " .. lang .. ". Create one with :KrsDocAdd " .. lang .. " 1.0 main!")
			return
		elseif #versions == 1 then
			version = versions[1]
		else
			pick("📖 Select " .. lang .. " documentation version", versions, function(v)
				return v
			end, function(v)
				M.view_docs(lang, v)
			end)
			return
		end
	end

	local target_dir = M.settings.docs_dir .. "/" .. lang .. "/" .. version
	if vim.fn.isdirectory(target_dir) == 0 then
		notify("Version directory does not exist: " .. target_dir, vim.log.levels.WARN)
		return
	end

	local has_telescope, builtin = pcall(require, "telescope.builtin")
	if has_telescope then
		builtin.find_files({
			prompt_title = "📖 " .. lang:upper() .. " (v" .. version .. ") Docs",
			cwd = target_dir,
		})
	else
		vim.cmd("Neotree show dir=" .. vim.fn.fnameescape(target_dir))
	end
end

--- Command palette entry: pick a downloaded language/lib, then browse its docs.
--- Current buffer's filetype is pre-selected when it matches a downloaded doc
--- set; no default row when it doesn't (e.g. Neo-tree, an empty buffer).
function M.pick_open_docs()
	local langs = M.list_languages()
	if #langs == 0 then
		notify("No offline docs downloaded yet. Use :KrsDocDownload first.", vim.log.levels.WARN)
		return
	end
	table.sort(langs)

	local ft = (vim.bo.filetype or ""):lower()
	local default_index = nil
	for i, lang in ipairs(langs) do
		if lang:lower() == ft then
			default_index = i
			break
		end
	end

	pick("📚 Open Downloaded Docs", langs, function(lang)
		return "📘 " .. lang
	end, function(lang)
		M.view_docs(lang)
	end, default_index)
end

--- Creates a new offline doc file for a language, version, and topic.
--- @param lang string|nil
--- @param version string|nil
--- @param topic string|nil
function M.add_doc(lang, version, topic)
	lang = resolve_lang(lang)

	local function do_create(l, v, t)
		local target_dir = M.settings.docs_dir .. "/" .. l .. "/" .. v
		vim.fn.mkdir(target_dir, "p")
		local filename = t:gsub("[^%w_%-]", "_"):lower() .. ".md"
		local filepath = target_dir .. "/" .. filename

		if vim.fn.filereadable(filepath) == 0 then
			local f = io.open(filepath, "w")
			if f then
				local content = string.format(
					[[# 📚 %s (v%s) — %s

## Overview
Offline documentation reference for %s version %s.

## Quick Reference
- Topic: %s
- Added: %s

## API & Examples
```%s
-- Code snippet or usage example
```
]],
					l:upper(),
					v,
					t,
					l,
					v,
					t,
					os.date("%Y-%m-%d"),
					l
				)
				f:write(content)
				f:close()
			end
		end

		vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		notify("Created offline doc: " .. filepath)
	end

	if not version or version == "" then
		vim.ui.input({ prompt = "Language Version (e.g. 5.4, 8.3, 3.12, 1.22, 12): ", default = "1.0" }, function(v)
			if not v or v == "" then
				return
			end
			vim.ui.input(
				{ prompt = "Doc Topic Name (e.g. string_functions, arrays, async): ", default = "overview" },
				function(t)
					if not t or t == "" then
						return
					end
					do_create(lang, v, t)
				end
			)
		end)
	elseif not topic or topic == "" then
		vim.ui.input(
			{ prompt = "Doc Topic Name (e.g. string_functions, arrays, async): ", default = "overview" },
			function(t)
				if not t or t == "" then
					return
				end
				do_create(lang, version, t)
			end
		)
	else
		do_create(lang, version, topic)
	end
end

-- ============================================================================
-- DEVDOCS DOWNLOAD -- pull real documentation offline from devdocs.io
-- ============================================================================

local BAR_WIDTH = 24

--- Renders an ASCII block progress bar [████░░░░] for a 0-1 fraction.
local function make_bar(frac)
	local filled = math.floor(frac * BAR_WIDTH)
	return "[" .. string.rep("█", filled) .. string.rep("░", BAR_WIDTH - filled) .. "]"
end

--- Fetches the list of every documentation set devdocs.io serves.
--- @param callback fun(list: table[]) Called with the decoded docs.json array.
function M.fetch_available(callback)
	vim.system({ "curl", "-sL", M.settings.devdocs_index_url }, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then
				notify("Failed to reach devdocs.io: " .. (obj.stderr or "unknown error"), vim.log.levels.ERROR)
				return
			end
			local ok, list = pcall(vim.json.decode, obj.stdout)
			if not ok or type(list) ~= "table" then
				notify("Failed to parse devdocs.io doc list", vim.log.levels.ERROR)
				return
			end
			callback(list)
		end)
	end)
end

--- Downloads one devdocs.io doc set, writing one `.html` file per page.
--- Progress is shown as a single updating toast (no new toast per tick).
---
--- @param slug string devdocs slug, e.g. "python~3.12", "lua~5.4", "node".
--- @param callback fun(ok: boolean, lang: string|nil, version: string|nil)|nil
function M.download(slug, callback)
	slug = vim.trim(slug or "")
	if slug == "" then
		return
	end

	local krs_notify = require("krs.core.notify")
	local toast_id = "doc_download_" .. slug
	local toast_opts = { title = "📥 DocManager" }

	krs_notify.notify_progress(
		toast_id,
		"⬇️  " .. slug .. "\nFetching from devdocs.io…",
		vim.log.levels.INFO,
		toast_opts
	)

	local db_url = M.settings.devdocs_documents_base .. "/" .. slug .. "/db.json"

	vim.system({ "curl", "-sL", db_url }, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then
				krs_notify.notify_progress(
					toast_id,
					"❌  " .. slug .. "\nFailed: " .. (obj.stderr or "unknown error"),
					vim.log.levels.ERROR,
					toast_opts
				)
				krs_notify.finish_progress(toast_id)
				if callback then
					callback(false)
				end
				return
			end

			local ok, pages = pcall(vim.json.decode, obj.stdout)
			if not ok or type(pages) ~= "table" then
				krs_notify.notify_progress(
					toast_id,
					"❌  " .. slug .. "\nFailed to parse response.",
					vim.log.levels.ERROR,
					toast_opts
				)
				krs_notify.finish_progress(toast_id)
				if callback then
					callback(false)
				end
				return
			end

			local lang, version = slug:match("^([^~]+)~?(.*)$")
			if not version or version == "" then
				version = "latest"
			end

			local target_dir = M.settings.docs_dir .. "/" .. lang .. "/" .. version
			vim.fn.mkdir(target_dir, "p")

			-- Flatten pages so we can write in scheduled chunks
			local page_list = {}
			for page_path, html in pairs(pages) do
				table.insert(page_list, { path = page_path, html = html })
			end

			local total = #page_list
			local done = 0
			local CHUNK = 20 -- files per scheduler tick

			local function write_chunk()
				local limit = math.min(done + CHUNK, total)
				while done < limit do
					done = done + 1
					local entry = page_list[done]
					local rel = entry.path:gsub("[^%w_%-/%.]", "_")
					if rel == "" then
						rel = "index"
					end
					local fpath = target_dir .. "/" .. rel .. ".html"
					vim.fn.mkdir(vim.fn.fnamemodify(fpath, ":h"), "p")
					local f = io.open(fpath, "w")
					if f then
						f:write(entry.html)
						f:close()
					end
				end

				local frac = total > 0 and (done / total) or 0
				local pct = math.floor(frac * 100)
				krs_notify.notify_progress(
					toast_id,
					string.format("⬇️  %s\n%s  %d%%  (%d / %d)", slug, make_bar(frac), pct, done, total),
					vim.log.levels.INFO,
					toast_opts
				)

				if done < total then
					vim.schedule(write_chunk)
				else
					krs_notify.notify_progress(
						toast_id,
						string.format("✅  %s\n%d pages saved → %s", slug, done, target_dir),
						vim.log.levels.INFO,
						toast_opts
					)
					krs_notify.finish_progress(toast_id)
					if callback then
						callback(true, lang, version)
					end
				end
			end

			vim.schedule(write_chunk)
		end)
	end)
end

-- ============================================================================
-- HTML RENDER -- show downloaded HTML docs as readable markdown in the buffer
-- ============================================================================

--- Converts a devdocs HTML page into rough markdown, good enough for
--- render-markdown.nvim to display headings/lists/code/links legibly.
--- @param html string
--- @return string[] lines
local function html_to_md(html)
	local text = html
	text = text:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt].->.-</[Ss][Cc][Rr][Ii][Pp][Tt]>", "")
	text = text:gsub("<[Ss][Tt][Yy][Ll][Ee].->.-</[Ss][Tt][Yy][Ll][Ee]>", "")
	text = text:gsub("<[Bb][Rr]%s*/?>", "\n")
	text = text:gsub("<[Hh]([1-6])[^>]*>", function(n)
		return "\n" .. string.rep("#", tonumber(n) or 1) .. " "
	end)
	text = text:gsub("</[Hh][1-6]>", "\n")
	text = text:gsub("<[Ll][Ii][^>]*>", "\n- ")
	text = text:gsub("<[Pp][^>]*>", "\n")
	text = text:gsub("</[Pp]>", "\n")
	text = text:gsub("<[Dd][Ii][Vv][^>]*>", "\n")
	text = text:gsub("<[Pp][Rr][Ee][^>]*>", "\n```\n")
	text = text:gsub("</[Pp][Rr][Ee]>", "\n```\n")
	text = text:gsub("<[Cc][Oo][Dd][Ee][^>]*>", "`")
	text = text:gsub("</[Cc][Oo][Dd][Ee]>", "`")
	text = text:gsub("<[Ss][Tt][Rr][Oo][Nn][Gg][^>]*>", "**"):gsub("</[Ss][Tt][Rr][Oo][Nn][Gg]>", "**")
	text = text:gsub("<[Bb][^>]*>", "**"):gsub("</[Bb]>", "**")
	text = text:gsub("<[Ee][Mm][^>]*>", "*"):gsub("</[Ee][Mm]>", "*")
	text = text:gsub("<[Ii][^>]*>", "*"):gsub("</[Ii]>", "*")
	text = text:gsub('<[Aa]%s+[^>]-href="(.-)"[^>]*>(.-)</[Aa]>', "[%2](%1)")
	text = text:gsub("<[^>]+>", "")
	text = text
		:gsub("&lt;", "<")
		:gsub("&gt;", ">")
		:gsub("&quot;", '"')
		:gsub("&#39;", "'")
		:gsub("&nbsp;", " ")
		:gsub("&amp;", "&")
	text = text:gsub("\n[ \t]+", "\n"):gsub("\n\n\n+", "\n\n")

	return vim.split(vim.trim(text), "\n")
end

--- Renders the downloaded-HTML doc buffer as markdown (read-only) so
--- render-markdown.nvim can display it legibly instead of raw tags.
local function render_html_buffer(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local md = html_to_md(table.concat(lines, "\n"))
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, md)
	vim.bo[bufnr].filetype = "markdown"
	vim.bo[bufnr].modified = false
	vim.bo[bufnr].readonly = true
	vim.bo[bufnr].modifiable = false
end

--- Fetches the devdocs.io catalog and lets the user pick a doc set to download.
function M.browse_and_download()
	M.fetch_available(function(list)
		table.sort(list, function(a, b)
			return a.name < b.name or (a.name == b.name and a.slug < b.slug)
		end)

		pick("📥 Download DevDocs Documentation (Offline)", list, function(entry)
			return "📘 "
				.. entry.name
				.. ((entry.version or "") ~= "" and (" " .. entry.version) or "")
				.. "  ["
				.. entry.slug
				.. "]"
		end, function(entry)
			M.download(entry.slug)
		end)
	end)
end

--- Main interactive Offline Doc Manager UI picker.
function M.open_manager()
	local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "lua"
	local options = {
		{ label = "⬇️ Download Docs from DevDocs.io (Offline)", action = M.browse_and_download },
		{ label = "🔍 Search All Offline Docs (Telescope Grep)", action = M.search_docs },
		{
			label = "📖 View Docs for Current Language (" .. ft .. ")",
			action = function()
				M.view_docs(ft)
			end,
		},
		{
			label = "➕ Create New Offline Doc (Add Topic)",
			action = function()
				M.add_doc(ft)
			end,
		},
		{
			label = "📂 Open Offline Docs Root Folder in Explorer",
			action = function()
				vim.cmd("Neotree show dir=" .. vim.fn.fnameescape(M.ensure_dir()))
			end,
		},
	}

	pick("📚 KRS Offline Documentation Store", options, function(item)
		return item.label
	end, function(item)
		item.action()
	end)
end

--- Registers user commands and keymaps.
function M.setup()
	vim.api.nvim_create_user_command("DocManager", function()
		M.open_manager()
	end, { desc = "Open KRS Offline Doc Manager" })

	vim.api.nvim_create_user_command("KrsDocManager", function()
		M.open_manager()
	end, { desc = "Open KRS Offline Doc Manager" })

	vim.api.nvim_create_user_command("KrsDocOpen", function()
		M.pick_open_docs()
	end, { desc = "Open downloaded docs (current buffer's language pre-selected)" })

	vim.api.nvim_create_user_command("KrsDocSearch", function(opts)
		M.search_docs(opts.args ~= "" and opts.args or nil)
	end, { nargs = "?", desc = "Search offline documentation" })

	vim.api.nvim_create_user_command("KrsDocView", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		M.view_docs(args[1], args[2])
	end, { nargs = "*", desc = "View offline docs for language and version" })

	vim.api.nvim_create_user_command("KrsDocAdd", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		M.add_doc(args[1], args[2], args[3])
	end, { nargs = "*", desc = "Add new offline doc topic" })

	vim.api.nvim_create_autocmd("BufReadPost", {
		pattern = M.settings.docs_dir .. "/*/*/**",
		callback = function(ev)
			if ev.file:match("%.html?$") then
				render_html_buffer(ev.buf)
			end
		end,
		desc = "Render offline HTML docs as markdown",
	})

	vim.api.nvim_create_user_command("KrsDocDownload", function(opts)
		if opts.args ~= "" then
			M.download(opts.args)
		else
			M.browse_and_download()
		end
	end, { nargs = "?", desc = "Download real docs from devdocs.io for offline use" })
end

return setmetatable({
	name = "doc_manager",
	dir = require("krs.core.lazyspec").for_module(),
	event = "VeryLazy",
	config = M.setup,
}, { __index = M })
