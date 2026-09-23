-- ============================================================================
-- tests/spec/git_conflicts_spec.lua -- Git Conflict Resolver tests.
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local conflicts = require("krs.git.conflicts")
local resolver = require("plugins.krs.git.conflict_resolver")

describe("git conflicts parse_markers", function()
	it("parses standard 2-way conflict markers", function()
		local lines = {
			"local a = 1",
			"<<<<<<< HEAD",
			"local b = 'ours'",
			"=======",
			"local b = 'theirs'",
			">>>>>>> feature",
			"return a",
		}

		local parsed = conflicts.parse_markers(lines)
		expect(#parsed).toBe(1)
		expect(parsed[1].start_line).toBe(2)
		expect(parsed[1].sep_line).toBe(4)
		expect(parsed[1].end_line).toBe(6)
		expect(parsed[1].current_label).toBe("HEAD")
		expect(parsed[1].incoming_label).toBe("feature")
		expect(parsed[1].current_lines).toEqual({ "local b = 'ours'" })
		expect(parsed[1].incoming_lines).toEqual({ "local b = 'theirs'" })
	end)

	it("parses 3-way diff3 conflict markers with base", function()
		local lines = {
			"header",
			"<<<<<<< HEAD",
			"my changes",
			"||||||| base",
			"original code",
			"=======",
			"incoming changes",
			">>>>>>> incoming",
			"footer",
		}

		local parsed = conflicts.parse_markers(lines)
		expect(#parsed).toBe(1)
		expect(parsed[1].start_line).toBe(2)
		expect(parsed[1].base_sep_line).toBe(4)
		expect(parsed[1].sep_line).toBe(6)
		expect(parsed[1].end_line).toBe(8)
		expect(parsed[1].current_lines).toEqual({ "my changes" })
		expect(parsed[1].base_lines).toEqual({ "original code" })
		expect(parsed[1].incoming_lines).toEqual({ "incoming changes" })
	end)

	it("returns empty list when no conflict markers exist", function()
		local lines = { "local x = 10", "print(x)" }
		local parsed = conflicts.parse_markers(lines)
		expect(#parsed).toBe(0)
	end)
end)

describe("git conflicts extract_clean_versions", function()
	it("extracts current and incoming versions cleanly", function()
		local lines = {
			"line 1",
			"<<<<<<< HEAD",
			"ours A",
			"ours B",
			"=======",
			"theirs X",
			">>>>>>> branch",
			"line 2",
		}

		local current, incoming = conflicts.extract_clean_versions(lines)
		expect(current).toEqual({ "line 1", "ours A", "ours B", "line 2" })
		expect(incoming).toEqual({ "line 1", "theirs X", "line 2" })
	end)
end)

describe("git conflicts resolve_conflict_in_lines", function()
	local lines = {
		"pre",
		"<<<<<<< HEAD",
		"val = 1",
		"=======",
		"val = 2",
		">>>>>>> branch",
		"post",
	}

	it("resolves to current / ours", function()
		local parsed = conflicts.parse_markers(lines)
		local resolved = conflicts.resolve_conflict_in_lines(lines, parsed[1], "current")
		expect(resolved).toEqual({ "pre", "val = 1", "post" })
	end)

	it("resolves to incoming / theirs", function()
		local parsed = conflicts.parse_markers(lines)
		local resolved = conflicts.resolve_conflict_in_lines(lines, parsed[1], "incoming")
		expect(resolved).toEqual({ "pre", "val = 2", "post" })
	end)

	it("resolves to both (current first)", function()
		local parsed = conflicts.parse_markers(lines)
		local resolved = conflicts.resolve_conflict_in_lines(lines, parsed[1], "both_current_first")
		expect(resolved).toEqual({ "pre", "val = 1", "val = 2", "post" })
	end)

	it("resolves to both (incoming first)", function()
		local parsed = conflicts.parse_markers(lines)
		local resolved = conflicts.resolve_conflict_in_lines(lines, parsed[1], "both_incoming_first")
		expect(resolved).toEqual({ "pre", "val = 2", "val = 1", "post" })
	end)
end)

describe("plugins.krs.git.conflict_resolver", function()
	it("exports public API methods and settings", function()
		expect(type(resolver.open)).toBe("function")
		expect(type(resolver.close)).toBe("function")
		expect(type(resolver.is_open)).toBe("function")
		expect(type(resolver.next_conflict)).toBe("function")
		expect(type(resolver.prev_conflict)).toBe("function")
		expect(type(resolver.accept_current)).toBe("function")
		expect(type(resolver.accept_incoming)).toBe("function")
		expect(type(resolver.accept_both)).toBe("function")
		expect(type(resolver.undo)).toBe("function")
		expect(type(resolver.reset_to_initial)).toBe("function")
		expect(type(resolver.get_sidebar_width)).toBe("function")
		expect(type(resolver.stage_current_file)).toBe("function")
		expect(resolver.settings.sidebar_width).toBe(30)
		expect(type(resolver.focus_current)).toBe("function")
		expect(type(resolver.focus_incoming)).toBe("function")
		expect(type(resolver.focus_up)).toBe("function")
		expect(type(resolver.focus_result)).toBe("function")
		expect(type(resolver.focus_sidebar)).toBe("function")
		expect(type(resolver.cycle_next_panel)).toBe("function")
		expect(type(resolver.cycle_prev_panel)).toBe("function")
	end)

	it("registers user commands on setup", function()
		resolver.setup()
		local commands = vim.api.nvim_get_commands({})
		expect(commands["GitConflictResolve"]).toBeDefined()
		expect(commands["GitConflictClose"]).toBeDefined()
		expect(commands["GitConflictNext"]).toBeDefined()
		expect(commands["GitConflictPrev"]).toBeDefined()
		expect(commands["GitConflictAcceptCurrent"]).toBeDefined()
		expect(commands["GitConflictAcceptIncoming"]).toBeDefined()
		expect(commands["GitConflictAcceptBoth"]).toBeDefined()
		expect(commands["GitConflictStage"]).toBeDefined()
		expect(commands["GitConflictUndo"]).toBeDefined()
		expect(commands["GitConflictReset"]).toBeDefined()
	end)

	it("validates repository and prevents opening when no merge conflicts exist", function()
		local opened = resolver.open(nil, vim.fn.getcwd())
		expect(opened).toBe(false)
		expect(resolver.is_open()).toBe(false)
	end)

	it("updates sidebar conflict counter from (2) to (1) to (0)", function()
		resolver.state.files = {
			{ file = "src/index.ts", full_path = "/fake/src/index.ts", conflict_count = 2, is_staged = false },
			{ file = "src/utils.ts", full_path = "/fake/src/utils.ts", conflict_count = 0, is_staged = false },
		}
		resolver.state.active_idx = 1
		local sbuf = vim.api.nvim_create_buf(false, true)
		resolver.state.sidebar_buf = sbuf

		resolver.render_sidebar()
		local lines = vim.api.nvim_buf_get_lines(sbuf, 0, -1, false)
		expect(lines[3]:find("src/index.ts %(2%)") ~= nil).toBe(true)
		expect(lines[4]:find("src/utils.ts %(0%)") ~= nil).toBe(true)

		-- 1 conflict resolved
		resolver.state.files[1].conflict_count = 1
		resolver.render_sidebar()
		lines = vim.api.nvim_buf_get_lines(sbuf, 0, -1, false)
		expect(lines[3]:find("src/index.ts %(1%)") ~= nil).toBe(true)

		-- All conflicts resolved
		resolver.state.files[1].conflict_count = 0
		resolver.render_sidebar()
		lines = vim.api.nvim_buf_get_lines(sbuf, 0, -1, false)
		expect(lines[3]:find("src/index.ts %(0%)") ~= nil).toBe(true)

		pcall(vim.api.nvim_buf_delete, sbuf, { force = true })
		resolver.state.sidebar_buf = nil
		resolver.state.files = {}
	end)
end)

describe("git conflicts build_resolved_lines", function()
	local lines = {
		"header",
		"<<<<<<< HEAD",
		"mine",
		"=======",
		"theirs",
		">>>>>>> branch",
		"footer",
	}

	it("builds clean result defaulting to current", function()
		local clean, spans = conflicts.build_resolved_lines(lines, nil, "current")
		expect(clean).toEqual({ "header", "mine", "footer" })
		expect(#spans).toBe(1)
		expect(spans[1].start_line).toBe(2)
		expect(spans[1].end_line).toBe(2)
		expect(spans[1].choice).toBe("current")
	end)

	it("builds clean result defaulting to incoming", function()
		local clean, spans = conflicts.build_resolved_lines(lines, nil, "incoming")
		expect(clean).toEqual({ "header", "theirs", "footer" })
		expect(#spans).toBe(1)
		expect(spans[1].choice).toBe("incoming")
	end)

	it("returns line spans for Ours and Theirs in extract_clean_versions", function()
		local _, _, _, cur_spans, inc_spans = conflicts.extract_clean_versions(lines)
		expect(#cur_spans).toBe(1)
		expect(cur_spans[1].start_line).toBe(2)
		expect(cur_spans[1].end_line).toBe(2)
		expect(#inc_spans).toBe(1)
		expect(inc_spans[1].start_line).toBe(2)
		expect(inc_spans[1].end_line).toBe(2)
	end)
end)

describe("git conflicts resolver undo system", function()
	it("undoes resolutions step-by-step back to original merge state", function()
		local rbuf = vim.api.nvim_create_buf(false, true)
		resolver.state.result_buf = rbuf
		resolver.state.active_idx = 1
		resolver.state.files = {
			{ file = "src/app.ts", conflict_count = 2, is_staged = false },
		}
		resolver.state.history = {
			[1] = {
				stack = {},
				initial_lines = { "start", "conflict 1", "mid", "conflict 2", "end" },
				initial_spans = {
					{ id = 1, start_line = 2, end_line = 2, resolved = false },
					{ id = 2, start_line = 4, end_line = 4, resolved = false },
				},
				initial_count = 2,
			},
		}
		resolver.state.spans = vim.deepcopy(resolver.state.history[1].initial_spans)
		vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, resolver.state.history[1].initial_lines)

		-- Step 1: Simulate resolution of conflict #1
		local snapshot1 = {
			lines = vim.api.nvim_buf_get_lines(rbuf, 0, -1, false),
			spans = vim.deepcopy(resolver.state.spans),
			conflict_count = 2,
		}
		table.insert(resolver.state.history[1].stack, snapshot1)
		vim.api.nvim_buf_set_lines(rbuf, 1, 2, false, { "ours 1" })
		resolver.state.spans[1].resolved = true
		resolver.state.files[1].conflict_count = 1

		-- Step 2: Simulate resolution of conflict #2
		local snapshot2 = {
			lines = vim.api.nvim_buf_get_lines(rbuf, 0, -1, false),
			spans = vim.deepcopy(resolver.state.spans),
			conflict_count = 1,
		}
		table.insert(resolver.state.history[1].stack, snapshot2)
		vim.api.nvim_buf_set_lines(rbuf, 3, 4, false, { "theirs 2" })
		resolver.state.spans[2].resolved = true
		resolver.state.files[1].conflict_count = 0

		expect(#resolver.state.history[1].stack).toBe(2)
		expect(resolver.state.files[1].conflict_count).toBe(0)

		-- Undo 1 step: back to conflict #2 unresolved
		local ok1 = resolver.undo()
		expect(ok1).toBe(true)
		expect(resolver.state.files[1].conflict_count).toBe(1)
		expect(resolver.state.spans[2].resolved).toBe(false)
		expect(resolver.state.spans[1].resolved).toBe(true)

		-- Undo 2nd step: back to initial merge state
		local ok2 = resolver.undo()
		expect(ok2).toBe(true)
		expect(resolver.state.files[1].conflict_count).toBe(2)
		expect(resolver.state.spans[1].resolved).toBe(false)
		expect(resolver.state.spans[2].resolved).toBe(false)
		local current_lines = vim.api.nvim_buf_get_lines(rbuf, 0, -1, false)
		expect(current_lines).toEqual(resolver.state.history[1].initial_lines)

		-- 3rd undo: already at beginning
		local ok3 = resolver.undo()
		expect(ok3).toBe(false)

		pcall(vim.api.nvim_buf_delete, rbuf, { force = true })
		resolver.state.result_buf = nil
		resolver.state.files = {}
		resolver.state.history = {}
		resolver.state.spans = {}
	end)
end)

describe("git conflicts resolver top panel memory", function()
	it("remembers whether user came from top-left (Ours) or top-right (Theirs)", function()
		local cur_win = vim.api.nvim_get_current_win()
		local inc_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			split = "right",
		})
		local res_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			split = "below",
		})

		resolver.state.current_win = cur_win
		resolver.state.incoming_win = inc_win
		resolver.state.result_win = res_win

		-- Simulate starting at top-right (Incoming)
		resolver.focus_incoming()
		expect(resolver.state.last_top_win).toBe(inc_win)
		expect(vim.api.nvim_get_current_win()).toBe(inc_win)

		-- Move down to Result
		resolver.focus_result()
		expect(vim.api.nvim_get_current_win()).toBe(res_win)
		-- last_top_win should still remember inc_win
		expect(resolver.state.last_top_win).toBe(inc_win)

		-- Go UP: should return to top-right (Incoming)
		resolver.focus_up()
		expect(vim.api.nvim_get_current_win()).toBe(inc_win)

		-- Now switch to top-left (Current)
		resolver.focus_current()
		expect(resolver.state.last_top_win).toBe(cur_win)
		expect(vim.api.nvim_get_current_win()).toBe(cur_win)

		-- Move down to Result
		resolver.focus_result()
		expect(vim.api.nvim_get_current_win()).toBe(res_win)
		expect(resolver.state.last_top_win).toBe(cur_win)

		-- Go UP: should return to top-left (Current)
		resolver.focus_up()
		expect(vim.api.nvim_get_current_win()).toBe(cur_win)

		-- Clean up windows
		pcall(vim.api.nvim_win_close, inc_win, true)
		pcall(vim.api.nvim_win_close, res_win, true)
		resolver.state.current_win = nil
		resolver.state.incoming_win = nil
		resolver.state.result_win = nil
		resolver.state.last_top_win = nil
	end)
end)

describe("git conflicts resolver edge cases and buffer preservation", function()
	it("does not hijack regular characters or Esc in insert/normal mode in result buffer", function()
		local buf = vim.api.nvim_create_buf(false, true)
		resolver.attach_result_keymaps(buf)

		local keymaps = vim.api.nvim_buf_get_keymap(buf, "i")
		local insert_keys = {}
		for _, km in ipairs(keymaps) do
			insert_keys[km.lhs] = true
		end

		-- Plain characters like 1, 2, s, u MUST NOT be mapped in insert mode
		expect(insert_keys["1"]).toBeNil()
		expect(insert_keys["2"]).toBeNil()
		expect(insert_keys["s"]).toBeNil()
		expect(insert_keys["u"]).toBeNil()
		expect(insert_keys["co"]).toBeNil()

		-- Ctrl chords SHOULD be mapped in insert mode
		expect(insert_keys["<C-1>"]).toBe(true)
		expect(insert_keys["<C-2>"]).toBe(true)
		expect(insert_keys["<C-S>"]).toBe(true)

		local n_keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
		local normal_keys = {}
		for _, km in ipairs(n_keymaps) do
			normal_keys[km.lhs] = true
		end
		-- Normal mode: no plain 's', 'u', '1' or '<Esc>' to preserve standard vim editing
		expect(normal_keys["s"]).toBeNil()
		expect(normal_keys["u"]).toBeNil()
		expect(normal_keys["1"]).toBeNil()
		expect(normal_keys["<Esc>"]).toBeNil()
		expect(normal_keys["<C-Q>"]).toBe(true)

		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)

	it("preserves pre-existing buffers and unlists temporary buffers on close", function()
		local pre_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(pre_buf, "/fake/project/existing.lua")
		vim.bo[pre_buf].buflisted = true

		local temp_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(temp_buf, "/fake/project/temp.lua")
		vim.bo[temp_buf].buflisted = true

		resolver.state.is_open = true
		resolver.state.pre_open_bufs = {
			[pre_buf] = { name = "/fake/project/existing.lua", modified = false },
		}
		resolver.state.attached_bufs = { pre_buf, temp_buf }
		resolver.state.files = {
			{ file = "existing.lua", full_path = "/fake/project/existing.lua", conflict_count = 0, is_staged = true },
			{ file = "temp.lua", full_path = "/fake/project/temp.lua", conflict_count = 0, is_staged = false },
		}

		resolver.close()

		-- pre_buf should remain listed
		expect(vim.bo[pre_buf].buflisted).toBe(true)
		-- temp_buf should be unlisted so it does not clutter user tabs
		expect(vim.bo[temp_buf].buflisted).toBe(false)

		pcall(vim.api.nvim_buf_delete, pre_buf, { force = true })
		pcall(vim.api.nvim_buf_delete, temp_buf, { force = true })
	end)

	it("restores pinned tabs on close without losing pin status", function()
		local pinned_tabs = require("plugins.krs.ui.pinned_tabs")
		local fake_pins = { "init.lua", "lua/vim_options.lua" }

		resolver.state.is_open = true
		resolver.state.pre_pinned_files = fake_pins

		resolver.close()

		local loaded = pinned_tabs.load_pins()
		expect(loaded).toEqual(fake_pins)

		-- Clean up pins
		pinned_tabs.save_pins({})
	end)
end)
