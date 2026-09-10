-- ============================================================================
-- COLORSCHEME: omarchy-krs -- Dynamic colorscheme synced with Omarchy Linux.
-- ============================================================================

local omarchy_theme = require("plugins.krs.ui.omarchy_theme")
if not omarchy_theme.is_omarchy_available() then
	vim.notify("⚠️ Omarchy theme sync is only supported on Omarchy Linux.", vim.log.levels.WARN)
	pcall(vim.cmd.colorscheme, "nagatoro-krs")
	return
end

local ok = omarchy_theme.apply_omarchy_theme({ quiet = true })
if not ok then
	-- Fallback to default nagatoro-krs if Omarchy is unavailable
	pcall(vim.cmd.colorscheme, "nagatoro-krs")
end
