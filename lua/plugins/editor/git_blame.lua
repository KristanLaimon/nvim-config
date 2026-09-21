-- ============================================================================
-- PLUGIN: git-blame.nvim -- VS Code GitLens-style inline blame virtual text.
-- ============================================================================
-- Displays inline git blame info as subtle virtual text at the end of the line:
-- "  <author>, <date> • <summary>"
--
-- Ex commands:
--   :GitBlameToggle         -- Toggle inline virtual text
--   :GitBlameEnable         -- Turn inline virtual text on
--   :GitBlameDisable        -- Turn inline virtual text off
--   :GitBlameOpenCommitURL  -- Open commit in browser
--   :GitBlameCopyCommitURL  -- Copy commit URL to clipboard
--   :GitBlameCopySHA        -- Copy commit SHA to clipboard
--   :GitBlameOpenFileURL    -- Open file at commit in browser
--   :GitBlameCopyFileURL    -- Copy file URL to clipboard
-- ============================================================================

local function set_gitblame_highlight()
	vim.api.nvim_set_hl(0, "GitBlame", { default = false, link = "Comment", italic = true })
end

return {
	"f-person/git-blame.nvim",
	event = { "BufReadPre", "BufNewFile" },
	cmd = {
		"GitBlameToggle",
		"GitBlameEnable",
		"GitBlameDisable",
		"GitBlameOpenCommitURL",
		"GitBlameCopyCommitURL",
		"GitBlameCopySHA",
		"GitBlameOpenFileURL",
		"GitBlameCopyFileURL",
	},
	opts = {
		enabled = true,
		message_template = "  <author>, <date> • <summary>",
		date_format = "%r",
		message_when_not_committed = "  Not Committed Yet",
		highlight_group = "GitBlame",
		delay = 150,
		ignored_filetypes = {
			"neo-tree",
			"TelescopePrompt",
			"alpha",
			"dashboard",
			"help",
			"gitcommit",
			"lazy",
			"mason",
		},
	},
	config = function(_, opts)
		set_gitblame_highlight()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("krs_gitblame_hl", { clear = true }),
			callback = set_gitblame_highlight,
		})
		require("gitblame").setup(opts)
	end,
}
