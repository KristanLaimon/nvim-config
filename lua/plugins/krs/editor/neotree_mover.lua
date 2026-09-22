-- ============================================================================
-- KRS PLUGIN: Neo-tree Mover ("En la mano" cut & paste workflow)
-- ============================================================================
-- WHAT IT DOES:
--   1. Replaces the old move picker menu in Neo-tree with a two-step move:
--      - First 'm' on a file or folder: picks it up "En la mano" and shows
--        a persistent toast notification.
--      - Second 'm' on a target node / directory in Neo-tree: moves the item
--        into that destination directory.
--   2. Same-directory detection: If the destination is the same place where the
--      item already was, cancels the move and warns the user.
--   3. Circular move prevention: If moving a directory, prevents moving it into
--      itself or any of its subdirectories.
--   4. Conflict detection: If an item with the same name already exists in the
--      target directory, cancels the move and reports the conflict.
--   5. Escape to cancel: Pressing <Esc> while holding an item cancels the move
--      and dismisses the persistent toast.
--   6. Buffer updates: Uses buffer_rename to keep open editor buffers and
--      bufferline tabs in sync.
--   7. LSP notifications: Fires neo-tree FILE_MOVED event for lsp file operations.
-- ============================================================================

local M = {}

M.held_item = nil
M.toast_record = nil
M.toast_id = "neotree_mover_toast"

--- Normalizes a path, stripping trailing slashes and converting slashes.
--- @param p string|nil
--- @return string
function M.normalize_path(p)
	if not p or p == "" then
		return ""
	end
	local clean = vim.fs.normalize(p)
	if #clean > 1 and clean:sub(-1) == "/" then
		clean = clean:sub(1, -2)
	end
	return clean
end

--- Returns true if an item is currently held in hand.
--- @return boolean
function M.is_holding()
	return M.held_item ~= nil
end

--- Returns a copy of the held item, or nil.
--- @return table|nil
function M.get_held_item()
	if not M.held_item then
		return nil
	end
	return vim.deepcopy(M.held_item)
end

--- Resolves the target directory based on the selected Neo-tree node.
--- If the node is a directory, returns its path.
--- If the node is a file, returns its containing directory.
--- Falls back to state.path or getcwd().
--- @param node table|nil
--- @param state table|nil
--- @return string dir_path
function M.resolve_target_dir(node, state)
	if node and node.path and node.path ~= "" then
		local norm_path = M.normalize_path(node.path)
		if node.type == "directory" or vim.fn.isdirectory(norm_path) == 1 then
			return norm_path
		else
			return M.normalize_path(vim.fn.fnamemodify(norm_path, ":h"))
		end
	end

	if state and state.path and state.path ~= "" then
		return M.normalize_path(state.path)
	end

	return M.normalize_path(vim.fn.getcwd())
end

--- Displays a persistent toast notification indicating the item is "En la mano".
--- @param item table
function M.show_persistent_toast(item)
	local icon = item.is_dir and "📁" or "📄"
	local msg = string.format(
		"✋ En la mano: %s %s\n\n➜ Navega a la carpeta destino y presiona 'm' para moverlo aquí.\n➜ Presiona 'm' en el mismo lugar o <Esc> para cancelar.",
		icon,
		item.name
	)

	-- 1. Try nvim-notify (rcarriga/nvim-notify)
	local ok_notify, notify = pcall(require, "notify")
	if ok_notify and type(notify) == "table" and type(notify.notify) == "function" then
		pcall(function()
			M.toast_record = notify.notify(msg, vim.log.levels.INFO, {
				title = "Neo-tree",
				timeout = false,
				keep = function()
					return M.is_holding()
				end,
			})
		end)
		return
	end

	-- 2. Try krs.core.notify
	local ok_krs, krs_notify = pcall(require, "krs.core.notify")
	if ok_krs and krs_notify.notify_progress then
		pcall(krs_notify.notify_progress, M.toast_id, msg, vim.log.levels.INFO, { title = "Neo-tree" })
		return
	end

	-- 3. Fallback to vim.notify
	vim.notify(msg, vim.log.levels.INFO, { title = "Neo-tree" })
end

--- Dismisses or replaces the persistent toast notification.
--- If result_msg is provided, updates the toast with the result message and auto-dismisses.
--- If omitted, closes the toast silently.
--- @param result_msg string|nil
--- @param level number|nil
function M.dismiss_toast(result_msg, level)
	level = level or vim.log.levels.INFO

	-- 1. Handle nvim-notify
	local ok_notify, notify = pcall(require, "notify")
	if ok_notify and type(notify) == "table" and type(notify.notify) == "function" then
		if M.toast_record and M.toast_record.id then
			if result_msg and result_msg ~= "" then
				pcall(notify.notify, result_msg, level, {
					title = "Neo-tree",
					replace = M.toast_record.id,
					timeout = 2500,
				})
			else
				pcall(notify.notify, "", vim.log.levels.INFO, {
					replace = M.toast_record.id,
					timeout = 1,
					hide_from_history = true,
				})
			end
			M.toast_record = nil
			return
		end
	end

	-- 2. Handle krs.core.notify
	local ok_krs, krs_notify = pcall(require, "krs.core.notify")
	if ok_krs and krs_notify then
		if result_msg and result_msg ~= "" then
			if krs_notify.notify_progress and krs_notify.finish_progress then
				pcall(krs_notify.notify_progress, M.toast_id, result_msg, level, { title = "Neo-tree" })
				pcall(krs_notify.finish_progress, M.toast_id, 2500)
				return
			end
		else
			if krs_notify.dismiss_progress then
				pcall(krs_notify.dismiss_progress, M.toast_id)
				return
			elseif krs_notify.finish_progress then
				pcall(krs_notify.finish_progress, M.toast_id, 0)
				return
			end
		end
	end

	-- 3. Fallback
	if result_msg and result_msg ~= "" then
		vim.notify(result_msg, level, { title = "Neo-tree" })
	end
