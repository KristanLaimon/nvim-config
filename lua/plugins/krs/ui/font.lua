-- ============================================================================
-- KRS PLUGIN: Font Manager -- GUI font size, persisted between sessions.
-- ============================================================================
-- WHAT IT DOES
--   Zooms the GUI font (`guifont`, and Neovide's scale factor) and remembers the
--   chosen size in `font_config.json` next to this config.
--
-- KEYS -- every one bound in normal, insert, visual and terminal mode
--   Ctrl +=/+/Numpad+/ScrollUp    Zoom in
--   Ctrl +-/_/Numpad-/ScrollDown  Zoom out
--   Ctrl +0/Numpad0               Reset
--
-- COMMANDS
--   :FontSizeIncrease  :FontSizeDecrease  :FontSizeReset
--
-- NOTE
--   This only affects GUI clients (Neovide, nvim-qt, ...). In a terminal the
--   font belongs to the terminal emulator and nvim cannot change it.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Font used for the GUI. Must be installed on the system.
	font_name = "JetBrainsMono Nerd Font",

	--- Starting size, and the size `:FontSizeReset` returns to.
	default_size = 14,

	--- Zoom limits, in points.
	min_size = 6,
	max_size = 40,

	--- Size change per keypress.
	step = 1,

	--- Where the chosen size is remembered.
	config_file = vim.fn.stdpath("data") .. "/font_config.json",

	--- Neovide's scale factor is a ratio; this size maps to 1.0.
	neovide_base_size = 14.0,

	--- Title on the zoom notifications.
	notify_title = "Font Manager (KRS)",

	keys = {
		increase = { "<C-=>", "<C-+>", "<C-S-=>", "<C-S-+>", "<C-kPlus>", "<C-KPPlus>", "<C-ScrollWheelUp>" },
		decrease = { "<C-->", "<C-S-->", "<C-S-_>", "<C-kMinus>", "<C-KPMinus>", "<C-ScrollWheelDown>" },
		reset = { "<C-0>", "<C-k0>", "<C-KP0>" },
	},
}

-- ============================================================================
-- STATE -- loaded from disk at require time
-- ============================================================================

local saved = store.load(M.settings.config_file, {})

--- Font size currently applied.
M.current_size = saved.font_size or M.settings.default_size

--- Font family currently applied.
M.font_name = saved.font_name or M.settings.font_name

-- ============================================================================
-- API
-- ============================================================================

--- Applies a font size, clamped to the configured limits, and persists it.
--- @param size integer Desired size in points.
function M.apply_font_size(size)
	size = math.max(M.settings.min_size, math.min(M.settings.max_size, size))
	M.current_size = size

	pcall(function()
		vim.o.guifont = M.font_name .. ":h" .. tostring(size)
	end)

	if vim.g.neovide then
		pcall(function()
			vim.g.neovide_scale_factor = size / M.settings.neovide_base_size
			-- Padding is reset with the scale, or Neovide keeps the old gaps.
			vim.g.neovide_padding_top = 0
			vim.g.neovide_padding_bottom = 0
			vim.g.neovide_padding_right = 0
			vim.g.neovide_padding_left = 0
		end)
	end

	store.save(M.settings.config_file, { font_size = size, font_name = M.font_name })
end

--- Applies `size` and notifies with `label`.
--- @param size integer
--- @param label string Text before the size in the notification.
local function apply_and_notify(size, label)
	M.apply_font_size(size)
	vim.notify("🔍 " .. label .. ": " .. M.current_size .. "pt", vim.log.levels.INFO, {
		title = M.settings.notify_title,
	})
end

--- Zooms in one step.
function M.increase()
	apply_and_notify(M.current_size + M.settings.step, "Font Size")
end

--- Zooms out one step.
function M.decrease()
	apply_and_notify(M.current_size - M.settings.step, "Font Size")
end

--- Returns to the default size.
function M.reset()
	apply_and_notify(M.settings.default_size, "Font Reset")
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Applies the saved size and binds the commands and keys.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	M.apply_font_size(M.current_size)

	local commands = {
		FontSizeIncrease = { M.increase, "Increase font size" },
		FontSizeDecrease = { M.decrease, "Decrease font size" },
		FontSizeReset = { M.reset, "Reset font size" },
	}
	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, spec[1], { desc = spec[2] })
		end
	end

	local actions = {
		{ keys = M.settings.keys.increase, fn = M.increase, desc = "Increase font size" },
		{ keys = M.settings.keys.decrease, fn = M.decrease, desc = "Decrease font size" },
		{ keys = M.settings.keys.reset, fn = M.reset, desc = "Reset font size" },
	}
	for _, action in ipairs(actions) do
		for _, key in ipairs(action.keys) do
			vim.keymap.set({ "n", "i", "v", "t" }, key, action.fn, {
				noremap = true,
				silent = true,
				desc = action.desc,
			})
		end
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.FontManager = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_font",
	dir = require("krs.core.lazyspec").for_module(),
	lazy = false,
	config = M.setup,
}, { __index = M })
