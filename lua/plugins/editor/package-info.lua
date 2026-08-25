-- ============================================================================
-- PLUGIN: package-info -- npm versions inline in package.json.
-- ============================================================================
-- Shows current and available versions next to each dependency, and can update,
-- delete or install packages from there. `<leader>n` + s/c/u/d/i/p.
--
-- `autostart = false` on purpose: on open it would shell out to the package
-- manager for every dependency, which stalls a large package.json. Press
-- <leader>ns when you actually want the versions.
-- ============================================================================

return {
	"vuki656/package-info.nvim",
	dependencies = "MunifTanjim/nui.nvim",
	ft = "json",
	config = function()
		require("package-info").setup({
			autostart = false, -- Prevent automatic background execution of pnpm/yq shell commands on file open
			hide_up_to_date = true,
			hide_unstable_versions = true,
			-- Auto-detects via lockfile (bun.lock, pnpm-lock.yaml, etc); this is fallback
			package_manager = "bun",
		})
	end,
}
