-- ============================================================================
-- KRS PLUGIN: Tailwind Class Organizer.
-- ============================================================================
-- WHAT IT DOES
--   Rewrites `class="..."` / `className="..."` into sorted, grouped rows, on save
--   (when enabled) or on demand.
--
-- THE LAYOUT IT PRODUCES -- one row per concern, each alphabetized
--   Row 1  Layout, position and size      (flex, absolute, w-*, h-*, z-*, items-*)
--          sorted display/position first, then dimensions, then the rest
--   Row 2  Everything aesthetic           (colors, typography, spacing, borders)
--   Row 3  hover: classes
--   Row 4+ One row per responsive prefix  (sm:, md:, lg:, ...) in breakpoint order
--
--   Short class lists stay on one line: see `min_classes_for_multiline`.
--
-- COMMANDS / KEYS
--   :TailwindOrganize          <leader>tw  Organize the current buffer.
--   :TailwindOrganizerToggle   <leader>tt  Turn format-on-save on and off.
--   :TailwindOrganizerStatus               Report the current state.
--   :TailwindOrganizerReload               Hot-reload this module while editing it.
--
-- CLASSIFICATION IS DATA
--   `M.settings.exact_layout` and `M.settings.layout_prefixes` decide what counts
--   as Row 1. Add utilities there; nothing else needs to change.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

--- Whether format-on-save is currently active. Toggled at runtime.
M.enabled = true

M.settings = {
	--- Reformat on `:w`.
	auto_format_on_save = true,

	--- Always break into rows, even for a single row of classes.
	force_multiline = false,

	--- Below this many classes the result stays on one line.
	min_classes_for_multiline = 9,

	--- Indentation added to each row, on top of the attribute's own indent.
	row_indent = "  ",

	--- Notification title.
	notify_title = "Tailwind Organizer",

	keys = {
		organize = nil,
		toggle = nil,
	},

	--- Responsive prefixes, in the order their rows are emitted.
	screen_order = {
		sm = 1,
		md = 2,
		lg = 3,
		xl = 4,
		["2xl"] = 5,
		["max-sm"] = 6,
		["max-md"] = 7,
		["max-lg"] = 8,
		["max-xl"] = 9,
		["max-2xl"] = 10,
		portrait = 11,
		landscape = 12,
	},

	--- Row 1 utilities matched exactly (display, position, box model).
	exact_layout = {
		"static",
		"fixed",
		"absolute",
		"relative",
		"sticky",
		"block",
		"inline-block",
		"inline",
		"flex",
		"inline-flex",
		"grid",
		"inline-grid",
		"table",
		"inline-table",
		"table-caption",
		"table-cell",
		"table-column",
		"table-column-group",
		"table-footer-group",
		"table-header-group",
		"table-row-group",
		"table-row",
		"flow-root",
		"contents",
		"hidden",
		"box-border",
		"box-content",
		"grow",
		"shrink",
	},

	--- Row 1 utilities matched by prefix (Lua patterns).
	layout_prefixes = {
		"^inset%-",
		"^inset%-x%-",
		"^inset%-y%-",
		"^top%-",
		"^right%-",
		"^bottom%-",
		"^left%-",
		"^z%-",
		"^flex%-",
		"^basis%-",
		"^grid%-",
		"^col%-",
		"^row%-",
		"^auto%-cols%-",
		"^auto%-rows%-",
		"^grid%-flow%-",
		"^items%-",
		"^justify%-",
		"^place%-items%-",
		"^place%-content%-",
		"^place%-self%-",
		"^self%-",
		"^gap%-",
		"^space%-x%-",
		"^space%-y%-",
		"^order%-",
		"^grow%-",
		"^shrink%-",
		"^w%-",
		"^min%-w%-",
		"^max%-w%-",
		"^h%-",
		"^min%-h%-",
		"^max%-h%-",
		"^size%-",
		"^overflow%-",
		"^overflow%-x%-",
		"^overflow%-y%-",
		"^float%-",
		"^clear%-",
		"^object%-",
		"^aspect%-",
	},

	--- Dimension utilities, which sort right after display/position in Row 1.
	dimension_prefixes = { "^w%-", "^min%-w%-", "^max%-w%-", "^h%-", "^min%-h%-", "^max%-h%-", "^size%-" },

	--- Attribute forms rewritten in a file. Each pattern captures, in order:
	--- position, prefix (up to and including the opener), body, closer.
	--- Covers class=, className= and :class=, plus the JSX `{\`...\`}` form.
	--- NOT class:list= (Astro): the trailing character class stops at the colon.
	attribute_patterns = {
		'()([%:%w%-]*class[%w%-]*%s*=%s*")([^"]-)(")',
		"()([%:%w%-]*class[%w%-]*%s*=%s*')([^']-)(')",
		"()([%:%w%-]*class[%w%-]*%s*=%s*{`)(.-)(`})",
	},
}

