-- ============================================================================
-- KRS PLUGIN: Git Center -- Config & State Management
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local git = lazy_req("krs.git.cmd")
local status = lazy_req("krs.git.status")
local diff = lazy_req("krs.git.diff")
local submodules = lazy_req("krs.git.submodules")
local ui = lazy_req("krs.core.ui")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path_util = lazy_req("krs.core.path")
local icons = lazy_req("krs.core.icons")

local env_ok, env_mod = pcall(require, "krs.core.environment")
local env = env_ok and env_mod.detect() or {}
local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
  --- Git Center geometry, as a fraction of the editor. The left panel takes
  --- `left_ratio` of the total width; the preview gets the rest.
  width_ratio = 0.92,
  height_ratio = 0.85,
  left_ratio = 0.30,

  --- Full-screen diff modal geometry.
  modal_width_ratio = 0.94,
  modal_height_ratio = 0.90,

  --- Commit message editor modal.
  editor_width_ratio = 0.65,
  editor_height = 6,

  --- Preview refresh delay after the cursor moves, in milliseconds. Enough to
  --- coalesce held-down `j`, short enough to feel immediate.
  preview_debounce_ms = is_mobile_or_proot and 130 or 40,

  --- Notification titles.
  notify_title = "Git Center",
  control_title = "Git Control Center",

  --- State persistence file name in project `.krsnvim/`.
  config_filename = "git-center.json",

  --- Submodule tab indicator colors mode (default: false = plain text, true = colored).
  tab_colored_indicators = false,

  keys = {
    --- Toggle the Git Center from anywhere.
    toggle = { "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>", "<leader>gc", "<leader>gC" },
    --- Stage everything from anywhere.
    stage_all = {
      "<C-S-x>",
      "<C-S-X>",
      "<C-A-s>",
      "<C-A-S>",
      "<C-M-s>",
      "<C-M-S>",
      "<A-C-s>",
      "<A-C-S>",
      "<M-C-s>",
      "<M-C-S>",
      "<A-s>",
      "<A-S>",
      "<M-s>",
      "<M-S>",
      "<leader>gs",
    },
    --- Switch submodule tabs (left / right).
    tab_prev = { "<A-h>", "<A-H>", "<M-h>", "<M-H>", "<A-Left>", "<M-Left>" },
    tab_next = { "<A-l>", "<A-L>", "<M-l>", "<M-L>", "<A-Right>", "<M-Right>" },
    --- Resize the split between left control panel and right preview pane.
    resize_left = { "<", ",", "<M-,>", "<A-,>", "<C-w><", "<C-Left>", "<C-S-Left>" },
    resize_right = { ">", ".", "<M-.>", "<A-.>", "<C-w>>", "<C-Right>", "<C-S-Right>" },
    --- Close the panel.
    close = { "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>", "q", "<Esc>", "<esc>", "<ESC>", "<C-[>" },
    --- Scroll the preview pane.
    scroll_down = { "<C-S-j>", "<C-S-J>", "<C-j>", "<C-J>" },
    scroll_up = { "<C-S-k>", "<C-S-K>", "<C-k>", "<C-K>" },
    --- Refresh the panel.
    refresh = { "<F5>", "<C-r>" },
    --- Close the diff modal.
    modal_close = { "q", "<Esc>", "<esc>", "<ESC>", "<C-[>", "<C-c>", "<C-S-g>", "<C-S-G>", "<C-g>", "<C-G>" },
    --- Open selected file in a bufferline tab.
    open_tab = { "<S-CR>", "<S-Enter>", "<S-Return>" },
  },
}

-- ============================================================================
-- STATE -- open windows, submodules, and the commit form
-- ============================================================================

M.main_win, M.main_buf = nil, nil
M.preview_win, M.preview_buf = nil, nil
M.tab_win, M.tab_buf = nil, nil
M.diff_modal_win, M.diff_modal_buf = nil, nil

--- Discovered repository list: [1] = root repository, [2..n] = submodules.
M.submodules = {}

M.ns_tabs = vim.api.nvim_create_namespace("krs_git_tabs")

--- Index of currently active submodule repository in `M.submodules`.
M.active_submodule_idx = 1

