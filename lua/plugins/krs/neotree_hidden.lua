-- ============================================================================
-- KRS PLUGIN: Neo-tree Custom Hidden Files & Folders Manager
-- ============================================================================
-- WHAT IT DOES
--   1. Visually hides files and folders marked as hidden in Neo-tree UI.
--   2. Provides shortcut 'H' (and 'gh') in Neo-tree to toggle hiding individual nodes.
--   3. Provides a Command Palette action / Ex commands to toggle showing/hiding all
--      marked items (or untoggling them).
--   4. Renders items marked as hidden with a theme-aware strikethrough color
--      (NeoTreeCustomHidden, linked to active theme's Comment group) in "show" mode.
--   5. Persists hidden paths per-project inside `.krsnvim/neotree_hidden.json`.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")

local M = {}

M.hidden_paths = {}
M.visibility_mode = "hide" -- "hide" or "show"
M.current_root = nil

local is_setup = false

local function normalize_path(p)
	if not p or p == "" then
		return ""
	end
	local clean = vim.fs.normalize(p)
	if #clean > 1 and clean:sub(-1) == "/" then
		clean = clean:sub(1, -2)
	end
	return clean
end

--- Converts an absolute path to a path relative to root_dir when possible.
--- @param abs_path string
--- @param root_dir string|nil
--- @return string
local function to_rel_path(abs_path, root_dir)
	root_dir = normalize_path(root_dir or project.root())
	local norm_abs = normalize_path(abs_path)
	if norm_abs == root_dir then
		return "."
	end
	if norm_abs:sub(1, #root_dir + 1) == root_dir .. "/" then
		return norm_abs:sub(#root_dir + 2)
	end
	return norm_abs
end

--- Resolves the per-project `.krsnvim/neotree_hidden.json` configuration file path.
--- @param root string|nil
--- @return string filepath
function M.get_config_path(root)
	root = root or project.root()
	return project.config_path("neotree_hidden.json", root)
end

--- Reads stored state from the project's `.krsnvim/neotree_hidden.json`.
--- @param root string|nil
function M.load_state(root)
	root = root or project.root()
	local file_path = M.get_config_path(root)
	local data = store.load(file_path, {})
	M.hidden_paths = {}
	if type(data) == "table" then
		if type(data.paths) == "table" then
			for _, p in ipairs(data.paths) do
				M.hidden_paths[normalize_path(p)] = true
			end
		end
		if data.visibility_mode == "hide" or data.visibility_mode == "show" then
			M.visibility_mode = data.visibility_mode
		end
	end
end

--- Saves state to `.krsnvim/neotree_hidden.json`.
--- @param root string|nil
function M.save_state(root)
	root = root or project.root()
	local file_path = M.get_config_path(root)
	local path_list = {}
	for p, _ in pairs(M.hidden_paths) do
		table.insert(path_list, p)
	end
	store.save(file_path, {
		paths = path_list,
		visibility_mode = M.visibility_mode,
	})
end

--- Ensures state is loaded for the current active project root.
--- @param root string|nil
function M.ensure_loaded(root)
	root = normalize_path(root or project.root())
	if M.current_root ~= root then
		M.current_root = root
		M.load_state(root)
	end
end

--- Checks if a path or any ancestor directory is marked as hidden.
--- @param path string
--- @param root string|nil
--- @return boolean
function M.is_path_hidden(path, root)
	if not path or path == "" then
		return false
	end
	root = root or project.root()
	M.ensure_loaded(root)

	if vim.tbl_isempty(M.hidden_paths) then
		return false
	end

	local norm_abs = normalize_path(path)
	local rel = to_rel_path(norm_abs, root)

	if M.hidden_paths[rel] or M.hidden_paths[norm_abs] then
		return true
	end

	-- Check relative ancestors
	local parent = vim.fn.fnamemodify(rel, ":h")
	local depth = 0
	while parent and parent ~= "" and parent ~= "." and parent ~= rel and depth < 30 do
		depth = depth + 1
		local parent_norm = normalize_path(parent)
		if M.hidden_paths[parent_norm] then
			return true
		end
		local next_parent = vim.fn.fnamemodify(parent_norm, ":h")
		if next_parent == parent_norm then
			break
		end
		parent = next_parent
	end

	-- Check absolute ancestors as fallback
	parent = vim.fn.fnamemodify(norm_abs, ":h")
	depth = 0
	while parent and parent ~= "" and parent ~= norm_abs and parent ~= "/" and depth < 30 do
		depth = depth + 1
		local parent_norm = normalize_path(parent)
		if M.hidden_paths[parent_norm] then
			return true
		end
		local next_parent = vim.fn.fnamemodify(parent_norm, ":h")
		if next_parent == parent_norm then
			break
		end
		parent = next_parent
	end

	return false
end

--- Toggles hidden status for a path in the active project.
--- @param path string
--- @param root string|nil
--- @return boolean is_now_hidden
function M.toggle_path(path, root)
	if not path or path == "" then
		return false
	end
	root = root or project.root()
	M.ensure_loaded(root)

	local norm_abs = normalize_path(path)
	local rel = to_rel_path(norm_abs, root)
	local name = vim.fn.fnamemodify(norm_abs, ":t")
	if name == "" then
		name = norm_abs
	end

	if M.hidden_paths[rel] or M.hidden_paths[norm_abs] then
		M.hidden_paths[rel] = nil
		M.hidden_paths[norm_abs] = nil
		M.save_state(root)
		M.refresh_neotree()
		vim.notify("👁️ Marked item UN-HIDDEN in Neo-tree: " .. name, vim.log.levels.INFO, { title = "Neo-tree" })
		return false
	else
		M.hidden_paths[rel] = true
		M.save_state(root)
		M.refresh_neotree()
		vim.notify("🙈 Marked item HIDDEN in Neo-tree (.krsnvim/neotree_hidden.json): " .. name, vim.log.levels.INFO, { title = "Neo-tree" })
		return true
	end
end

--- Toggles visibility mode between "hide" and "show".
--- @param root string|nil
function M.toggle_visibility(root)
	root = root or project.root()
	M.ensure_loaded(root)

	if M.visibility_mode == "hide" then
		M.visibility_mode = "show"
		vim.notify("👁️ Custom Hidden items are now VISIBLE (strikethrough theme color)", vim.log.levels.INFO, { title = "Neo-tree" })
	else
		M.visibility_mode = "hide"
		vim.notify("🙈 Custom Hidden items are now HIDDEN", vim.log.levels.INFO, { title = "Neo-tree" })
	end
	M.save_state(root)
	M.refresh_neotree()
end

--- Clears all marked hidden items for the active project.
--- @param root string|nil
function M.clear_all(root)
	root = root or project.root()
	M.ensure_loaded(root)
	M.hidden_paths = {}
	M.save_state(root)
	M.refresh_neotree()
	vim.notify("🧹 Cleared all marked hidden items in Neo-tree (.krsnvim/neotree_hidden.json)", vim.log.levels.INFO, { title = "Neo-tree" })
end

--- Triggers a Neo-tree refresh.
function M.refresh_neotree()
	pcall(function()
		require("neo-tree.sources.manager").refresh("filesystem")
	end)
end

--- Filters or decorates tree items according to hidden state.
--- @param items table[]
--- @param root string|nil
function M.filter_or_mark_items(items, root)
	if not items or type(items) ~= "table" then
		return
	end
	root = root or project.root()
	local i = 1
	while i <= #items do
		local item = items[i]
		local is_hidden = item.path and M.is_path_hidden(item.path, root)
		if is_hidden then
			if M.visibility_mode == "hide" then
				table.remove(items, i)
			else
				item.filtered_by = item.filtered_by or {}
				item.filtered_by.custom_hidden = true
				item.filtered_by.always_show = true
				if item.children and type(item.children) == "table" then
					M.filter_or_mark_items(item.children, root)
				end
				i = i + 1
			end
		else
			if item.children and type(item.children) == "table" then
				M.filter_or_mark_items(item.children, root)
			end
			i = i + 1
		end
	end
end

--- Configures theme-derived highlight group for hidden items with strikethrough & comment color.
function M.setup_highlights()
	vim.api.nvim_set_hl(0, "NeoTreeCustomHidden", {
		link = "Comment",
		strikethrough = true,
		italic = true,
		default = false,
	})
end

--- Initializes the neotree_hidden module and registers hooks.
function M.setup()
	if is_setup then
		return
	end
	is_setup = true

	M.ensure_loaded()
	M.setup_highlights()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("NeoTreeCustomHiddenHL", { clear = true }),
		callback = function()
			M.setup_highlights()
		end,
	})

	vim.api.nvim_create_autocmd("DirChanged", {
		group = vim.api.nvim_create_augroup("NeoTreeCustomHiddenDir", { clear = true }),
		callback = function()
			local root = project.root()
			M.ensure_loaded(root)
			M.refresh_neotree()
		end,
	})

	local ok_comp, common_components = pcall(require, "neo-tree.sources.common.components")
	if ok_comp and common_components then
		local orig_filtered_by = common_components.filtered_by
		common_components.filtered_by = function(config, node, state)
			local fby = node and node.filtered_by
			if fby and fby.custom_hidden then
				return {
					highlight = "NeoTreeCustomHidden",
				}
			end
			if orig_filtered_by then
				return orig_filtered_by(config, node, state)
			end
			return {}
		end
	end

	local ok_rend, renderer = pcall(require, "neo-tree.ui.renderer")
	if ok_rend and renderer then
		local orig_show_nodes = renderer.show_nodes
		renderer.show_nodes = function(sourceItems, state, parentId, callback)
			if sourceItems and type(sourceItems) == "table" then
				M.filter_or_mark_items(sourceItems)
			end
			return orig_show_nodes(sourceItems, state, parentId, callback)
		end
	end
end

M.name = "krs_neotree_hidden"
M.dir = require("krs.core.lazyspec").for_module()
M.lazy = false
M.config = M.setup

return M