--- Fast lookup built from `M.settings.exact_layout`.
local exact_layout = {}
for _, name in ipairs(M.settings.exact_layout) do
	exact_layout[name] = true
end

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

-- ============================================================================
-- CLASSIFICATION
-- ============================================================================

--- Responsive prefix of a class, if it has one (`md:flex` -> "md").
--- @param token string Class token.
--- @return string|nil prefix
local function get_screen_prefix(token)
	local prefix = token:match("^([%w%-]+):")
	if not prefix then
		return nil
	end

	if M.settings.screen_order[prefix] or prefix:match("^max%-") or prefix:match("^min%-") then
		return prefix
	end
	return nil
end

--- True when any pattern in `patterns` matches `token`.
--- @param token string
--- @param patterns string[]
--- @return boolean
local function matches_any(token, patterns)
	for _, pattern in ipairs(patterns) do
		if token:match(pattern) then
			return true
		end
	end
	return false
end

--- True when the class belongs in Row 1 (layout, position or size).
--- @param token string
--- @return boolean
local function is_layout_position_size(token)
	return exact_layout[token] == true or matches_any(token, M.settings.layout_prefixes)
end

--- Sort weight inside Row 1: display/position (1), dimensions (2), rest (3).
--- @param token string
--- @return integer priority
local function get_layout_priority(token)
	local base = token:match(":(.*)$") or token

	if exact_layout[base] then
		return 1
	end
	if matches_any(base, M.settings.dimension_prefixes) then
		return 2
	end
	return 3
end

--- Sorts a layout row by priority, then alphabetically.
--- @param row string[]
local function sort_layout_row(row)
	table.sort(row, function(a, b)
		local prio_a, prio_b = get_layout_priority(a), get_layout_priority(b)
		if prio_a ~= prio_b then
			return prio_a < prio_b
		end
		return a < b
	end)
end

-- ============================================================================
-- ORGANIZING
-- ============================================================================

--- Sorts and groups a raw class string.
---
--- @param raw_class_str string Whitespace-separated classes.
--- @param row_indent string|nil Indent for each row in multi-line output.
--- @param base_indent string|nil Indent of the closing quote.
--- @return string organized Single line, or a multi-line block.
function M.organize_classes(raw_class_str, row_indent, base_indent)
	local tokens, seen = {}, {}
	for cls in raw_class_str:gmatch("%S+") do
		if not seen[cls] then
			seen[cls] = true
			table.insert(tokens, cls)
		end
	end
	if #tokens == 0 then
		return ""
	end

	local layout, aesthetic, hover, screens = {}, {}, {}, {}

	for _, cls in ipairs(tokens) do
		local screen_prefix = get_screen_prefix(cls)
		if cls:match("hover:") then
			table.insert(hover, cls)
		elseif screen_prefix then
			screens[screen_prefix] = screens[screen_prefix] or {}
			table.insert(screens[screen_prefix], cls)
		elseif is_layout_position_size(cls) then
			table.insert(layout, cls)
		else
			table.insert(aesthetic, cls)
		end
	end

	sort_layout_row(layout)
	table.sort(aesthetic)
	table.sort(hover)

	local screen_keys = vim.tbl_keys(screens)
	table.sort(screen_keys, function(a, b)
		local order_a = M.settings.screen_order[a] or 999
		local order_b = M.settings.screen_order[b] or 999
		if order_a ~= order_b then
			return order_a < order_b
		end
		return a < b
	end)
	for _, key in ipairs(screen_keys) do
		sort_layout_row(screens[key])
	end

	local rows = {}
	for _, row in ipairs({ layout, aesthetic, hover }) do
		if #row > 0 then
			table.insert(rows, table.concat(row, " "))
		end
	end
	for _, key in ipairs(screen_keys) do
		table.insert(rows, table.concat(screens[key], " "))
	end

	if #rows == 0 then
		return ""
	end

	local min_count = M.settings.min_classes_for_multiline or 9
	if #tokens < min_count or (#rows == 1 and not M.settings.force_multiline) then
		return table.concat(rows, " ")
	end

	row_indent = row_indent or M.settings.row_indent
	base_indent = base_indent or ""

	local lines = {}
	for _, row in ipairs(rows) do
		table.insert(lines, row_indent .. row)
	end
	return "\n" .. table.concat(lines, "\n") .. "\n" .. base_indent
