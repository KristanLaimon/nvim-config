-- ============================================================================
-- KRS PLUGIN: Live Colorscheme Preview.
-- ============================================================================
-- WHAT IT DOES
--   While you type `:colorscheme <name>` (and tab through the completions) the
--   theme is applied live. Confirming with <CR> keeps it; cancelling with <Esc>
--   restores the theme you started from.
--
-- HOW IT WORKS
--   `CmdlineChanged` applies each candidate and remembers the original theme the
--   first time. `CmdlineLeave` checks `vim.v.event.abort`: on an aborted command
--   line with no theme applied, the original is put back.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Matches `:colo`/`:colorscheme` plus a single argument. The capture is the
	--- theme name to preview.
	command_pattern = "^colo%S*%s+(%S+)%s*$",

	--- Autocmd group owning both listeners.
	augroup = "KRSColorschemeLivePreview",
}

--- Theme active before the preview started; nil when no preview is in progress.
local original_colorscheme = nil

-- ============================================================================
-- API
-- ============================================================================

--- Theme named on the command line right now, if any.
--- @return string|nil name
local function pending_colorscheme()
	if vim.fn.getcmdtype() ~= ":" then
		return nil
	end
	return vim.fn.getcmdline():match(M.settings.command_pattern)
end

--- Installs the two command-line listeners.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup(M.settings.augroup, { clear = true })

	vim.api.nvim_create_autocmd("CmdlineChanged", {
		group = group,
		callback = function()
			local name = pending_colorscheme()
			if not name then
				return
			end
			original_colorscheme = original_colorscheme or vim.g.colors_name
			pcall(vim.cmd.colorscheme, name)
		end,
	})

	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		callback = function()
			if vim.fn.getcmdtype() ~= ":" then
				return
			end

			-- Aborted (<Esc>) with nothing applied: undo the preview.
			if original_colorscheme and vim.v.event.abort and not pending_colorscheme() then
				pcall(vim.cmd.colorscheme, original_colorscheme)
			end
			original_colorscheme = nil
		end,
	})
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.ColorschemePreview = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_colorscheme_preview",
	dir = require("krs.core.lazyspec").for_module(),
	event = "CmdlineEnter",
	config = M.setup,
}, { __index = M })
