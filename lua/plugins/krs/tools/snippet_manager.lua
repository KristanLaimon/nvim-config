-- ============================================================================
-- KRS PLUGIN: Snippet Manager -- Create, edit, override and manage snippets.
-- ============================================================================
-- WHAT IT DOES
--   Manages per-language snippets stored in VSCode JSON format inside
--   `stdpath("config")/snippets/<language>.json`.
--   Integrates natively with blink.cmp autocompletion engine and provides full
--   CRUD operations (Create, Edit, Delete, List, Reload).
--
-- COMMANDS
--   :SnippetManager / :KrsSnippetManager  Open the Snippet Manager UI.
--   :KrsSnippetEdit [lang]               Open/Create snippets file for language.
--   :KrsSnippetAdd [lang]                Interactively add a new snippet.
--   :KrsSnippetReload                    Reload snippet definitions.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

M.settings = {
	snippets_dir = vim.fn.stdpath("config") .. "/snippets",
	notify_title = "KRS Snippet Manager",
	default_languages = {
		"lua",
		"typescript",
		"javascript",
		"php",
		"python",
		"go",
		"cs",
		"html",
		"css",
		"json",
		"markdown",
		"sh",
	},
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

--- Ensures the snippets directory exists.
--- @return string dir_path
function M.ensure_dir()
	local dir = M.settings.snippets_dir
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir
end

--- Gets current filetype or prompts if unspecified.
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

--- Returns the absolute path to a language snippet JSON file.
--- @param lang string
--- @return string
function M.get_snippet_file(lang)
	M.ensure_dir()
	return M.settings.snippets_dir .. "/" .. lang .. ".json"
end

--- Returns starter template content for a new language snippet file.
--- @param lang string
--- @return string
local function get_starter_json(lang)
	local tmpl = {
		["Example " .. lang:gsub("^%l", string.upper) .. " Snippet"] = {
			prefix = "ex_" .. lang,
			body = {
				"-- " .. lang .. " snippet example",
				"local function ${1:name}()",
				"\t${0}",
				"end",
			},
			description = "Example starter snippet for " .. lang,
		},
	}
	return vim.json.encode(tmpl)
end

--- Opens the JSON snippet file for a given language for direct editing.
--- Creates a valid starter JSON file if it does not exist.
--- @param lang string|nil
function M.edit_snippets(lang)
	lang = resolve_lang(lang)
	local filepath = M.get_snippet_file(lang)

	if vim.fn.filereadable(filepath) == 0 then
		local f = io.open(filepath, "w")
		if f then
			f:write(get_starter_json(lang))
			f:close()
		end
	end

	vim.cmd("edit " .. vim.fn.fnameescape(filepath))
	notify("Editing snippets for: " .. lang .. "\nPath: " .. filepath)
end

--- Reads and parses the JSON snippet file for a language.
--- @param lang string
--- @return table snippets, string filepath
function M.read_snippets(lang)
	local filepath = M.get_snippet_file(lang)
	if vim.fn.filereadable(filepath) == 0 then
		return {}, filepath
	end
	local f = io.open(filepath, "r")
	if not f then
		return {}, filepath
	end
	local content = f:read("*a")
	f:close()
	if not content or content == "" then
		return {}, filepath
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if ok and type(decoded) == "table" then
		return decoded, filepath
	end
	return {}, filepath
end

--- Writes a snippets table to the JSON snippet file for a language.
--- @param lang string
--- @param snippets table
--- @return boolean success
function M.write_snippets(lang, snippets)
	local filepath = M.get_snippet_file(lang)
	local f = io.open(filepath, "w")
	if not f then
		notify("Failed to write to file: " .. filepath, vim.log.levels.ERROR)
		return false
	end

	local ok, encoded = pcall(vim.json.encode, snippets)
	if not ok then
		notify("Failed to encode JSON snippets", vim.log.levels.ERROR)
		f:close()
		return false
	end

	f:write(encoded)
	f:close()
	notify("Updated snippets for " .. lang .. " (" .. filepath .. ")")

	-- Format open buffer if currently editing it
	local buf = vim.fn.bufnr(filepath)
	if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("edit!")
		end)
	end
	return true
end

--- Interactive UI to add a new snippet to a language.
--- @param lang string|nil
function M.add_snippet(lang)
	lang = resolve_lang(lang)

	vim.ui.input({ prompt = "Snippet Name: ", default = "My New Snippet" }, function(name)
		if not name or name == "" then
			return
		end

		vim.ui.input({ prompt = "Prefix (trigger word): ", default = "my_prefix" }, function(prefix)
			if not prefix or prefix == "" then
				return
			end

			vim.ui.input({ prompt = "Body (use \\n for lines, ${1:placeholder}): " }, function(body_str)
				if not body_str or body_str == "" then
					return
				end

				vim.ui.input({ prompt = "Description: ", default = name }, function(desc)
					local body_lines = {}
					for line in string.gmatch(body_str, "[^\r\n]+") do
						table.insert(body_lines, line)
					end
					if #body_lines == 0 then
						body_lines = { body_str }
					end

					local snippets = M.read_snippets(lang)
					snippets[name] = {
						prefix = prefix,
						body = body_lines,
						description = desc or name,
					}

					if M.write_snippets(lang, snippets) then
						notify("Added snippet '" .. name .. "' [" .. prefix .. "] to " .. lang)
					end
				end)
			end)
		end)
	end)
