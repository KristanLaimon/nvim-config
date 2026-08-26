-- ============================================================================
-- KRS CORE: Icons & Symbols Manager (Nerd Font vs Emoji Toggle)
-- ============================================================================
-- WHAT IT DOES
--   Manages UI icon symbols across Neovim. By default, uses crisp Nerd Font
--   vector glyphs (no plain white emoji rendering bugs). Allows toggling
--   between Nerd Font Symbols mode and Emoji mode via Command Palette,
--   persisting the preference in Neovim data store.
-- ============================================================================

local store = require("krs.core.store")

local CONFIG_FILE = vim.fn.stdpath("data") .. "/krs_icons_config.json"

local M = {}

M.settings = {
	use_emojis = false, -- Default: false (Nerd Font Symbols mode)
}

function M.load()
	local data = store.load(CONFIG_FILE, {})
	if data and data.use_emojis ~= nil then
		M.settings.use_emojis = data.use_emojis
	end
end

function M.save()
	store.save(CONFIG_FILE, { use_emojis = M.settings.use_emojis })
end

--- Dictionary mapping icon keys to { nerdfont, emoji } representations.
M.dictionary = {
	git = { nerdfont = "", emoji = "🐙" },
	dir = { nerdfont = "󰉋", emoji = "📁" },
	root = { nerdfont = "󰏗", emoji = "📦" },
	branch = { nerdfont = "󰘬", emoji = "🌿" },
	changes = { nerdfont = "󰦨", emoji = "📊" },
	staged = { nerdfont = "󰄬", emoji = "🟢" },
	unstaged = { nerdfont = "󰅖", emoji = "🔴" },
	untracked = { nerdfont = "󰋗", emoji = "❓" },
	preview = { nerdfont = "󰈈", emoji = "👁️" },
	commit = { nerdfont = "󰏫", emoji = "📝" },
	quick = { nerdfont = "󱐋", emoji = "⚡" },
	search = { nerdfont = "󰍉", emoji = "🔍" },
	workspace = { nerdfont = "󰂺", emoji = "💼" },
	close = { nerdfont = "󰅖", emoji = "🚪" },
	save = { nerdfont = "󰆓", emoji = "💾" },
	explorer = { nerdfont = "󰙅", emoji = "🌳" },
	lsp = { nerdfont = "󰒮", emoji = "💉" },
	info = { nerdfont = "󰋽", emoji = "ℹ️" },
	package = { nerdfont = "󰏗", emoji = "📦" },
	ui = { nerdfont = "󰏘", emoji = "🎨" },
	config = { nerdfont = "󰒓", emoji = "🧩" },
	rocket = { nerdfont = "󰞅", emoji = "🚀" },
	fox = { nerdfont = "󰄛", emoji = "🦊" },
	discord = { nerdfont = "󰙯", emoji = "🎮" },
	incoming = { nerdfont = "󰇚", emoji = "📥" },
	outgoing = { nerdfont = "󰇛", emoji = "📤" },
	dot = { nerdfont = "●", emoji = "●" },
	clean_dot = { nerdfont = "○", emoji = "○" },
}

--- Returns the icon string for the given key based on current mode
--- @param key string
--- @return string
function M.get(key)
	local entry = M.dictionary[key]
	if not entry then
		return ""
	end
	return M.settings.use_emojis and entry.emoji or entry.nerdfont
end

--- Toggles between Emoji icons and Nerd Font symbols mode
function M.toggle()
	M.settings.use_emojis = not M.settings.use_emojis
	M.save()

	local mode_name = M.settings.use_emojis and "Emoji Mode" or "Nerd Font Symbols Mode (Default)"
	vim.notify("🎨 UI Icons Mode Changed: " .. mode_name, vim.log.levels.INFO, { title = "UI Icons Settings" })

	-- Refresh open panels
	local ok_gc, gc = pcall(require, "plugins.krs.git.git_center")
	if ok_gc and gc.is_open and gc.is_open() and gc.refresh then
		gc.refresh()
	end
end

M.load()

-- Register global command
if vim.fn.exists(":ToggleIconsMode") == 0 then
	pcall(vim.api.nvim_create_user_command, "ToggleIconsMode", function()
		M.toggle()
	end, { desc = "Toggle UI Icons Mode (Nerd Font Symbols vs Emojis)" })
end

return M
