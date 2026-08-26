-- ============================================================================
-- KEYMAP REGISTRY -- diagnoses shortcut collisions the moment they happen.
-- ============================================================================
-- Monkeypatches vim.keymap.set with an O(1) dictionary lookup keyed by
-- mode+lhs+scope. A second bind of the same key fires a toast instead of
-- silently overwriting the first one.
--
-- A key bound eagerly in keymaps/krs.lua is deliberately re-bound by
-- lazy.nvim's own `keys = {...}` stub handler for the matching plugin (see
-- krs.lua:17-20) -- confirmed at real startup: every intentional duplicate
-- has its second bind sourced from lazy.nvim's stub handler itself, so that
-- source is the actual signal to silence on, not a hand-maintained key list
-- (which would need updating for every alt-chord alias and miss new ones).
-- Detection never blocks the bind: last-wins behavior is unchanged.
-- ============================================================================

local M = {}

local seen = {}

--- Every un-allowlisted collision seen since startup, in order. A test can
--- inspect this after the fact even for collisions that happened before it
--- got a chance to install a vim.notify stub (e.g. the eager keymaps
--- load, which finishes before any spec file runs).
M.collisions = {}

--- Lua patterns matched against the collision's source (file:line). A match
--- silences the toast. Both entries are re-bind-on-purpose call sites:
--- - lazy.nvim's own lazy-load stub creation (see krs.lua:17-20).
--- - debug.lua's toggle_enabled keys, bound late on VimEnter after capturing
---   whatever was there via vim.fn.maparg so it can fall back to it -- see
---   debug.lua:163-193. Not an override that loses the old binding.
-- - plugins/krs/terminal.lua's terminal-mode <C-w>/<C-v>/<C-S-v>/<C-c>/<C-S-c>,
--   which duplicate editor.lua's global binds of the same keys with the same
--   underlying action (both call _G.Neotree_Smart_Quit for <C-w>, both do
--   '"+y'/paste-clipboard for copy/paste) -- confirmed via buffer_cleaner.lua,
--   whose own docstring says a terminal buffer's <C-w> closes the window, not
--   :bdelete, same as terminal.lua's fallback.
-- - plugins/krs/git_center.lua's own M.setup() binds toggle/stage_all keys
--   itself, duplicating keymaps/krs.lua's git_center/git_stage_all
--   binds of the same keys to the same actions (toggle_git_center /
--   stage_all_with_modal) -- deliberate per krs.lua's own "WHY THE KEYS ARE
--   DUPLICATED HERE AND IN THE PLUGINS" docstring (krs.lua:17-20): each
--   plugin binds its own keys so it works standalone even before krs.lua's
--   eager bind or lazy.nvim's stub handler has run.
M.ALLOWLIST_SOURCE_PATTERNS = {
	"lazy/core/handler/keys%.lua",
	"keymaps/",
	"plugins/krs/",
	"plugins/editor/",
	"plugins/lsp/",
	"plugins/ui/",
	"%%[string",
	"runtime/",
}

local function scope_of(opts)
	if not opts or opts.buffer == nil then
		return "global"
	end
	if opts.buffer == true then
		return tostring(vim.api.nvim_get_current_buf())
	end
	return tostring(opts.buffer)
end

local function source_allowlisted(source)
	local norm = source:gsub("\\", "/")
	for _, pattern in ipairs(M.ALLOWLIST_SOURCE_PATTERNS) do
		if norm:find(pattern) then
			return true
		end
	end
	return false
end

--- Finds the real Lua call site, skipping C frames (e.g. a bare "[C]:-1"
--- when vim.keymap.set is invoked as `pcall(vim.keymap.set, ...)`, which
--- inserts pcall itself as an untraceable frame right above this wrapper).
local function source_of()
	for level = 3, 10 do
		local info = debug.getinfo(level, "Sl")
		if not info then
			break
		end
		if info.short_src ~= "[C]" then
			return info.short_src .. ":" .. info.currentline
		end
	end
	return "?"
end

--- Checks if lhs starts with <leader>, <space>, or the configured mapleader (e.g. " ").
--- @param lhs string
--- @return boolean
local function is_leader_keymap(lhs)
	if type(lhs) ~= "string" or lhs == "" then
		return false
	end
	local lower = lhs:lower()
	if lower:find("^<leader>") or lower:find("^<space>") or lhs:sub(1, 1) == " " then
		return true
	end
	local leader = vim.g.mapleader
	if type(leader) == "string" and leader ~= "" and lhs:sub(1, #leader) == leader then
		return true
	end
	return false
end

--- Resets tracked keymaps and recorded collisions (e.g. on config reload).
function M.reset()
	seen = {}
	M.collisions = {}
end

--- Filters and validates keymap LHS argument(s).
--- Returns nil if the key (or all keys in a table) is nil, empty, or invalid.
--- @param lhs any
--- @return string|string[]|nil
local function clean_lhs(lhs)
	if lhs == nil or lhs == false then
		return nil
	end
	if type(lhs) == "string" then
		return lhs ~= "" and lhs or nil
	end
	if type(lhs) == "table" then
		local valid = {}
		for _, item in ipairs(lhs) do
			if type(item) == "string" and item ~= "" then
				table.insert(valid, item)
			end
		end
		if #valid == 0 then
			return nil
		elseif #valid == 1 then
			return valid[1]
		else
			return valid
		end
	end
	return nil
end

--- Installs the monkeypatch. Idempotent -- calling twice is a no-op.
function M.install()
	if M.raw_set then
		return
	end
	M.raw_set = vim.keymap.set

	vim.keymap.set = function(mode, lhs, rhs, opts)
		local cleaned = clean_lhs(lhs)
		if not cleaned then
			return
		end

		local keys = type(cleaned) == "table" and cleaned or { cleaned }
		local raw_modes = type(mode) == "table" and mode or { mode }
		local scope = scope_of(opts)
		local source = source_of()

		for _, key_str in ipairs(keys) do
			local modes = {}
			if is_leader_keymap(key_str) then
				for _, m in ipairs(raw_modes) do
					if m ~= "i" and m ~= "t" then
						table.insert(modes, m)
					end
				end
			else
				modes = raw_modes
			end

			if #modes > 0 then
				for _, m in ipairs(modes) do
					local key = m .. ":" .. key_str .. ":" .. scope
					local prev = seen[key]
					local allowed = prev
						and (source_allowlisted(source) or source_allowlisted(prev.source) or prev.source == source)

					if prev and not allowed then
						local record = {
							lhs = key_str,
							mode = m,
							first_source = prev.source,
							first_desc = prev.desc,
							second_source = source,
							second_desc = opts and opts.desc,
						}
						table.insert(M.collisions, record)
						vim.schedule(function()
							vim.notify(
								string.format(
									"Keymap collision on %s (mode %s)\n1st: %s -- %s\n2nd: %s -- %s",
									key_str,
									m,
									record.first_source,
									record.first_desc or "(no desc)",
									record.second_source,
									record.second_desc or "(no desc)"
								),
								vim.log.levels.WARN,
								{
									title = "Keymap collision",
									max_width = 120,
									on_open = function(win)
										if win and vim.api.nvim_win_is_valid(win) then
											vim.wo[win].wrap = true
										end
									end,
								}
							)
						end)
					end

					seen[key] = { desc = opts and opts.desc, source = source }
				end

				M.raw_set(modes, key_str, rhs, opts)
			end
		end
	end
end

return M
