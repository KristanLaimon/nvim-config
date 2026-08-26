-- ============================================================================
-- PLUGIN: cord.nvim -- Discord rich presence.
-- ============================================================================
-- Shows what you are editing on your Discord profile: file, repository and
-- elapsed time, idle after five minutes. Purely cosmetic; toggle it at runtime
-- with `:Cord toggle` (also in the command palette under "Discord").
-- Hot-reload configuration without restarting Neovim via `:CordReload`.
-- ============================================================================

local function hot_reload()
	package.loaded["plugins.ui.discord"] = nil
	package.loaded["cord"] = nil
	package.loaded["cord.api.config"] = nil

	local ok_spec, spec = pcall(require, "plugins.ui.discord")
	if not ok_spec or type(spec) ~= "table" then
		vim.notify("❌ Failed to reload Discord spec", vim.log.levels.ERROR, { title = "Discord Plugin" })
		return
	end

	local opts = spec.opts or {}
	local ok_cord, cord = pcall(require, "cord")
	if ok_cord and cord.setup then
		cord.setup(opts)
		pcall(function()
			require("cord.api.command").restart()
		end)
		vim.notify(
			"🎮 Discord plugin (cord.nvim) hot-reloaded successfully!",
			vim.log.levels.INFO,
			{ title = "Discord Plugin" }
		)
	else
		vim.notify(
			"⚠️ cord.nvim module not found, updated spec only",
			vim.log.levels.WARN,
			{ title = "Discord Plugin" }
		)
	end
end

for _, name in ipairs({ "DiscordReload", "CordReload" }) do
	pcall(vim.api.nvim_create_user_command, name, hot_reload, { desc = "Hot-reload Discord plugin (cord.nvim)" })
end

return {
	"vyfor/cord.nvim",
	build = ":Cord update",
	event = "VeryLazy",
	opts = {
		usercmds = true,
		timer = {
			enable = true,
		},
		editor = {
			client = "neovim",
			tooltip = "Neovim",
		},
		display = {
			theme = "minecraft",
			flavor = "dark",
			show_time = true,
			show_repository = true,
		},
		idle = {
			enable = true,
			show_status = true,
			timeout = 300000,
		},
		text = {
			terminal = function()
				local cur_buf = vim.api.nvim_get_current_buf()
				if vim.bo[cur_buf].buftype == "terminal" then
					return "Running commands in nvim terminal"
				end
				return false
			end,
		},
	},
}
