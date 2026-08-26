-- ============================================================================
-- krs.core.ui -- Floating window and scratch buffer factory.
-- ============================================================================
-- WHY THIS EXISTS
--   Every KRS modal repeated the same 15 lines: create a scratch buffer, set
--   `buftype`/`bufhidden`, compute a centered row/col, open a rounded float, then
--   map `q`/`<Esc>` to close. Centering arithmetic was copy-pasted with slightly
--   different clamping, so a small terminal broke some modals and not others.
--
-- DESIGN
--   `float()` returns `buf, win` and nothing else -- callers keep full control of
--   content, highlights and extra mappings. This module owns geometry and the
--   scratch-buffer boilerplate; it deliberately owns no application state.
--
-- USAGE
--   local ui = require("krs.core.ui")
--   local buf, win = ui.float({ lines = lines, title = " Tasks ", width = 0.6 })
--   ui.close_on_keys(buf, win)
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration -- defaults for every KRS float
-- ---------------------------------------------------------------------------

--- Default window border style. Any `nvim_open_win` border value works.
M.border = "rounded"

--- Keys that dismiss a float when `close_on_keys` is used.
M.close_keys = { "q", "<Esc>" }

--- Minimum row/col so a float never lands off-screen on small terminals.
M.min_offset = 1

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

--- Resolves a size given either an absolute cell count (>= 1) or a fraction of
--- the editor (0 < n < 1).
---
--- @param value number Absolute cells or fraction of `total`.
--- @param total number Editor width or height in cells.
--- @return integer size Size in cells, at least 1.
function M.resolve_size(value, total)
	if value > 0 and value < 1 then
		return math.max(math.floor(total * value), 1)
	end
	return math.max(math.floor(value), 1)
end

--- Computes centered `row`/`col` for a float of the given size.
---
--- @param width integer Float width in cells.
--- @param height integer Float height in cells.
--- @return integer row
--- @return integer col
function M.center(width, height)
	local row = math.max(math.floor(((vim.o.lines or 24) - height) / 2), M.min_offset)
	local col = math.max(math.floor(((vim.o.columns or 80) - width) / 2), M.min_offset)
	return row, col
end

-- ---------------------------------------------------------------------------
-- Buffers & windows
-- ---------------------------------------------------------------------------

