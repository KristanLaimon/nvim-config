-- ============================================================================
-- CONFIG: lazy.nvim -- plugin manager bootstrap and import order.
-- ============================================================================
-- WHAT IT DOES
--   1. Clones lazy.nvim on first launch (nothing else is vendored).
--   2. Imports every plugin spec, one directory at a time.
--   3. Disables the built-in plugins this config replaces.
--
-- IMPORT ORDER MATTERS
--   ui -> editor -> lsp -> krs -> miscelanea. Specs later in the list may depend
--   on earlier ones (the KRS modules assume telescope and dap exist), and lazy
--   merges duplicate specs in this order.
--
-- ADDING A PLUGIN
--   Drop a new file in the matching lua/plugins/<area>/ directory that returns a
--   lazy spec. Nothing here needs to change. Files in SUBdirectories (for example
--   lua/plugins/krs/debuggers/) are NOT imported, which is what makes that a safe
--   place for helper modules.
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Where lazy.nvim itself is installed, and where it comes from.
	install_path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim",
	repo = "https://github.com/folke/lazy.nvim.git",
	branch = "stable",

	--- Spec directories, imported in this order.
	spec_modules = {
		"plugins.ui",
		"plugins.editor",
		"plugins.lsp",
		"plugins.krs.ui",
		"plugins.krs.editor",
		"plugins.krs.tools",
		"plugins.krs.git",
		"plugins.krs.dev",
	},

	--- Built-in plugins this config does not use. Skipping them shortens startup.
	disabled_builtins = {
		"gzip",
		"matchit",
		"matchparen",
		"netrwPlugin", -- replaced by neo-tree
		"tarPlugin",
		"tohtml",
		"tutor",
		"zipPlugin",
	},
}

-- ============================================================================
-- BOOTSTRAP
-- ============================================================================

if not (vim.uv or vim.loop).fs_stat(settings.install_path) then
	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=" .. settings.branch,
		settings.repo,
		settings.install_path,
	})

	-- Without lazy.nvim there is no config at all, so this is fatal on purpose.
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end

vim.opt.rtp:prepend(settings.install_path)

-- ============================================================================
-- SETUP
-- ============================================================================

local spec = {}
for _, module in ipairs(settings.spec_modules) do
	table.insert(spec, { import = module })
end

require("lazy").setup({
	spec = spec,
	-- Config files change constantly while working on them; the notification
	-- every time would be noise.
	change_detection = { notify = false },
	performance = {
		rtp = { disabled_plugins = settings.disabled_builtins },
	},
})