end

--- Indentation of the line containing byte position `pos`.
--- @param text string Whole buffer text.
--- @param pos integer Byte position.
--- @return string indent
local function find_indent(text, pos)
	local line_start = 1
	for i = pos, 2, -1 do
		if text:sub(i, i) == "\n" then
			line_start = i + 1
			break
		end
	end
	return text:sub(line_start, pos):match("^(%s*)") or ""
end

--- Rewrites every class attribute in a document.
--- Also reports how many lines were ADDED before the cursor and before the first
--- visible line, so the caller can keep the view steady.
---
--- @param full_text string Buffer contents.
--- @param cursor_byte_offset integer|nil Byte offset of the cursor.
--- @param topline_byte_offset integer|nil Byte offset of the first visible line.
--- @return string organized
--- @return integer added_before_cursor
--- @return integer added_before_topline
function M.organize_full_text(full_text, cursor_byte_offset, topline_byte_offset)
	cursor_byte_offset = cursor_byte_offset or math.huge
	topline_byte_offset = topline_byte_offset or math.huge

	local result = full_text
	local added_before_cursor, added_before_topline = 0, 0

	--- Tracks the line-count delta of one replacement.
	local function track(pos, old_str, new_str)
		local _, old_lines = old_str:gsub("\n", "")
		local _, new_lines = new_str:gsub("\n", "")
		local diff = new_lines - old_lines
		if diff == 0 then
			return
		end
		if pos <= cursor_byte_offset then
			added_before_cursor = added_before_cursor + diff
		end
		if pos <= topline_byte_offset then
			added_before_topline = added_before_topline + diff
		end
	end

	for _, pattern in ipairs(M.settings.attribute_patterns) do
		result = result:gsub(pattern, function(pos, prefix, body, suffix)
			local base_indent = find_indent(result, pos)
			local cleaned = body:gsub("%s+", " "):match("^%s*(.-)%s*$")
			if not cleaned or cleaned == "" then
				return prefix .. suffix
			end

			local organized = M.organize_classes(cleaned, base_indent .. M.settings.row_indent, base_indent)
			local old_str = prefix .. body .. suffix
			local new_str = prefix .. organized .. suffix
			track(pos, old_str, new_str)
			return new_str
		end)
	end

	return result, added_before_cursor, added_before_topline
end