end

--- Cancels any pending move operation and dismisses the persistent toast.
--- @return boolean cancelled True if an operation was cancelled
function M.cancel()
	if not M.is_holding() then
		return false
	end

	M.held_item = nil
	M.dismiss_toast("Movimiento cancelado.", vim.log.levels.INFO)
	return true
end

--- Resets state silently without notification (e.g. on Neo-tree close).
function M.reset()
	if M.is_holding() then
		M.held_item = nil
		M.dismiss_toast(nil)
	end
end

--- Executes the move action triggered by 'm' in Neo-tree.
--- If not holding: picks up the node under cursor "En la mano".
--- If already holding: moves the held item to the selected target directory.
--- @param node table|nil
--- @param state table|nil
function M.handle_move(node, state)
	-- First press: Pick up item
	if not M.is_holding() then
		if not node or not node.path or node.path == "" then
			vim.notify("⚠️ No hay ningún archivo o carpeta seleccionada para mover.", vim.log.levels.WARN, {
				title = "Neo-tree",
			})
			return
		end

		local norm_path = M.normalize_path(node.path)
		local is_dir = (node.type == "directory" or vim.fn.isdirectory(norm_path) == 1)
		local name = node.name or vim.fn.fnamemodify(norm_path, ":t")
		local parent = M.normalize_path(vim.fn.fnamemodify(norm_path, ":h"))

		M.held_item = {
			path = norm_path,
			name = name,
			type = node.type or (is_dir and "directory" or "file"),
			is_dir = is_dir,
			parent = parent,
		}

		M.show_persistent_toast(M.held_item)
		return
	end

	-- Second press: Drop / move item
	local held = M.held_item
	local target_dir = M.resolve_target_dir(node, state)
	local orig_parent = held.parent
	local orig_path = held.path
	local dest_path = M.normalize_path(target_dir .. "/" .. held.name)

	-- Check 1: Same directory / same place
	if target_dir == orig_parent or dest_path == orig_path then
		M.held_item = nil
		M.dismiss_toast(
			string.format("⚠️ '%s' ya estaba en donde mismo. Movimiento cancelado.", held.name),
			vim.log.levels.WARN
		)
		return
	end

	-- Check 2: Moving a directory into itself or one of its descendants
	if held.is_dir and (target_dir == orig_path or target_dir:sub(1, #orig_path + 1) == orig_path .. "/") then
		M.held_item = nil
		M.dismiss_toast(
			string.format("⚠️ No puedes mover la carpeta '%s' dentro de sí misma. Movimiento cancelado.", held.name),
			vim.log.levels.WARN
		)
		return
	end

	-- Check 3: Collision with existing file or folder in target directory
	local uv = vim.uv or vim.loop
	if uv.fs_stat(dest_path) ~= nil then
		M.held_item = nil
		M.dismiss_toast(
			string.format("❌ Ya existe un elemento llamado '%s' en el destino. Movimiento cancelado.", held.name),
			vim.log.levels.ERROR
		)
		return
	end

	-- Ensure target directory exists
	if vim.fn.isdirectory(target_dir) == 0 then
		vim.fn.mkdir(target_dir, "p")
	end

	-- Check 4: Perform filesystem move
	local ok, err = os.rename(orig_path, dest_path)
	if not ok then
		local uv_ok, uv_err = uv.fs_rename(orig_path, dest_path)
		if uv_ok then
			ok = true
			err = nil
		else
			err = uv_err or err
		end
	end

	if ok then
		-- Fire neo-tree FILE_MOVED event for LSP file operations
		local ok_ev, events = pcall(require, "neo-tree.events")
		if ok_ev and events and events.FILE_MOVED then
			pcall(events.fire_event, events.FILE_MOVED, {
				source = orig_path,
				destination = dest_path,
			})
		end

		-- Update open buffers and bufferline tabs
		local ok_br, buffer_rename = pcall(require, "krs.core.buffer_rename")
		if ok_br and buffer_rename and buffer_rename.update_buffers_path then
			pcall(buffer_rename.update_buffers_path, orig_path, dest_path)
		end

		M.held_item = nil

		-- Refresh Neo-tree filesystem
		pcall(function()
			require("neo-tree.sources.manager").refresh("filesystem")
		end)

		local display_target = vim.fn.fnamemodify(target_dir, ":~:.")
		if display_target == "" or display_target == "." then
			display_target = target_dir
		end

		M.dismiss_toast(string.format("🚚 Movido: '%s' ➜ %s", held.name, display_target), vim.log.levels.INFO)
	else
		M.held_item = nil
		M.dismiss_toast(string.format("❌ Error al mover '%s': %s", held.name, tostring(err)), vim.log.levels.ERROR)
	end
end

--- Helper for Ex command / Command Palette invocation.
function M.handle_move_ex()
	local ok, manager = pcall(require, "neo-tree.sources.manager")
	if ok and manager then
		local state = manager.get_state("filesystem")
		local node = state and state.tree and state.tree:get_node()
		M.handle_move(node, state)
	else
		vim.notify("Neo-tree no está activo", vim.log.levels.WARN, { title = "Neo-tree" })
	end
end

M.name = "krs_neotree_mover"
M.dir = require("krs.core.lazyspec").for_module()
M.event = "VeryLazy"
M.config = function() end

return M
