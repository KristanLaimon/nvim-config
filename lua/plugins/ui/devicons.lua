-- ============================================================================
-- PLUGIN: mini.icons -- filetype icons for every list in the editor.
-- ============================================================================
-- Replaces nvim-web-devicons. Devicons' default JS/TS glyphs are the plain
-- "JS"/"TS" brand-logo icons; mini.icons draws its default set from Material
-- Design Icons instead, which is what this file is picking on purpose.
--
-- `mock_nvim_web_devicons()` makes `require("nvim-web-devicons")` (used by
-- bufferline, neo-tree, telescope, etc.) transparently resolve to mini.icons,
-- so none of those plugin configs need to change.
--
-- The `.krsnvim` and `.proto` icons are registered as both extension and
-- filetype, same as before, because each consumer looks them up differently.
--
-- mini.icons LINKS its 9 `MiniIcons*` groups to built-in highlight groups by
-- default, on purpose, to "blend with the colorscheme" -- with nagatoro-krs
-- that means every icon inherits the same accent colour instead of keeping
-- its own hue. Fixed hex below overrides that; reapplied on every
-- `ColorScheme` event because a colorscheme change re-links them.
-- ============================================================================

local mini_icons_palette = {
	MiniIconsAzure = "#3a8bfd",
	MiniIconsBlue = "#4e79f0",
	MiniIconsCyan = "#22d3ee",
	MiniIconsGreen = "#6cc644",
	MiniIconsGrey = "#8c8c8c",
	MiniIconsOrange = "#f38019",
	MiniIconsPurple = "#a855f7",
	MiniIconsRed = "#f14c4c",
	MiniIconsYellow = "#f1e05a",
}

local function apply_mini_icons_palette()
	for group, fg in pairs(mini_icons_palette) do
		vim.api.nvim_set_hl(0, group, { fg = fg, default = false })
	end
end

return {
	{
		"nvim-mini/mini.icons",
		version = false,
		event = "VeryLazy",
		-- Must configure before bufferline/neo-tree/telescope/devicons.lua ever
		-- call require("nvim-web-devicons"), so the mock is in place first.
		priority = 10000,
		opts = {
			style = "glyph",
			extension = {
				krsnvim = { glyph = "🦊", hl = "MiniIconsOrange" },
				proto = { glyph = "", hl = "MiniIconsAzure" },
				lua = { hl = "MiniIconsBlue" },
			},
			filetype = {
				krsnvim = { glyph = "🦊", hl = "MiniIconsOrange" },
				proto = { glyph = "", hl = "MiniIconsAzure" },
				lua = { hl = "MiniIconsBlue" },
			},
		},
		config = function(_, opts)
			require("mini.icons").setup(opts)
			require("mini.icons").mock_nvim_web_devicons()
			apply_mini_icons_palette()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("krs_mini_icons_palette", { clear = true }),
				callback = apply_mini_icons_palette,
			})
		end,
	},
}
