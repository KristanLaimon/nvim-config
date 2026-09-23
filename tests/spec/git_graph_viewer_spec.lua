-- ============================================================================
-- tests/spec/git_graph_viewer_spec.lua -- GitKraken Commit Graph Viewer Tests
-- ============================================================================

local t = require("krs.lib.krsnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local graph_viewer = require("plugins.krs.git.git_center.graph_viewer")
local config = require("plugins.krs.git.git_center.config")
local git_center = require("plugins.krs.git.git_center")

describe("plugins.krs.git.git_center.graph_viewer", function()
	beforeEach(function()
		if git_center.is_open() then
			git_center.close_git_center()
		end
		if config.graph_win and vim.api.nvim_win_is_valid(config.graph_win) then
			pcall(vim.api.nvim_win_close, config.graph_win, true)
		end
		if config.graph_right_win and vim.api.nvim_win_is_valid(config.graph_right_win) then
			pcall(vim.api.nvim_win_close, config.graph_right_win, true)
		end
	end)

	afterEach(function()
		if git_center.is_open() then
			git_center.close_git_center()
		end
		if config.graph_win and vim.api.nvim_win_is_valid(config.graph_win) then
			pcall(vim.api.nvim_win_close, config.graph_win, true)
		end
		if config.graph_right_win and vim.api.nvim_win_is_valid(config.graph_right_win) then
			pcall(vim.api.nvim_win_close, config.graph_right_win, true)
		end
	end)

	it("exports public API methods", function()
		expect(type(graph_viewer.open)).toBe("function")
		expect(type(graph_viewer.fetch_commits)).toBe("function")
		expect(type(graph_viewer.beautify_graph_prefix)).toBe("function")
		expect(type(graph_viewer.parse_raw_graph_line)).toBe("function")
		expect(type(graph_viewer.format_commit_line)).toBe("function")
		expect(type(graph_viewer.setup_highlights)).toBe("function")
		expect(type(git_center.open_graph_viewer)).toBe("function")
	end)

	it("beautifies raw ASCII git graph characters into GitKraken Unicode glyphs", function()
		local raw = "* | / \\ _ ."
		local beautified = graph_viewer.beautify_graph_prefix(raw)
		expect(beautified).toBe("● │ ╱ ╲ ─ ⬝")
	end)

	it("parses raw git graph commit lines with delimiter", function()
		local raw = "* 87a6e94\x1f (HEAD -> main, origin/main, tag: v1.0.0)\x1fKristanLaimon\x1f25 hours ago\x1ffeat: Neo-tree mover"
		local parsed = graph_viewer.parse_raw_graph_line(raw)

		expect(parsed.is_commit).toBeTruthy()
		expect(parsed.hash).toBe("87a6e94")
		expect(parsed.author).toBe("KristanLaimon")
		expect(parsed.date).toBe("25 hours ago")
		expect(parsed.subject).toBe("feat: Neo-tree mover")
		expect(parsed.refs).toContain("HEAD -> main")
	end)

	it("parses pure graph connector lines without commits", function()
		local raw = "|/| "
		local parsed = graph_viewer.parse_raw_graph_line(raw)

		expect(parsed.is_commit).toBeFalsy()
		expect(parsed.hash).toBeNil()
		expect(parsed.graph_raw).toBe("|/| ")
	end)

	it("formats commit lines with GitKraken lane highlights and badges", function()
		graph_viewer.setup_highlights()
		local parsed = {
			is_commit = true,
			graph_raw = "*",
			hash = "87a6e94",
			refs = " (HEAD -> main, origin/main)",
			author = "KristanLaimon",
			date = "25 hours ago",
			subject = "feat: Neo-tree mover",
		}

		local line_text, spans = graph_viewer.format_commit_line(parsed)

		expect(line_text).toContain("●")
		expect(line_text).toContain("87a6e94")
		expect(line_text).toContain("🌿 main")
		expect(line_text).toContain("☁️ main")
		expect(line_text).toContain("feat: Neo-tree mover")
		expect(line_text).toContain("👤 KristanLaimon")
		expect(line_text).toContain("🕒 25 hours ago")

		-- Spans should contain lane color, SHA hl, and ref badge hl
		expect(#spans).toBeGreaterThan(3)
		local has_lane_hl = false
		local has_sha_hl = false
		local has_head_hl = false
		for _, s in ipairs(spans) do
			if s.hl_group == "KRSGitKrakenLane1" then
				has_lane_hl = true
			elseif s.hl_group == "KRSGitKrakenSha" then
				has_sha_hl = true
			elseif s.hl_group == "KRSGitKrakenBadgeHead" then
				has_head_hl = true
			end
		end
		expect(has_lane_hl).toBeTruthy()
		expect(has_sha_hl).toBeTruthy()
		expect(has_head_hl).toBeTruthy()
	end)

	it("fetches commits for active repository in branch and all modes", function()
		local cwd = vim.fn.getcwd()
		local branch_res = graph_viewer.fetch_commits(5, cwd, "branch")
		expect(branch_res).toBeDefined()
		expect(branch_res.total_commits).toBeGreaterThan(0)
		expect(#branch_res.lines).toBeGreaterThan(0)

		local all_res = graph_viewer.fetch_commits(5, cwd, "all")
		expect(all_res).toBeDefined()
		expect(all_res.total_commits).toBeGreaterThan(0)
		expect(#all_res.lines).toBeGreaterThan(0)
	end)

	it("registers :GitGraph and :GitCenterGraph user commands", function()
		git_center.setup()
		local commands = vim.api.nvim_get_commands({})
		expect(commands.GitGraph).toBeDefined()
		expect(commands.GitCenterGraph).toBeDefined()
	end)

	it("opens GitKraken Graph Viewer modal dual panes cleanly", function()
		graph_viewer.open()

		expect(config.graph_win).toBeDefined()
		expect(config.graph_buf).toBeDefined()
		expect(config.graph_right_win).toBeDefined()
		expect(config.graph_right_buf).toBeDefined()

		expect(vim.api.nvim_win_is_valid(config.graph_win)).toBeTruthy()
		expect(vim.api.nvim_win_is_valid(config.graph_right_win)).toBeTruthy()

		-- Verify title contains GitKraken Graph and Mode
		local win_cfg = vim.api.nvim_win_get_config(config.graph_win)
		local title_str = type(win_cfg.title) == "string" and win_cfg.title
			or (type(win_cfg.title) == "table" and win_cfg.title[1] and win_cfg.title[1][1] or "")
		expect(title_str).toContain("GitKraken Graph")

		-- Buffer should be unmodifiable nofile
		expect(vim.bo[config.graph_buf].buftype).toBe("nofile")
		expect(vim.bo[config.graph_buf].modifiable).toBeFalsy()

		-- Close using q
		pcall(vim.api.nvim_win_close, config.graph_win, true)
		pcall(vim.api.nvim_win_close, config.graph_right_win, true)
	end)
end)
