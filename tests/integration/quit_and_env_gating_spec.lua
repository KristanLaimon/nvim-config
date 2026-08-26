-- ============================================================================
-- tests/integration/quit_and_env_gating_spec.lua
-- ============================================================================
-- Covers two commits that shipped without tests:
--   84faa51  q!/bd!/bdelete! bang routing (buffer_cleaner) + blink.cmp
--            `sources.providers.snippets.opts.search_paths` shape.
--   cdb53f3  proot Ubuntu treated as desktop (not native Termux) in
--            treesitter.lua, autopairs.lua and lsp.lua's blink.cmp opts.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

-- ----------------------------------------------------------------------------
-- q! / bd! / bdelete! bang routing
-- ----------------------------------------------------------------------------

describe("buffer_cleaner bang routing", function()
	local buffer_cleaner = require("plugins.krs.editor.buffer_cleaner")
	buffer_cleaner.setup()

	it("registers KrsQ and KrsBd as bang-aware user commands", function()
		expect(vim.fn.exists(":KrsQ") > 0).toBeTruthy()
		expect(vim.fn.exists(":KrsBd") > 0).toBeTruthy()
	end)

	it("routes :KrsQ! with force=true and :KrsQ with force=false", function()
		local received = {}
		local original = _G.Neotree_Smart_Quit
		_G.Neotree_Smart_Quit = function(force)
			table.insert(received, force)
		end

		vim.cmd("KrsQ")
		vim.cmd("KrsQ!")

		_G.Neotree_Smart_Quit = original

		expect(received).toEqual({ false, true })
	end)

	it("routes :KrsBd! with force=true and :KrsBd with force=false", function()
		local received = {}
		local original = _G.Smart_Close_Buffer
		_G.Smart_Close_Buffer = function(_, force)
			table.insert(received, force)
		end

		vim.cmd("KrsBd")
		vim.cmd("KrsBd!")

		_G.Smart_Close_Buffer = original

		expect(received).toEqual({ false, true })
	end)

	it("expands the bare `q`/`bd`/`bdelete` abbreviations to their user command, leaving a typed ! untouched", function()
		for _, abbrev in ipairs(buffer_cleaner.settings.abbreviations) do
			local listing = vim.fn.execute("cabbrev " .. abbrev.lhs)
			expect(listing).toContain(abbrev.user_cmd)
			-- The old approach baked `getcmdline() ==# 'q!'` matching into the
			-- abbrev itself, which can never fire (see buffer_cleaner.lua): the
			-- bang is typed AFTER the abbrev already expanded on the bare word.
			-- The fix removed `force` from each entry in favor of `user_cmd`,
			-- letting the typed `!` attach to the expanded command's own bang.
			expect(abbrev.force).toBeNil()
		end
	end)
end)

-- ----------------------------------------------------------------------------
-- blink.cmp snippets provider shape
-- ----------------------------------------------------------------------------

describe("blink.cmp snippets configuration", function()
	local blink_spec
	for _, spec in ipairs(require("plugins.lsp.lsp")) do
		if spec[1] == "saghen/blink.cmp" then
			blink_spec = spec
		end
	end

	it("finds the blink.cmp plugin spec", function()
		expect(blink_spec).toBeDefined()
	end)

	it("does NOT put search_paths on the top-level snippets table (invalid field)", function()
		local opts = blink_spec.opts()
		expect(opts.snippets.search_paths).toBeNil()
	end)

	it("puts search_paths under sources.providers.snippets.opts, per blink.cmp's schema", function()
		local opts = blink_spec.opts()
		local snippet_provider = opts.sources.providers.snippets
		expect(snippet_provider).toBeDefined()
		expect(type(snippet_provider.opts.search_paths)).toBe("table")
		expect(snippet_provider.opts.search_paths[1]).toContain("snippets")
	end)
end)

-- ----------------------------------------------------------------------------
-- proot Ubuntu vs. bare Termux gating
-- ----------------------------------------------------------------------------

describe("environment-based mobile gating (proot treated as desktop)", function()
	--- Swaps `krs.core.environment` for a stub returning `fixture`, runs `fn`,
	--- then restores the real module either way.
	--- @param fixture table Partial env table merged over sane defaults.
	--- @param fn fun()
	local function with_env(fixture, fn)
		local real = package.loaded["krs.core.environment"]
		package.loaded["krs.core.environment"] = {
			detect = function()
				return vim.tbl_extend("force", {
					is_tmux = false,
					is_termux = false,
					is_proot = false,
					is_ubuntu = false,
					is_wsl = false,
					is_windows = false,
					is_mac = false,
					is_linux = true,
					is_mobile = false,
					label = "stub",
				}, fixture)
			end,
		}
		local ok, err = pcall(fn)
		package.loaded["krs.core.environment"] = real
		if not ok then
			error(err, 0)
		end
	end

	local bare_termux = { is_termux = true, is_proot = false, is_mobile = true }
	local proot_ubuntu = { is_termux = true, is_proot = true, is_ubuntu = true, is_mobile = true }
	local desktop = { is_termux = false, is_proot = false, is_mobile = false }

	it("nvim-autopairs: check_ts is off on bare Termux, on for proot Ubuntu and desktop", function()
		local captured = {}
		package.loaded["nvim-autopairs"] = {
			setup = function(opts)
				table.insert(captured, opts.check_ts)
			end,
		}
		package.loaded["plugins.editor.autopairs"] = nil

		for _, fixture in ipairs({ bare_termux, proot_ubuntu, desktop }) do
			with_env(fixture, function()
				require("plugins.editor.autopairs").config()
			end)
		end

		package.loaded["nvim-autopairs"] = nil
		package.loaded["plugins.editor.autopairs"] = nil

		expect(captured).toEqual({ false, true, true })
	end)

	it("nvim-treesitter: core parsers install skipped only on bare Termux", function()
		local install_calls = 0
		package.loaded["nvim-treesitter"] = {
			setup = function() end,
			install = function()
				install_calls = install_calls + 1
			end,
		}
		package.loaded["plugins.lsp.treesitter"] = nil

		for _, fixture in ipairs({ bare_termux, proot_ubuntu, desktop }) do
			with_env(fixture, function()
				require("plugins.lsp.treesitter").config()
			end)
		end

		package.loaded["nvim-treesitter"] = nil
		package.loaded["plugins.lsp.treesitter"] = nil

		-- bare Termux skips the install; proot Ubuntu and desktop both run it.
		expect(install_calls).toBe(2)
	end)

	it("blink.cmp: fuzzy implementation is lua only when termux without proot, or a narrow terminal", function()
		local blink_spec
		for _, spec in ipairs(require("plugins.lsp.lsp")) do
			if spec[1] == "saghen/blink.cmp" then
				blink_spec = spec
			end
		end

		local results = {}
		for _, fixture in ipairs({ bare_termux, proot_ubuntu, desktop }) do
			with_env(fixture, function()
				table.insert(results, blink_spec.opts().fuzzy.implementation)
			end)
		end

		expect(results).toEqual({ "lua", "prefer_rust_with_warning", "prefer_rust_with_warning" })
	end)
end)