--- Project root directory.
M.root_dir = nil

--- Current left ratio (persisted per project and globally).
M.current_left_ratio = nil

--- Formatted diffs, keyed "<type>:<file>". Cleared on every refresh.
M.diff_cache = {}

--- Panel line number -> `{ type = "staged"|"unstaged"|"untracked", file = ... }`.
M.line_map = {}

--- The commit form, kept between openings so a draft is not lost.
M.commit_data = { title = "", description = "", tag = "" }

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
--- @param title string|nil Defaults to `M.settings.notify_title`.
function M.notify(msg, level, title)
  if type(msg) == "string" and #msg > 1000 then
    msg = msg:sub(1, 1000) .. "\n... [Truncated for UI]"
  end
  vim.notify(msg, level or vim.log.levels.INFO, { title = title or M.settings.notify_title })
end

-- ============================================================================
-- PERSISTENCE & SUBMODULE TARGET RESOLUTION
-- ============================================================================

M.GLOBAL_CONFIG_FILE = vim.fn.stdpath("data") .. "/krs_git_center.json"

--- Resolves the active target table: `{ name, path, is_root, full_path }`.
--- @return table
function M.get_active_target()
  if not M.submodules or #M.submodules == 0 then
    local root = M.root_dir or vim.fn.getcwd()
    return { name = "Root", path = ".", is_root = true, full_path = root }
  end
  return M.submodules[M.active_submodule_idx] or M.submodules[1]
end

--- Loads settings from project `.krsnvim/git-center.json` with fallback to global store.
--- @param root string|nil Project root directory.
--- @return table
function M.load_git_center_config(root)
  local global_data = store.load(M.GLOBAL_CONFIG_FILE, {})
  local project_cfg = root and project.config_path(M.settings.config_filename, root)
  local project_data = project_cfg and store.load(project_cfg, nil)

  local merged = {}
  if type(global_data) == "table" then
    for k, v in pairs(global_data) do
      merged[k] = v
    end
  end
  if type(project_data) == "table" then
    for k, v in pairs(project_data) do
      merged[k] = v
    end
  end
  return merged
end

--- Saves settings to both project `.krsnvim/git-center.json` and global store.
--- @param root string|nil Project root directory.
--- @param updates table
function M.save_git_center_config(root, updates)
  if root then
    local project_cfg = project.config_path(M.settings.config_filename, root)
    local data = store.load(project_cfg, {})
    for k, v in pairs(updates) do
      data[k] = v
    end
    store.save(project_cfg, data)
  end

  local global_data = store.load(M.GLOBAL_CONFIG_FILE, {})
  for k, v in pairs(updates) do
    global_data[k] = v
  end
  store.save(M.GLOBAL_CONFIG_FILE, global_data)
end

--- Loads the last active submodule tab identifier.
--- @param root string Project root directory.
--- @return string|nil saved_path Submodule relative path (e.g. "." or "plugins/foo").
function M.load_saved_active_tab(root)
  local data = M.load_git_center_config(root)
  return data.current_tab or data.active_tab
end

M.save_tab_timer = nil
--- Saves the active submodule tab identifier.
--- @param root string Project root directory.
--- @param target_path string Submodule relative path.
function M.save_active_tab(root, target_path)
  if M.save_tab_timer then
    M.save_tab_timer:stop()
    M.save_tab_timer = nil
  end
  M.save_tab_timer = vim.defer_fn(function()
    M.save_tab_timer = nil
    M.save_git_center_config(root, { current_tab = target_path, active_tab = target_path })
  end, 500)
end

--- Loads the saved left panel width ratio.
--- @param root string|nil Project root directory.
--- @return number ratio Left panel fraction (e.g. 0.50).
function M.load_saved_left_ratio(root)
  local data = M.load_git_center_config(root)
  local ratio = tonumber(data.left_ratio)
  if ratio and ratio >= 0.15 and ratio <= 0.85 then
    return ratio
  end
  return M.settings.left_ratio
end

--- Saves the left panel width ratio permanently.
--- @param root string|nil Project root directory.
--- @param ratio number Left panel fraction.
function M.save_left_ratio(root, ratio)
  M.save_git_center_config(root, { left_ratio = ratio })
end

return M
