-- ============================================================================
-- TESTS: KrsVim Help Menu & Runtime Cheatsheet Manager (<F1>)
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local hm = require("plugins.krs.ui.help_modal")

describe("plugins.krs.ui.help_modal", function()
	it("exposes all required topic categories including Neo-tree, Environments, Git-Center, InTab, Terminal", function()
		local topic_ids = {}
		for _, topic in ipairs(hm.topic_catalog) do
			topic_ids[topic.id] = topic.title
		end

		expect(topic_ids["environments"]).toBe("Environments")
		expect(topic_ids["git_center"]).toBe("Git-Center")
		expect(topic_ids["neotree"]).toBe("Neo-tree")
		expect(topic_ids["intab"]).toBe("InTab")
		expect(topic_ids["terminal"]).toBe("Terminal")
		expect(topic_ids["tasks"]).toBe("Task Runner")
		expect(topic_ids["launch"]).toBe("Launch & Debug")
		expect(topic_ids["workspaces"]).toBe("Workspaces")
	end)

	it("formats key chord tokens into human-friendly strings", function()
		expect(hm.format_key("<C-S-e>")).toBe("Ctrl+Shift+e")
		expect(hm.format_key("<C-S-E>")).toBe("Ctrl+Shift+E")
		expect(hm.format_key("<C-;>")).toBe("Ctrl+;")
		expect(hm.format_key("<A-1>")).toBe("Alt+1")
		expect(hm.format_key("<F1>")).toBe("F1")
		expect(hm.format_key(" ee")).toBe("Space + e + e")
		expect(hm.format_key("<leader>ee")).toBe("Space + e + e")
	end)

	it("collects runtime keymaps dynamically while filtering out unwanted leader shortcuts", function()
		local maps = hm.collect_runtime_keymaps()
		expect(type(maps)).toBe("table")
		expect(#maps > 0).toBe(true)

		-- Verify no random <leader>### keymaps leak through (except <leader>ee)
		for _, km in ipairs(maps) do
			local lhs = km.lhs
			local is_leader = lhs:find("^ ") or lhs:lower():find("^<leader>") or lhs:lower():find("^<space>")
			if is_leader then
				local is_allowed = (lhs == " ee" or lhs:lower() == "<leader>ee")
				expect(is_allowed).toBe(true)
			end
		end
	end)

	it("builds topic cheatsheet dynamically from runtime data without hardcoded strings", function()
		local all_maps = hm.collect_runtime_keymaps()
		local env_topic = nil
		for _, top in ipairs(hm.topic_catalog) do
			if top.id == "environments" then
				env_topic = top
				break
			end
		end

		expect(env_topic ~= nil).toBe(true)
		local items = hm.build_topic_cheatsheet(env_topic, all_maps)
		expect(type(items)).toBe("table")
		expect(#items > 0).toBe(true)

		local has_slots = false
		local has_menu = false
		for _, item in ipairs(items) do
			if item.name:find("Environment Slots") then
				has_slots = true
				expect(type(item.chord)).toBe("string")
			elseif item.name:find("Environments CRUD Menu") then
				has_menu = true
				expect(type(item.chord)).toBe("string")
			end
		end

		expect(has_slots).toBe(true)
		expect(has_menu).toBe(true)
	end)

	it("opens dual floating panels and toggles closed cleanly", function()
		expect(hm.is_open()).toBe(false)
		hm.open()
		expect(hm.is_open()).toBe(true)

		-- Calling open again or close should dismiss
		hm.open()
		expect(hm.is_open()).toBe(false)
	end)

	it("registers user commands upon setup", function()
		hm.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["KrsHelp"] ~= nil).toBe(true)
		expect(cmds["Cheatsheet"] ~= nil).toBe(true)
		expect(cmds["HelpMenu"] ~= nil).toBe(true)
	end)
end)