--- Splits any string containing `\r` or `\n` into multiple strings so the
--- result is safe to pass to `nvim_buf_set_lines`, which rejects entries
--- that contain newline characters.
---
--- @param lines string[] Raw lines (may contain embedded newlines).
--- @return string[] clean Lines guaranteed to be newline-free.
function M.sanitize_lines(lines)
	local out = {}
	for _, line in ipairs(lines) do
		if type(line) == "string" and (line:find("\r") or line:find("\n")) then
			for part in (line:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"):gmatch("([^\n]*)\n") do
				table.insert(out, part)
			end
		else
			table.insert(out, line or "")
		end
	end
	return out
end

--- Creates an unlisted scratch buffer, optionally filled with `lines`.
--- Lines are sanitized via `M.sanitize_lines` before being written, so
--- callers do not need to strip embedded newlines themselves.
---
--- @param opts table|nil { lines?: string[], filetype?: string, modifiable?: boolean }
--- @return integer buf Buffer handle.
function M.scratch_buffer(opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	if opts.filetype then
		vim.bo[buf].filetype = opts.filetype
	end
	if opts.lines then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.sanitize_lines(opts.lines))
	end
	vim.bo[buf].modifiable = opts.modifiable == true
	return buf
end

--- Opens a centered floating window over a scratch buffer.
---
--- @param opts table|nil Options:
---   lines      string[]  Initial content.
---   buf        integer   Existing buffer to reuse instead of creating one.
---   width      number    Cells, or a 0-1 fraction of the editor. Default 0.6.
---   height     number    Cells, or a 0-1 fraction of the editor. Defaults to `#lines`.
---   title      string    Window title, centered.
---   filetype   string    Buffer filetype, useful for syntax and autocmds.
---   focus      boolean   Enter the window. Default true.
---   modifiable boolean   Leave the buffer writable. Default false.
---   border     string    Overrides `M.border`.
--- @return integer buf Buffer handle.
--- @return integer win Window handle.
function M.float(opts)
	opts = opts or {}
	local buf = opts.buf
		or M.scratch_buffer({ lines = opts.lines, filetype = opts.filetype, modifiable = opts.modifiable })

	local width = M.resolve_size(opts.width or 0.6, vim.o.columns or 80)
	local height = M.resolve_size(opts.height or (opts.lines and #opts.lines) or 0.6, vim.o.lines or 24)
	local row, col = M.center(width, height)

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = opts.border or M.border,
	}
	if opts.title then
		win_opts.title = opts.title
		win_opts.title_pos = "center"
	end

	local z_index = require("krs.core.z_index")
	local name = opts.name or (opts.title and opts.title:gsub("%s+", "_"):lower()) or ("float_" .. tostring(buf))
	local z_val = opts.zindex

	if type(z_val) == "number" then
		win_opts.zindex = z_val
	else
		z_val = z_index.next_zindex(name, { parent = opts.parent, offset = opts.offset })
		win_opts.zindex = z_val
	end

	local win = vim.api.nvim_open_win(buf, opts.focus ~= false, win_opts)
	z_index.register(name, win, { zindex = z_val, parent = opts.parent, offset = opts.offset })

	return buf, win
end

--- Maps `M.close_keys` in `buf` to close `win` (and wipe the buffer).
---
--- @param buf integer Buffer handle.
--- @param win integer Window handle.
--- @param keys string[]|nil Overrides `M.close_keys`.
function M.close_on_keys(buf, win, keys)
	for _, key in ipairs(keys or M.close_keys) do
		vim.keymap.set("n", key, function()
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end, { buffer = buf, nowait = true, silent = true })
	end
end

--- Closes a window if it is still valid. Safe to call with nil.
---
--- @param win integer|nil Window handle.
function M.close(win)
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
end

-- ---------------------------------------------------------------------------
-- Dual-Panel Side-by-Side Layout Geometry & Synchronous Split Resizing
-- ---------------------------------------------------------------------------

--- Computes centered geometry for a side-by-side dual panel UI.
---
--- @param opts table|nil Configuration:
---   left_ratio?       number Current fraction of width for left panel (default 0.35).
---   width_ratio?      number Fraction of editor width for total dual panel (default 0.88).
---   height_ratio?     number Fraction of editor height for total dual panel (default 0.85).
---   gap?              integer Gap cells between left and right windows (default 2).
---   min_ratio?        number Min allowed left ratio (default 0.15).
---   max_ratio?        number Max allowed left ratio (default 0.80).
---   min_left_width?   integer Minimum left panel width (default 20).
---   min_right_width?  integer Minimum right panel width (default 20).
--- @return table Geometry details:
---   left_ratio        number Cleaned and clamped left ratio.
---   total_width       integer Total width across both panels and gap.
---   total_height      integer Total height.
---   row               integer Centered row position.
---   left_col          integer Left panel col position.
---   left_width        integer Left panel width.
---   right_col         integer Right panel col position.
---   right_width       integer Right panel width.
function M.compute_dual_panel(opts)
	opts = opts or {}
	local editor_w = vim.o.columns or 80
	local editor_h = (vim.o.lines or 24) - 2

	local min_r = opts.min_ratio or 0.15
	local max_r = opts.max_ratio or 0.80
	local raw_ratio = opts.left_ratio or 0.35
	local left_ratio = math.max(min_r, math.min(max_r, raw_ratio))
	left_ratio = tonumber(string.format("%.3f", left_ratio)) or left_ratio

	local tot_w = M.resolve_size(opts.width_ratio or 0.88, editor_w)
	local tot_h = M.resolve_size(opts.height_ratio or 0.85, editor_h)
	local gap = opts.gap or 2

	local min_left = opts.min_left_width or 20
	local min_right = opts.min_right_width or 20

	local left_w = math.floor(tot_w * left_ratio)
	left_w = math.max(min_left, math.min(tot_w - gap - min_right, left_w))
	local right_w = tot_w - left_w - gap

	local row = math.max(2, math.floor((editor_h - tot_h) / 2))
	local start_col = math.floor((editor_w - tot_w) / 2)

	return {
		left_ratio = left_ratio,
		total_width = tot_w,
		total_height = tot_h,
		row = row,
		left_col = start_col,
		left_width = left_w,
		right_col = start_col + left_w + gap,
		right_width = right_w,
	}
end

--- Adjusts and re-applies layout geometry for side-by-side dual panel UI windows synchronously.
---
--- @param opts table Configuration:
---   left_win          integer Handle to left window.
---   right_win         integer Handle to right window.
---   delta?            number Amount to adjust left_ratio (e.g. -0.03 or 0.03).
---   left_ratio?       number Current left ratio.
---   width_ratio?      number Combined width fraction.
---   height_ratio?     number Combined height fraction.
---   gap?              integer Cell gap between panels.
---   min_ratio?        number Min allowed left ratio.
---   max_ratio?        number Max allowed left ratio.
---   min_left_width?   integer Minimum left panel width.
---   min_right_width?  integer Minimum right panel width.
---   tab_win?          integer Optional tab header window above left panel.
--- @return number new_left_ratio
function M.resize_dual_panel(opts)
	opts = opts or {}
	local left_win = opts.left_win
	local right_win = opts.right_win
	if not left_win or not vim.api.nvim_win_is_valid(left_win) then
		return opts.left_ratio or 0.35
	end

	local cur_ratio = opts.left_ratio or 0.35
	local delta = opts.delta or 0
	local target_ratio = cur_ratio + delta

	local geo = M.compute_dual_panel({
		left_ratio = target_ratio,
		width_ratio = opts.width_ratio,
		height_ratio = opts.height_ratio,
		gap = opts.gap,
		min_ratio = opts.min_ratio,
		max_ratio = opts.max_ratio,
		min_left_width = opts.min_left_width,
		min_right_width = opts.min_right_width,
	})

	-- Update Left Window
	pcall(vim.api.nvim_win_set_config, left_win, {
		relative = "editor",
		row = geo.row,
		col = geo.left_col,
		width = geo.left_width,
		height = geo.total_height,
	})

	-- Update Right Window
	if right_win and vim.api.nvim_win_is_valid(right_win) then
		pcall(vim.api.nvim_win_set_config, right_win, {
			relative = "editor",
			row = geo.row,
			col = geo.right_col,
			width = geo.right_width,
			height = geo.total_height,
		})
	end

	-- Update Tab Window (if present)
	if opts.tab_win and vim.api.nvim_win_is_valid(opts.tab_win) then
		local t_width = opts.tab_full_width and (geo.total_width + 2) or (geo.left_width + 2)
		pcall(vim.api.nvim_win_set_config, opts.tab_win, {
			relative = "editor",
			row = geo.row - 1,
			col = geo.left_col - 1,
			width = t_width,
			height = 1,
		})
	end

	return geo.left_ratio
end

return M
