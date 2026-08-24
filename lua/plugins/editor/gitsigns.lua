-- ============================================================================
-- PLUGINS: GitSigns -- git signs in signcolumn, hunk previews & stage/reset.
-- ============================================================================

local env_ok, env_mod = pcall(require, "krs.core.environment")
local is_mobile_or_proot = false
if env_ok then
	local env = env_mod.detect()
	is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile
else
	is_mobile_or_proot = vim.env.TERMUX_VERSION ~= nil
end

return {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		signs = {
			add = { text = "▎" },
			change = { text = "▎" },
			delete = { text = "" },
			topdelete = { text = "" },
			changedelete = { text = "▎" },
			untracked = { text = "▎" },
		},
		signcolumn = true,
		numhl = false,
		linehl = false,
		word_diff = false,
		watch_gitdir = {
			enable = not is_mobile_or_proot,
			interval = 1500,
			follow_files = true,
		},
		attach_to_untracked = true,
		current_line_blame = false,
		preview_config = {
			border = "rounded",
			style = "minimal",
			relative = "cursor",
			row = 0,
			col = 1,
		},
		on_attach = function(bufnr)
			local gs = package.loaded.gitsigns
			if not gs then
				return
			end

			local function map(mode, l, r, opts)
				opts = opts or {}
				opts.buffer = bufnr
				vim.keymap.set(mode, l, r, opts)
			end

			-- Hunk Navigation
			map("n", "]c", function()
				if vim.wo.diff then
					return "]c"
				end
				vim.schedule(function()
					gs.next_hunk()
				end)
				return "<Ignore>"
			end, { expr = true, desc = "Next Git Hunk" })

			map("n", "[c", function()
				if vim.wo.diff then
					return "[c"
				end
				vim.schedule(function()
					gs.prev_hunk()
				end)
				return "<Ignore>"
			end, { expr = true, desc = "Previous Git Hunk" })

		end,
	},
}
