-- ============================================================================
-- KrsVim -- entry point (Neovim v0.12.4).
-- ============================================================================
-- Target / Current Neovim Version: NVIM v0.12.4
--
-- STARTUP ORDER (each step depends on the one before it)
--   1. vim_options   Editor options, filetypes, shell, PATH repair.
--   2. keymaps   Every keybinding, grouped by domain.
--   3. lazy_init      Bootstraps lazy.nvim and imports lua/plugins/*.
--
-- WHERE THINGS LIVE
--   lua/config/    Editor bootstrap: options, keymaps, plugin manager.
--   lua/krs/       Shared internal libraries (core, git, launch, lsp).
--   lua/plugins/   One lazy.nvim spec per file, grouped by area.
--   lua/krsnvim/   The krsnvimscript automation library (its own public API).
--   tests/         Unit specs (`nvim -l tests/run.lua`) and integration specs.
--   docs/          Architecture and feature documentation.
--
-- See docs/architecture.md for the full picture.
-- ============================================================================

-- Byte-compilation cache: cuts startup roughly in half on Windows.
if vim.loader then
	vim.loader.enable()
end

require("vim_options")
require("krs.core.keymap_registry").install()
require("keymaps")
require("lazy_init")

-- Reload the configuration without restarting. Only top-level config modules are
-- dropped from the cache; plugins keep their state, which is what makes this
-- fast enough to use while editing keymaps.
vim.api.nvim_create_user_command("ReloadConfig", function()
	for name, _ in pairs(package.loaded) do
		if name == "vim_options" or name == "lazy_init" or name:match("^keymaps") then
			package.loaded[name] = nil
		end
	end
	require("krs.core.keymap_registry").reset()
	dofile(vim.env.MYVIMRC)
	vim.notify("Config reloaded", vim.log.levels.INFO)
end, {})

-- Run the test suite from inside the editor. The same specs run headlessly with
-- `nvim -l tests/run.lua`; see tests/run.lua for the runner itself.
vim.api.nvim_create_user_command("KrsTest", function(command)
	local root = vim.fn.stdpath("config")
	local runner = dofile(root .. "/tests/run.lua")
	runner.run(root, command.args ~= "" and command.args or nil)
end, { nargs = "?", desc = "Run the KRS unit test suite (optionally filtered by spec name)" })

-- If nvim is being run inside Neovide GUI
if vim.g.neovide then
	vim.g.neovide_window_blurred = false
	vim.g.neovide_opacity = 0.96
	vim.g.neovide_normal_opacity = 0.96

	-- Cursor Motion & Trail Animation (Time in seconds)
	-- Try setting to 0.25 for slow motion, 0.05 for super snappy, or 0.0 to disable.
	vim.g.neovide_cursor_animation_length = 0.15
	vim.g.neovide_cursor_trail_size = 0.8 -- Trail size length (0.0 to 1.0)
	vim.g.neovide_cursor_animate_in_insert_mode = true
	vim.g.neovide_cursor_animate_command_line = true
	vim.g.neovide_cursor_unfocused_outline = true -- Draw outline cursor when window loses focus
end
