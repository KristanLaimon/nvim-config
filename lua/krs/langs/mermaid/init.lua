-- ============================================================================
-- LANGUAGE: Mermaid
-- ============================================================================

local M = {}

M.bundle_name = "Mermaid"

M.treesitter = { "mermaid" }

M.mason_order = { "mmdc" }

M.mason = {
	["mmdc"] = {
		mason = "mmdc",
		cmd = "mmdc",
		type = "formatter",
		name = "Mermaid CLI",
	},
}

return M