--- Organizes a buffer in place, preserving the cursor and scroll position.
--- @param bufnr integer|nil Defaults to the current buffer.
--- @return boolean changed
function M.organize_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local is_current = bufnr == vim.api.nvim_get_current_buf()

	local view
	local cursor_byte_offset, topline_byte_offset = math.huge, math.huge

	if is_current then
		view = vim.fn.winsaveview()

		--- Byte offset of the start of line `lnum` (1-based).
		local function offset_of_line(lnum)
			local offset = 0
			for i = 1, math.min(lnum, #lines) - 1 do
				offset = offset + #(lines[i] or "") + 1
			end
			return offset
		end

		topline_byte_offset = offset_of_line(view.topline or 1)
		cursor_byte_offset = offset_of_line(view.lnum or 1) + (view.col or 0)
	end

	local full_text = table.concat(lines, "\n")
	local organized, added_before_cursor, added_before_topline =
		M.organize_full_text(full_text, cursor_byte_offset, topline_byte_offset)

	if organized == full_text then
		return false
	end

	local new_lines = {}
	for line in (organized .. "\n"):gmatch("(.-)\n") do
		table.insert(new_lines, line)
	end
	if #new_lines > 0 and new_lines[#new_lines] == "" and organized:sub(-1) ~= "\n" then
		table.remove(new_lines)
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

	if view and is_current then
		-- The cursor line moved down by however many rows were inserted above it.
		view.lnum = math.max(1, math.min(#new_lines, view.lnum + added_before_cursor))
		view.topline = math.max(1, math.min(#new_lines, view.topline + added_before_topline))
		vim.fn.winrestview(view)
	end
	return true
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

--- Organizes the current buffer and reports what happened.
local function organize_current()
	if M.organize_buffer(0) then
		notify("✨ Tailwind classes organized!")
	else
		notify("Tailwind classes already organized.")
	end
end

--- Turns format-on-save on or off.
function M.toggle()
	M.enabled = not M.enabled
	notify(
		"🎨 Tailwind Organizer: "
			.. (M.enabled and "ACTIVATED (Auto-format on Save ON)" or "DEACTIVATED (Auto-format on Save OFF)"),
		M.enabled and vim.log.levels.INFO or vim.log.levels.WARN
	)
end

--- Reports whether format-on-save is active.
function M.show_status()
	notify(
		"🎨 Tailwind Organizer Status: "
			.. (M.enabled and "Active (Auto-format on Save ON)" or "Inactive (Auto-format on Save OFF)")
	)
end

--- Reloads this module from disk, for editing the rules without restarting.
function M.reload()
	package.loaded["plugins.krs.tailwind_organizer"] = nil
	require("plugins.krs.tailwind_organizer").setup()
	notify("🔄 Tailwind Organizer reloaded in-memory!")
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers commands, keymaps, the save hook, and the palette entries.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local commands = {
		TailwindOrganizerToggle = { M.toggle, "Toggle Tailwind Classes Organizer" },
		TailwindOrganize = { organize_current, "Organize Tailwind Classes in Current Buffer" },
		TailwindOrganizerStatus = { M.show_status, "Show Tailwind Organizer Status" },
		TailwindOrganizerReload = { M.reload, "Hot-reload Tailwind Organizer module" },
	}
	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, function()
				spec[1]()
			end, { desc = spec[2] })
		end
	end

	vim.keymap.set("n", M.settings.keys.organize, organize_current, { desc = "Organize Tailwind Classes" })
	vim.keymap.set("n", M.settings.keys.toggle, M.toggle, { desc = "Toggle Tailwind Organizer" })

	vim.api.nvim_create_autocmd("BufWritePre", {
		group = vim.api.nvim_create_augroup("TailwindOrganizerGroup", { clear = true }),
		pattern = "*",
		callback = function(args)
			if M.enabled and M.settings.auto_format_on_save then
				M.organize_buffer(args.buf)
			end
		end,
	})

	local ok, palette = pcall(require, "plugins.krs.command_palette")
	if ok and palette.add_command then
		palette.add_command({
			name = "🎨 Toggle Tailwind Organizer (Auto-Format on Save)",
			cmd = "TailwindOrganizerToggle",
			category = "Tailwind",
		})
		palette.add_command({
			name = "✨ Organize Tailwind Classes (Current File)",
			cmd = "TailwindOrganize",
			category = "Tailwind",
		})
		palette.add_command({
			name = "ℹ️ Tailwind Organizer Status",
			cmd = "TailwindOrganizerStatus",
			category = "Tailwind",
		})
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.TailwindOrganizer = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "krs_tailwind_organizer",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "TailwindOrganize", "TailwindOrganizerToggle", "TailwindOrganizerStatus", "TailwindOrganizerReload" },
	event = { "BufReadPost", "BufNewFile" },
	keys = {},
	config = M.setup,
}, { __index = M })