end

--- Browses snippets for a language using Telescope or vim.ui.select.
--- @param lang string|nil
function M.list_snippets(lang)
	lang = resolve_lang(lang)
	local snippets = M.read_snippets(lang)
	local entries = {}

	for name, data in pairs(snippets) do
		local prefix = data.prefix or name
		local desc = data.description or ""
		local body = type(data.body) == "table" and table.concat(data.body, "\n  ") or tostring(data.body)
		table.insert(entries, {
			name = name,
			prefix = prefix,
			desc = desc,
			body = body,
			raw = data,
		})
	end

	if #entries == 0 then
		notify("No custom snippets found for language: " .. lang .. ". Use :KrsSnippetEdit " .. lang .. " to create some!")
		return
	end

	local has_telescope, pickers = pcall(require, "telescope.pickers")
	local finders = pcall(require, "telescope.finders") and require("telescope.finders")
	local conf = pcall(require, "telescope.config") and require("telescope.config").values
	local actions = pcall(require, "telescope.actions") and require("telescope.actions")
	local action_state = pcall(require, "telescope.actions.state") and require("telescope.actions.state")

	if has_telescope and finders and conf and actions and action_state then
		pickers
			.new({}, {
				prompt_title = "📋 Custom Snippets (" .. lang .. ")",
				finder = finders.new_table({
					results = entries,
					entry_maker = function(entry)
						return {
							value = entry,
							display = string.format("[%-12s] %-25s - %s", entry.prefix, entry.name, entry.desc),
							ordinal = entry.prefix .. " " .. entry.name .. " " .. entry.desc .. " " .. entry.body,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, _)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection then
							local item = selection.value
							vim.ui.select({
								"📝 Edit raw JSON file",
								"🗑️ Delete snippet '" .. item.name .. "'",
							}, { prompt = "Action for snippet [" .. item.prefix .. "]:" }, function(choice)
								if choice and choice:find("Edit") then
									M.edit_snippets(lang)
								elseif choice and choice:find("Delete") then
									local cur_snippets = M.read_snippets(lang)
									cur_snippets[item.name] = nil
									M.write_snippets(lang, cur_snippets)
								end
							end)
						end
					end)
					return true
				end,
			})
			:find()
	else
		local items = {}
		for _, e in ipairs(entries) do
			table.insert(items, string.format("[%s] %s: %s", e.prefix, e.name, e.desc))
		end
		vim.ui.select(items, { prompt = "Snippets for " .. lang }, function(_, idx)
			if idx then
				M.edit_snippets(lang)
			end
		end)
	end
end

--- Main interactive Snippet Manager picker.
function M.open_manager()
	local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "lua"
	local options = {
		"📝 Edit Snippets for Current Filetype (" .. ft .. ")",
		"➕ Add Snippet to Current Filetype (" .. ft .. ")",
		"📋 List Snippets for Current Filetype (" .. ft .. ")",
		"🌐 Select Specific Language to Edit...",
		"📂 Open Snippets Directory in Neo-tree",
		"🔄 Reload Completion Engine (blink.cmp)",
	}

	vim.ui.select(options, { prompt = "⚡ KRS Snippet Manager" }, function(choice, idx)
		if not idx then
			return
		end

		if idx == 1 then
			M.edit_snippets(ft)
		elseif idx == 2 then
			M.add_snippet(ft)
		elseif idx == 3 then
			M.list_snippets(ft)
		elseif idx == 4 then
			vim.ui.input(
				{ prompt = "Enter language (e.g. lua, typescript, php, python, go, cs): ", default = ft },
				function(l)
					if l and l ~= "" then
						M.edit_snippets(l)
					end
				end
			)
		elseif idx == 5 then
			local dir = M.ensure_dir()
			vim.cmd("Neotree " .. vim.fn.fnameescape(dir))
		elseif idx == 6 then
			vim.cmd("lazy reload blink.cmp")
			notify("Reloaded blink.cmp completion engine!")
		end
	end)
end

--- Registers user commands and keymaps.
function M.setup()
	vim.api.nvim_create_user_command("SnippetManager", function()
		M.open_manager()
	end, { desc = "Open KRS Snippet Manager" })

	vim.api.nvim_create_user_command("KrsSnippetManager", function()
		M.open_manager()
	end, { desc = "Open KRS Snippet Manager" })

	vim.api.nvim_create_user_command("KrsSnippetEdit", function(opts)
		M.edit_snippets(opts.args ~= "" and opts.args or nil)
	end, { nargs = "?", desc = "Edit language snippets JSON" })

	vim.api.nvim_create_user_command("KrsSnippetAdd", function(opts)
		M.add_snippet(opts.args ~= "" and opts.args or nil)
	end, { nargs = "?", desc = "Add a new snippet interactively" })

	vim.api.nvim_create_user_command("KrsSnippetReload", function()
		vim.cmd("lazy reload blink.cmp")
		notify("Reloaded blink.cmp completion engine!")
	end, { desc = "Reload completion snippets" })
end

return setmetatable({
	name = "snippet_manager",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = false,
	config = M.setup,
}, { __index = M })
