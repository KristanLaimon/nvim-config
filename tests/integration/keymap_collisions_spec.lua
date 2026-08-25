-- ============================================================================
-- tests/integration/keymap_collisions_spec.lua -- Fails on un-allowlisted
-- keymap collisions, including ones only created on VimEnter.
-- ============================================================================
-- WHY THIS LIVES HERE, NOT IN tests/spec
--   debug.lua rebinds toggle_enabled keys inside a VimEnter autocmd on
--   purpose (see debug.lua:163-193), so that collision only exists once the
--   event has actually fired. Neither `nvim -l tests/run.lua` (unit specs)
--   nor the `-c`/`-S` arguments this integration runner itself uses fire
--   VimEnter before quitting -- confirmed by checking `maparg("<A-h>", "n")`
--   after each: it stays "Previous buffer" (editor.lua) until VimEnter is
--   fired for real. So this spec fires it explicitly.
--
--   krs.core.keymap_registry keeps its own M.collisions log (not just a
--   fire-and-forget vim.notify) precisely so this spec can also see the
--   collisions that happened during the eager config.keymaps load, which
--   finishes before any spec file -- including this one -- gets to run.
--
--   git_center.lua binds its own toggle/stage_all keys from its lazy.nvim
--   `config = M.setup` callback, which only runs once the plugin is actually
--   loaded (its lazy spec `keys` table only stubs the keys, it doesn't load
--   the plugin outright) -- neither VimEnter nor the eager config.keymaps
--   load triggers that, so this spec also calls M.setup() directly to
--   surface collisions from it.
-- ============================================================================

local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("keymap collisions after a real startup", function()
	it("has no un-allowlisted mode+lhs collisions once VimEnter has fired and plugins open", function()
		vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
		require("plugins.krs.git_center").setup()
		require("plugins.krs.hover_links").setup()

		-- Create a markdown buffer and trigger FileType autocmd
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, "test_doc.md")
		vim.bo[buf].filetype = "markdown"
		vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })

		-- Open and close krsvim wiki index modal
		local wiki = require("plugins.krs.wiki_modal")
		wiki.setup()
		wiki.open()
		wiki.close()

		local registry = require("krs.core.keymap_registry")
		local summary = {}
		for _, c in ipairs(registry.collisions) do
			table.insert(
				summary,
				string.format(
					"%s (%s): %s (%s) <-> %s (%s)",
					c.lhs,
					c.mode,
					c.first_source,
					c.first_desc or "no desc",
					c.second_source,
					c.second_desc or "no desc"
				)
			)
		end

		expect(summary).toEqual({})
	end)
end)
