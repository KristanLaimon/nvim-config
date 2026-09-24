-- ============================================================================
-- Dynamic theme specification for Omarchy Linux environments.
-- ============================================================================
local omarchy_theme_path = vim.fn.expand("~/.local/state/omarchy/current/theme/neovim.lua")
if vim.fn.filereadable(omarchy_theme_path) == 1 then
	local ok, mod = pcall(dofile, omarchy_theme_path)
	if ok and type(mod) == "table" then
		return mod
	end
end

return {}
