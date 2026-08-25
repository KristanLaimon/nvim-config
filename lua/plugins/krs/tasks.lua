-- ============================================================================
-- KRS PLUGIN: Task Runner -- per-project tasks, chains and output slots.
-- ============================================================================
-- WHAT IT DOES
--   1. Discovers tasks from the project itself (Makefile, package.json, Cargo.toml,
--      go.mod) and merges them with custom tasks from `.krsnvim/tasks.json`.
--   2. Runs a task as a CHAIN of steps in a terminal buffer; a failing step halts
--      the chain and pops an alert instead of silently continuing.
--   3. Keeps up to `M.settings.max_slots` task outputs alive at once, each toggleable
--      without losing its scrollback.
--
-- KEYBINDS (see M.settings.keys to change them)
--   <C-S-t>          Task menu (Telescope)          <F5>  Run default task
--   <F6>             Task menu                      <C-i> Toggle last task output
--   <C-A-S-1..4>     Toggle task output slot 1..4
--
-- PROJECT FILE -- `.krsnvim/tasks.json`
--   {
--     "default_task": { "name": "Dev", "cmd": "npm run dev" },
--     "custom_tasks": [
--       { "name": "Dev", "cmd": "npm run dev" },
--       { "name": "Ship", "chain": ["npm run build", "npm test"] },
--       { "name": "Deploy", "depends_on": ["Ship"], "cmd": "npm run deploy" }
--     ]
--   }
--
-- PUBLIC API (also used by launch_profiles and the command palette)
--   M.get_project_root()                      Project root for the current buffer.
--   M.run_task_item(item, root, opts)         Run a task table/string; opts.on_done(code).
--   M.run_custom_command(cmd, env, cb, name)  Run one command with env + callback.
--   M.open_task_menu()                        Telescope picker over every task.
--   M.stop_task(slot) / M.restart_task(slot)  Control a running slot.
--
-- COLLABORATORS
--   krs.core.store / project / path -- persistence and root resolution.
--   telescope -- picker UI only; nothing else here depends on it.
-- ============================================================================

local lazy_req = require("krs.core.lazy_require")
local store = lazy_req("krs.core.store")
local project = lazy_req("krs.core.project")
local path = lazy_req("krs.core.path")
local ui = lazy_req("krs.core.ui")
local dock = lazy_req("krs.core.dock")

local M = {}

-- ============================================================================
-- CONFIGURATION -- everything tunable lives here
-- ============================================================================

M.settings = {
	--- How many task outputs can live at once. Slot toggles are bound for each.
	max_slots = 4,

	--- Height, in lines, of a freshly opened task output split.
	output_height = 12,

	--- Title used by every notification from this module.
	notify_title = "KRS Task Runner",

	--- Pre-`.krsnvim` global store, still read so old projects keep their tasks.
	legacy_store_file = vim.fn.stdpath("data") .. "/project_tasks.json",

	--- Name of the per-project config file inside `.krsnvim/`.
	config_file = "tasks.json",

	--- Legacy single-file config at the project root, read when no `.krsnvim` exists.
	legacy_project_file = ".nvimkrs",

	--- Environment forced on every task process, so output is UTF-8 on Windows too.
	--- A task's own env (opts.env) wins over these defaults.
	forced_env = {
		PYTHONUTF8 = "1",
		PYTHONIOENCODING = "utf-8",
		NODE_IO_ENCODING = "utf-8",
		LANG = "en_US.UTF-8",
		LC_ALL = "en_US.UTF-8",
	},

	keys = {
		--- Open the task menu. Bound in normal, insert, visual and terminal mode.
		menu = { "<C-S-t>", "<C-S-T>", "<leader>tm" },
		--- Run the default task, falling back to launch profile or menu.
		run_default = { "<C-S-a>", "<C-S-A>", "<C-A>", "<F5>" },
		--- Open the task menu (function-key alternative).
		menu_fkey = "<F6>",
		--- Toggle the most recently used task output.
		toggle_last = { "<C-`>", "<C-~>", "<C-S-i>", "<C-S-I>", "<C-A-S-j>" },
		--- Toggle the output of the slot you are currently inside.
		toggle_from_output = { "<C-i>", "<C-I>", "<C-`>", "<C-~>", "<C-S-i>", "<C-S-I>", "<C-A-S-j>", "<C-[>" },
		--- Dismiss a finished task window / the failure alert.
		dismiss = { "<CR>", "<Esc>", "q", "<Space>" },
		--- Prefix for per-slot toggles; the slot number is appended (`<C-A-S-1>`).
		slot_prefix = "<C-A-S-",
		--- Mappings deleted on setup because they collide with <Esc> in terminals.
		unbind = { "<C-[>", "<C-S-[>", "<C-{>" },
	},

	--- Task discovery rules, applied in order. `tasks` is either a fixed list of
	--- commands or a function(filepath) -> string[] for files that need parsing.
	--- ADD A NEW ECOSYSTEM HERE -- nothing else needs to change.
	discovery = {
		{
			file = "Makefile",
			tasks = function(filepath)
				local out = {}
				for _, line in ipairs(vim.fn.readfile(filepath)) do
					local target = line:match("^([a-zA-Z0-9_%-.]+):")
					if target and target ~= ".PHONY" and target ~= "all" and not target:find("^%.") then
						table.insert(out, "make " .. target)
					end
				end
				return out
			end,
		},
		{
			file = "package.json",
			tasks = function(filepath)
				local out = {}
				local pkg = store.load(filepath, {})
				for script_name, _ in pairs(pkg.scripts or {}) do
					table.insert(out, "npm run " .. script_name)
				end
				return out
			end,
		},
		{ file = "Cargo.toml", tasks = { "cargo run", "cargo build", "cargo test" } },
		{ file = "go.mod", tasks = { "go run .", "go test ./..." } },
		{
			file = ".vscode/tasks.json",
			tasks = function(filepath)
				local out = {}
				local data = store.load(filepath, {})
				local tasks_list = data.tasks or {}
				for _, t in ipairs(tasks_list) do
					local cmd = t.command or t.script
					if type(cmd) == "string" and cmd ~= "" then
						table.insert(out, cmd)
					elseif type(t.label) == "string" and t.label ~= "" then
						table.insert(out, t.label)
					end
				end
				return out
			end,
		},
	},
}

-- ============================================================================
-- RUNTIME STATE
-- ============================================================================

--- Task output slots, keyed 1..max_slots.
--- @class TaskSlot
--- @field win integer|nil Window showing the output, nil when hidden.
--- @field buf integer|nil Terminal buffer holding the scrollback.
--- @field job_id integer|nil Running job, nil when the task finished.
--- @field name string Task name, shown in notifications.
--- @field task_item table|string|nil Definition, kept so the slot can restart.
--- @field root string|nil Working directory the task ran in.
M.slots = {}

--- Slot targeted by "toggle last output".
M.last_slot = nil

--- Window to return focus to when a task output closes.
M.origin_win = nil

--- Convenience wrapper so every message carries the same title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

-- ============================================================================
-- PERSISTENCE -- `.krsnvim/tasks.json` plus the two legacy fallbacks
-- ============================================================================

--- Resolves the project root for the current buffer.
--- @return string root
function M.get_project_root()
	return project.root()
end

--- Resolves the tasks file for `root`.
--- Order: `.krsnvim/tasks.json`, then the legacy `.nvimkrs` file at the root.
--- When neither exists the `.krsnvim` path is returned so writers create it.
---
--- @param root string Project root.
--- @return string filepath
local function tasks_filepath(root)
	local norm_root = path.normalize(root)
	local krs_file = path.join(norm_root, ".krsnvim", M.settings.config_file)
	if path.is_file(krs_file) then
		return krs_file
	end

	local legacy = path.join(norm_root, M.settings.legacy_project_file)
	if path.is_file(legacy) then
		return legacy
	end

	return krs_file
end

--- Loads the task configuration for a project.
--- Falls back to the pre-`.krsnvim` global store keyed by lowercased root path.
---
--- @param root string Project root.
--- @return table pdata `{ default_task = ..., custom_tasks = {...} }`
function M.get_project_data(root)
	local data = store.load(tasks_filepath(root), nil)
	if data then
		return {
			default_task = data.default_task,
			custom_tasks = type(data.custom_tasks) == "table" and data.custom_tasks or {},
		}
	end

	local legacy = store.load(M.settings.legacy_store_file, {})[path.normalize(root):lower()]
	if legacy then
		return legacy
	end

	return { default_task = nil, custom_tasks = {} }
end

--- Writes the task configuration to `.krsnvim/tasks.json`, creating the directory.
---
--- @param root string Project root.
--- @param pdata table `{ default_task = ..., custom_tasks = {...} }`
function M.save_project_data(root, pdata)
	store.save(path.join(project.config_dir(root), M.settings.config_file), {
		default_task = pdata.default_task,
		custom_tasks = pdata.custom_tasks or {},
	})
end

-- ============================================================================
-- DISCOVERY & CHAIN RESOLUTION
-- ============================================================================

--- Scans the project for tasks it can infer, following `M.settings.discovery`.
---
--- @param root string Project root.
--- @return table[] discovered `{ name, cmd, source }` entries.
function M.discover_tasks(root)
	local norm_root = path.normalize(root)
	local discovered = {}

	for _, rule in ipairs(M.settings.discovery) do
		local filepath = path.join(norm_root, rule.file)
		if path.is_file(filepath) then
			local cmds = type(rule.tasks) == "function" and rule.tasks(filepath) or rule.tasks
			for _, cmd in ipairs(cmds) do
				table.insert(discovered, { name = cmd, cmd = cmd, source = rule.file })
			end
		end
	end

	return discovered
end

--- Flattens a task definition into the ordered list of shell commands to run.
--- Resolves `depends_on` first (recursively), then `chain`, then a plain `cmd`.
---
--- @param task_item table|string|nil Task definition or bare command string.
--- @param pdata table Project data, used to look up `depends_on` names.
--- @return string[] steps Commands in execution order.
function M.resolve_steps(task_item, pdata)
	if not task_item then
		return {}
	end
	if type(task_item) == "string" then
		return { task_item }
	end
	if type(task_item) ~= "table" then
		return {}
	end

	local steps = {}

	if type(task_item.depends_on) == "table" then
		for _, dep_name in ipairs(task_item.depends_on) do
			for _, ct in ipairs(pdata.custom_tasks or {}) do
				if (ct.name and ct.name == dep_name) or (ct.cmd and ct.cmd == dep_name) then
					vim.list_extend(steps, M.resolve_steps(ct, pdata))
				end
			end
		end
	end

	if type(task_item.chain) == "table" then
		for _, step in ipairs(task_item.chain) do
			if type(step) == "string" then
				table.insert(steps, step)
			end
		end
	elseif type(task_item.cmd) == "string" and task_item.cmd ~= "" then
		table.insert(steps, task_item.cmd)
	end

	return steps
end

-- ============================================================================
-- WINDOW LAYOUT -- task outputs live in the shared bottom dock
-- ============================================================================

--- Re-exported so older callers (and the keybinds file) keep working.
M.enforce_bottom_layout = dock.enforce_order

-- ============================================================================
-- SLOT MANAGEMENT
-- ============================================================================

--- Re-attaches task buffers that survived a config reload (or were restored from a
--- session) to their slot, so toggles keep working without re-running the task.
function M.sync_task_slots()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local is_task = vim.api.nvim_buf_is_valid(buf) and (vim.b[buf].krs_is_task or vim.bo[buf].filetype == "TaskRunner")

		if is_task then
			local slot = vim.b[buf].krs_task_slot
			if not slot or slot < 1 or slot > M.settings.max_slots then
				slot = nil
				for i = 1, M.settings.max_slots do
					local s = M.slots[i]
					if not s or not s.buf or not vim.api.nvim_buf_is_valid(s.buf) then
						slot = i
						break
					end
				end
			end

			local occupant = slot and M.slots[slot]
			local slot_is_free = slot and (not occupant or not occupant.buf or not vim.api.nvim_buf_is_valid(occupant.buf))

			if slot_is_free then
				local win
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == buf then
						win = w
						break
					end
				end

				M.slots[slot] = {
					win = win,
					buf = buf,
					job_id = nil,
					name = vim.b[buf].krs_task_name or "Task Output",
				}
				vim.b[buf].krs_is_task = true
				vim.b[buf].krs_task_slot = slot
				M.last_slot = M.last_slot or slot
			end
		end
	end
end

--- First slot with no running job.
--- @return integer|nil slot
local function get_free_slot()
	M.sync_task_slots()
	for i = 1, M.settings.max_slots do
		local s = M.slots[i]
		if not s or not s.job_id then
			return i
		end
	end
	return nil
end

--- The slot the cursor is in, else the last used one, else any populated slot.
--- @return integer|nil slot
function M.get_active_or_last_slot()
	M.sync_task_slots()

	local cur_slot = vim.b[vim.api.nvim_get_current_buf()].krs_task_slot
	if cur_slot and M.slots[cur_slot] then
		return cur_slot
	end
	if M.last_slot and M.slots[M.last_slot] then
		return M.last_slot
	end
	for i = 1, M.settings.max_slots do
		if M.slots[i] then
			return i
		end
	end
	return nil
end

-- ============================================================================
-- TASK BUFFER KEYMAPS
-- ============================================================================

--- Pastes the OS clipboard into a terminal buffer (`"+`, falling back to `"*`).
local function paste_clipboard()
	local clip = vim.fn.getreg("+")
	if not clip or clip == "" then
		clip = vim.fn.getreg("*")
	end
	if clip and clip ~= "" then
		vim.api.nvim_paste(clip, true, -1)
	end
end

--- Binds toggle, escape-to-editor and clipboard keys inside a task output buffer.
---
--- @param buf integer Task terminal buffer.
--- @param slot integer Slot the buffer belongs to.
local function bind_task_buffer_keys(buf, slot)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	for _, key in ipairs(M.settings.keys.toggle_from_output) do
		vim.keymap.set({ "n", "t", "i", "v" }, key, function()
			if vim.fn.mode() == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			M.toggle_slot_window(slot)
		end, { noremap = true, silent = true, buffer = buf, desc = "Toggle Task Output Window" })
	end

	vim.keymap.set("t", "<Esc><Esc>", function()
		pcall(vim.cmd, "stopinsert")
		if M.origin_win and vim.api.nvim_win_is_valid(M.origin_win) then
			pcall(vim.api.nvim_set_current_win, M.origin_win)
		end
	end, { noremap = true, silent = true, buffer = buf, desc = "Return to Code Editor" })

	local opts = { noremap = true, silent = true, buffer = buf, desc = "Paste OS Clipboard" }
	vim.keymap.set({ "n", "t", "i" }, "<C-v>", paste_clipboard, opts)
	vim.keymap.set({ "n", "t", "i" }, "<C-S-v>", paste_clipboard, opts)

	local copy_opts = { noremap = true, silent = true, buffer = buf, desc = "Copy selection to OS Clipboard" }
	vim.keymap.set("v", "<C-c>", '"+y', copy_opts)
	vim.keymap.set("v", "<C-S-c>", '"+y', copy_opts)
end

--- Binds the dismiss keys of a FINISHED task window: leave the output, return to
--- the window the task was launched from, and free the slot's window handle.
---
--- @param buf integer Task buffer.
--- @param win integer Task window.
--- @param slot integer Slot index.
--- @param origin_win integer|nil Window to focus after closing.
local function bind_dismiss_keys(buf, win, slot, origin_win)
	local function close_task_window()
		if origin_win and vim.api.nvim_win_is_valid(origin_win) then
			pcall(vim.api.nvim_set_current_win, origin_win)
		else
			pcall(vim.cmd, "wincmd p")
		end
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
		if M.slots[slot] and M.slots[slot].win == win then
			M.slots[slot].win = nil
		end
	end

	local opts = { noremap = true, silent = true, nowait = true, buffer = buf }
	for _, key in ipairs(M.settings.keys.dismiss) do
		vim.keymap.set({ "n", "t", "i", "v" }, key, close_task_window, opts)
	end
end

--- Shows or hides the output window of a slot.
--- @param n integer Slot index.
function M.toggle_slot_window(n)
	M.sync_task_slots()

	local s = M.slots[n]
	if not s or not s.buf or not vim.api.nvim_buf_is_valid(s.buf) then
		notify("No task in slot " .. n, vim.log.levels.WARN)
		return
	end

	if s.win and vim.api.nvim_win_is_valid(s.win) then
		pcall(vim.cmd, "stopinsert")
		pcall(vim.api.nvim_win_close, s.win, true)
		s.win = nil
		if M.origin_win and vim.api.nvim_win_is_valid(M.origin_win) then
			pcall(vim.api.nvim_set_current_win, M.origin_win)
		else
			pcall(vim.cmd, "wincmd p")
		end
	else
		-- Remember where we came from, unless we are already inside a task output.
		local current = vim.api.nvim_get_current_win()
		local active_slot_win
		for _, slot in pairs(M.slots) do
			if slot.win and vim.api.nvim_win_is_valid(slot.win) then
				active_slot_win = slot.win
				break
			end
		end
		if current ~= active_slot_win then
			M.origin_win = current
		end

		s.win = dock.open({ prefer = "task", height = M.settings.output_height })
		vim.api.nvim_win_set_buf(s.win, s.buf)
		dock.style(s.win)
		bind_task_buffer_keys(s.buf, n)
	end

	M.last_slot = n
end

--- Toggles the most recently used slot.
function M.toggle_last_slot_window()
	M.sync_task_slots()
	if not M.last_slot then
		notify("No task has been run yet", vim.log.levels.WARN)
		return
	end
	M.toggle_slot_window(M.last_slot)
end

-- ============================================================================
-- EXECUTION
-- ============================================================================

--- Modal alert shown when a chain step fails, listing what was cancelled.
---
--- @param step_idx integer Failing step number (1-based).
--- @param total_steps integer Steps in the chain.
--- @param failed_cmd string The command that failed.
--- @param exit_code integer Process exit code.
--- @param remaining_count integer Steps that were cancelled.
local function show_failure_alert(step_idx, total_steps, failed_cmd, exit_code, remaining_count)
	local width = math.floor(vim.o.columns * 0.70)
	local lines = {
		" ❌ TASK CHAIN EXECUTION FAILED",
		string.rep("═", width - 4),
		string.format("  • Step %d of %d failed!", step_idx, total_steps),
		string.format("  • Failed Command: %s", (failed_cmd:gsub("[\r\n]+", " "))),
		string.format("  • Exit Code: %d", exit_code),
		"",
		string.format(" ⛔ Execution HALTED. %d remaining task(s) CANCELLED.", remaining_count),
		"",
		" Press <Enter>, <Esc> or 'q' to close this alert and inspect logs below.",
	}

	local buf, win = ui.float({
		lines = lines,
		width = width,
		height = #lines + 2,
		title = " 🚨 ALERT: Task Chain Interrupted ",
	})
	pcall(vim.api.nvim_set_option_value, "cursorline", false, { win = win })

	local opts = { buffer = buf, noremap = true, silent = true }
	for _, key in ipairs(M.settings.keys.dismiss) do
		vim.keymap.set({ "n", "v", "i" }, key, function()
			ui.close(win)
		end, opts)
	end
end

--- Builds the process environment: caller values first, UTF-8 defaults filled in.
---
--- @param env table|nil Caller-supplied environment.
--- @return table<string,string> env
local function build_env(env)
	local out = {}
	for k, v in pairs(env or {}) do
		if v ~= nil then
			out[tostring(k)] = tostring(v)
		end
	end
	for k, v in pairs(M.settings.forced_env) do
		out[k] = out[k] or v
	end
	return out
end

--- Splits a simple command into argv so it runs without a shell.
--- Commands containing shell metacharacters (`| & > < ;`) are handed to the shell
--- untouched, because splitting them would change their meaning.
---
--- @param cmd string Command line.
--- @return string|string[] target Argv list, or the original string.
local function to_exec_target(cmd)
	if type(cmd) ~= "string" or cmd == "" or cmd:find("[|&><;]") then
		return cmd
	end

	local argv = {}
	for quoted, word in cmd:gmatch([=[["'](.-)["']|(%S+)]=]) do
		table.insert(argv, quoted or word)
	end
	return #argv > 0 and argv or cmd
end

--- Prepares a slot for a new run: kills the previous job, drops its window/buffer,
--- and opens a fresh terminal buffer wired to the slot.
---
--- @param slot integer Slot index.
--- @param task_name string Display name.
--- @param task_item table|string Definition, kept for restart.
--- @param root string Working directory.
--- @param steps string[] Resolved chain.
local function reset_slot(slot, task_name, task_item, root, steps)
	local prev = M.slots[slot]
	if prev then
		if prev.job_id and prev.job_id > 0 then
			prev.is_killing_for_restart = true
			pcall(vim.fn.jobstop, prev.job_id)
		end
		if prev.win and vim.api.nvim_win_is_valid(prev.win) then
			pcall(vim.api.nvim_win_close, prev.win, true)
		end
		if prev.buf and vim.api.nvim_buf_is_valid(prev.buf) then
			pcall(vim.api.nvim_buf_delete, prev.buf, { force = true })
		end
	end

	local win = dock.open({ prefer = "task", height = M.settings.output_height })
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)

	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "TaskRunner"
	vim.b[buf].krs_is_task = true
	vim.b[buf].krs_task_slot = slot
	vim.b[buf].krs_task_name = task_name

	dock.style(win)
	bind_task_buffer_keys(buf, slot)

	M.slots[slot] = {
		win = win,
		buf = buf,
		job_id = nil,
		name = task_name,
		task_item = task_item,
		root = root,
		steps = steps,
		is_killing_for_restart = false,
		is_killing = false,
	}
	M.last_slot = slot
end

--- Runs step `step_idx` of a chain, recursing into the next step on success.
---
--- @param step_idx integer 1-based step index.
--- @param steps string[] All steps in the chain.
--- @param root string Working directory.
--- @param origin_win integer|nil Window to restore focus to.
--- @param task_name string Display name.
--- @param slot integer Slot index.
--- @param task_item table|string Definition, kept for restart.
--- @param opts table|nil `{ env = table, on_done = function(exit_code) }`.
---
--- `on_done` fires once per CHAIN: 0 when every step succeeded, the failing step's
--- exit code otherwise. Callers that gate further work on the result (launch
--- profiles' pre-launch tasks) depend on it; nothing else passes opts.
local function run_step_sequence(step_idx, steps, root, origin_win, task_name, slot, task_item, opts)
	opts = opts or {}
	local total = #steps
	local current_cmd = steps[step_idx]

	if step_idx == 1 then
		reset_slot(slot, task_name, task_item, root, steps)
	end

	local s = M.slots[slot]
	local win, buf = s.win, s.buf

	notify(string.format("🚀 Running Step %d/%d: %s", step_idx, total, task_name or "Task"))

	--- Focuses the output window and lets the dismiss keys close it.
	local function finish_and_arm_dismiss()
		if M.slots[slot] then
			M.slots[slot].job_id = nil
		end
		pcall(vim.cmd, "stopinsert")
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_set_current_win, win)
		end
		bind_dismiss_keys(buf, win, slot, origin_win)
	end

	local function on_exit(_, exit_code)
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				if opts.on_done then
					opts.on_done(exit_code)
				end
				return
			end

			local cur = M.slots[slot]
			if cur and (cur.is_killing_for_restart or cur.is_killing) then
				-- Stopped or restarted by hand: never report success, or a waiting
				-- caller would treat a cancelled build as a passing one.
				if opts.on_done then
					opts.on_done(exit_code == 0 and 1 or exit_code)
				end
				return
			end

			if exit_code ~= 0 then
				finish_and_arm_dismiss()
				show_failure_alert(step_idx, total, current_cmd, exit_code, total - step_idx)
				if opts.on_done then
					opts.on_done(exit_code)
				end
				return
			end

			if step_idx < total then
				notify(string.format("✅ Step %d/%d completed. Starting Step %d/%d...", step_idx, total, step_idx + 1, total))
				run_step_sequence(step_idx + 1, steps, root, origin_win, task_name, slot, task_item, opts)
				return
			end

			finish_and_arm_dismiss()
			notify(
				string.format(
					"✅ Task chain '%s' (%d/%d steps) finished successfully. Press <Enter> to close.",
					task_name or "Chain",
					total,
					total
				)
			)
			if opts.on_done then
				opts.on_done(0)
			end
		end)
	end

	local job_id = vim.fn.termopen(to_exec_target(current_cmd), {
		cwd = root,
		env = build_env(opts.env),
		on_exit = on_exit,
	})

	if job_id <= 0 then
		notify("Error starting command: " .. current_cmd, vim.log.levels.ERROR)
		if opts.on_done then
			opts.on_done(1)
		end
		return
	end

	s.job_id = job_id
	vim.cmd("startinsert")
end

--- Runs a task definition, reusing the slot of a same-named running task.
---
--- @param task_item table|string Task definition or bare command.
--- @param root string|nil Working directory. Defaults to the project root.
--- @param opts table|nil `{ env = table, on_done = function(exit_code) }`.
function M.run_task_item(task_item, root, opts)
	opts = opts or {}
	root = root or M.get_project_root()

	local pdata = M.get_project_data(root)
	local steps = M.resolve_steps(task_item, pdata)

	-- Every bail-out reports failure too, or a caller waiting on on_done (launch
	-- profiles) would sit there forever instead of aborting.
	local function abort(msg)
		notify(msg, vim.log.levels.WARN)
		if opts.on_done then
			opts.on_done(1)
		end
	end

	if #steps == 0 then
		return abort("No executable steps found for this task")
	end

	M.sync_task_slots()

	local task_name = (type(task_item) == "table" and (task_item.name or task_item.cmd)) or tostring(task_item)

	-- Re-running the SAME task that is currently running toggles it off (kills job & closes window).
	-- Running a DIFFERENT task opens a new output slot for concurrent execution.
	local running_slot
	for i = 1, M.settings.max_slots do
		local s = M.slots[i]
		if s and s.job_id and s.job_id > 0 then
			local same_name = (s.name or "") == task_name
			local same_item = s.task_item
				and (
					s.task_item == task_item
					or (type(s.task_item) == "table" and type(task_item) == "table" and s.task_item.name == task_item.name)
				)
			if same_name or same_item then
				running_slot = i
				break
			end
		end
	end

	if running_slot then
		local s = M.slots[running_slot]
		s.is_killing = true
		pcall(vim.fn.jobstop, s.job_id)
		s.job_id = nil
		if s.win and vim.api.nvim_win_is_valid(s.win) then
			pcall(vim.api.nvim_win_close, s.win, true)
			s.win = nil
		end
		notify(string.format("⏹️ Stopped task '%s' (Slot #%d)", task_name, running_slot))
		if opts.on_done then
			opts.on_done(1)
		end
		return
	end

	local slot = get_free_slot()
	if not slot then
		return abort(
			string.format(
				"All %d task slots are busy. Stop one first (Ctrl+Shift+Alt+1..%d to view, q/<CR> in it once done).",
				M.settings.max_slots,
				M.settings.max_slots
			)
		)
	end

	local origin_win = vim.api.nvim_get_current_win()
	vim.cmd("silent! write")

	run_step_sequence(1, steps, root, origin_win, task_name, slot, task_item, opts)
end

--- Runs a bare command string as a task.
--- @param cmd string Shell command.
--- @param root string|nil Working directory.
function M.run_task_cmd(cmd, root)
	M.run_task_item(cmd, root)
end

--- Runs one command in a task slot with a custom environment and completion
--- callback. This is the entry point launch_profiles uses for pre-launch tasks
--- and for run-mode profiles.
---
--- @param cmd string Shell command.
--- @param env table|nil Extra environment variables.
--- @param on_exit function|nil Called with the exit code when the task ends.
--- @param task_name string|nil Display name; derived from `cmd` when omitted.
function M.run_custom_command(cmd, env, on_exit, task_name)
	local name = task_name
	if not name and type(cmd) == "string" then
		name = cmd:match("(%S+%.krsnvim)") or cmd:match("(%S+%.%w+)$") or vim.fn.fnamemodify(cmd, ":t")
	end
	M.run_task_item({ name = name or "Custom Task", cmd = cmd }, nil, { env = env, on_done = on_exit })
end

--- Stops the job in a slot, if any.
--- @param slot integer|nil Defaults to the active or last slot.
--- @return boolean stopped
function M.stop_task(slot)
	slot = slot or M.get_active_or_last_slot()
	if not slot or not M.slots[slot] then
		notify("No task found to stop", vim.log.levels.WARN)
		return false
	end

	local s = M.slots[slot]
	if not (s.job_id and s.job_id > 0) then
		notify(string.format("Task '%s' (Slot #%d) is not currently running", s.name or "Task", slot), vim.log.levels.WARN)
		return false
	end

	s.is_killing = true
	pcall(vim.fn.jobstop, s.job_id)
	s.job_id = nil
	notify(string.format("🛑 Stopped task '%s' (Slot #%d)", s.name or "Task", slot))
	return true
end

--- Re-runs the task stored in a slot, killing it first when still running.
--- @param slot integer|nil Defaults to the active or last slot.
function M.restart_task(slot)
	slot = slot or M.get_active_or_last_slot()
	if not slot or not M.slots[slot] then
		notify("No active task found to restart. Run a task first (<C-S-t> or Command Palette).", vim.log.levels.WARN)
		return
	end

	local s = M.slots[slot]
	local task_item = s.task_item
	if not task_item then
		notify("Cannot restart task: no stored task definition found for slot #" .. slot, vim.log.levels.WARN)
		return
	end

	local root = s.root or M.get_project_root()
	local task_name = s.name or "Task"

	if s.job_id and s.job_id > 0 then
		s.is_killing_for_restart = true
		pcall(vim.fn.jobstop, s.job_id)
		s.job_id = nil
		notify(string.format("🔄 Killed running task '%s' (Slot #%d). Restarting...", task_name, slot))
	else
		notify(string.format("🔄 Restarting task '%s' (Slot #%d)...", task_name, slot))
	end

	local steps = M.resolve_steps(task_item, M.get_project_data(root))
	if #steps == 0 then
		notify("No executable steps found for task", vim.log.levels.WARN)
		return
	end

	local origin_win = vim.api.nvim_get_current_win()
	vim.cmd("silent! write")

	run_step_sequence(1, steps, root, origin_win, task_name, slot, task_item)
end

--- Runs the project's default task, or opens the menu when none is set.
function M.run_default_or_menu()
	local root = M.get_project_root()
	local pdata = M.get_project_data(root)

	if pdata and pdata.default_task then
		M.run_task_item(pdata.default_task, root)
		return
	end

	local ok_lp, lp = pcall(require, "plugins.krs.launch_profiles")
	if ok_lp and lp.get_default_profile then
		local def_prof = lp.get_default_profile(root)
		if def_prof then
			lp.run_profile(def_prof, root)
			return
		end
	end

	M.open_task_menu()
end

-- ============================================================================
-- TASK MENU (Telescope)
-- ============================================================================

--- Merges custom tasks with discovered ones, dropping discovered duplicates.
---
--- @param pdata table Project data.
--- @param discovered table[] Result of `M.discover_tasks`.
--- @return table[] entries `{ name, item, steps_count, source, is_custom }`
local function build_menu_entries(pdata, discovered)
	local entries = {}

	for _, ct in ipairs(pdata.custom_tasks or {}) do
		table.insert(entries, {
			name = ct.name or (type(ct.cmd) == "string" and ct.cmd) or "Chained Task",
			item = ct,
			steps_count = #M.resolve_steps(ct, pdata),
			source = "custom",
			is_custom = true,
		})
	end

	for _, dt in ipairs(discovered) do
		local exists = false
		for _, entry in ipairs(entries) do
			local item = entry.item
			if (type(item) == "string" and item == dt.cmd) or (type(item) == "table" and item.cmd == dt.cmd) then
				exists = true
				break
			end
		end
		if not exists then
			table.insert(entries, { name = dt.name, item = dt.cmd, steps_count = 1, source = dt.source })
		end
	end

	return entries
end

--- True when `entry` is the project's default task.
--- @param entry table Menu entry.
--- @param default_task table|string|nil Stored default.
--- @return boolean
local function is_default_entry(entry, default_task)
	if not default_task then
		return false
	end
	if type(default_task) == "string" then
		return entry.name == default_task or entry.item == default_task
	end
	return type(entry.item) == "table" and (default_task.name == entry.item.name or default_task.cmd == entry.item.cmd)
end

--- Opens the task picker: <CR> runs, `d` sets default, `a` adds, `c` chains,
--- `x` deletes. With no tasks at all it prompts for a first command.
function M.open_task_menu()
	local root = M.get_project_root()
	local pdata = M.get_project_data(root)
	local entries = build_menu_entries(pdata, M.discover_tasks(root))

	if #entries == 0 then
		vim.ui.input({ prompt = "No tasks detected. Enter command to execute: " }, function(cmd)
			if cmd and cmd ~= "" then
				local new_task = { name = cmd, cmd = cmd }
				pdata.custom_tasks = pdata.custom_tasks or {}
				table.insert(pdata.custom_tasks, new_task)
				pdata.default_task = new_task
				M.save_project_data(root, pdata)
				M.run_task_item(new_task, root)
			end
		end)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local themes = require("telescope.themes")

	local default_task = pdata.default_task

	pickers
		.new(
			themes.get_dropdown({
				prompt_title = " 🛠️ Tasks ("
					.. vim.fn.fnamemodify(root, ":t")
					.. ") | [d]=Default [a]=Add [e]=Edit [c]=Chain [x]=Delete ",
				finder = finders.new_table({
					results = entries,
					entry_maker = function(entry)
						local chain_tag = entry.steps_count > 1 and string.format(" 🔗 [%d steps]", entry.steps_count) or ""
						local tag = is_default_entry(entry, default_task) and " ⭐ [DEFAULT]"
							or (" [" .. entry.source .. "]" .. chain_tag)
						local display = entry.name .. tag
						return { value = entry, display = display, ordinal = display .. " " .. entry.name }
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					--- Selection under the cursor, or nil.
					local function selected()
						local selection = action_state.get_selected_entry()
						return selection and selection.value or nil
					end

					--- Persists `pdata` and reopens the menu so it shows the new state.
					local function save_and_reopen()
						M.save_project_data(root, pdata)
						actions.close(prompt_bufnr)
						vim.schedule(M.open_task_menu)
					end

					--- Binds single-letter shortcuts in normal mode only, and Ctrl-key mirrors in insert mode
					local function map_action(norm_key, ctrl_key, fn)
						map("n", norm_key, fn)
						if ctrl_key then
							map({ "n", "i" }, ctrl_key, fn)
						end
					end

					actions.select_default:replace(function()
						local value = selected()
						actions.close(prompt_bufnr)
						if value then
							M.run_task_item(value.item, root)
						end
					end)

					local action_default = function()
						local value = selected()
						if value then
							pdata.default_task = value.item
							save_and_reopen()
							notify("⭐ Default task saved")
						end
					end

					local action_add = function()
						actions.close(prompt_bufnr)
						vim.schedule(function()
							vim.ui.input({ prompt = "New Task Command: " }, function(cmd)
								if cmd and cmd ~= "" then
									pdata.custom_tasks = pdata.custom_tasks or {}
									table.insert(pdata.custom_tasks, { name = cmd, cmd = cmd })
									M.save_project_data(root, pdata)
									M.open_task_menu()
								end
							end)
						end)
					end

					local action_edit = function()
						local value = selected()
						if not value then
							return
						end

						actions.close(prompt_bufnr)
						vim.schedule(function()
							local initial_name = value.name
							local item = type(value.item) == "table" and value.item or { name = value.name, cmd = value.item }

							vim.ui.input({ prompt = "Edit Task Name: ", default = initial_name }, function(new_name)
								if not new_name or new_name == "" then
									return
								end

								if type(item) == "table" and item.chain then
									local default_chain = table.concat(item.chain, " && ")
									vim.ui.input(
										{ prompt = "Edit Chained Steps (separated by '&&' or ','): ", default = default_chain },
										function(raw_steps)
											if not raw_steps or raw_steps == "" then
												return
											end

											local steps = {}
											for step in raw_steps:gmatch("[^&,]+") do
												local clean = vim.trim(step)
												if clean ~= "" then
													table.insert(steps, clean)
												end
											end

											if #steps > 0 then
												pdata.custom_tasks = pdata.custom_tasks or {}
												local updated = false
												for idx, ct in ipairs(pdata.custom_tasks) do
													if ct == item or ct.name == initial_name then
														pdata.custom_tasks[idx] = { name = new_name, chain = steps }
														updated = true
														break
													end
												end
												if not updated then
													table.insert(pdata.custom_tasks, { name = new_name, chain = steps })
												end
												M.save_project_data(root, pdata)
												notify("✏️ Task chain updated: " .. new_name)
											end
											M.open_task_menu()
										end
									)
								else
									local default_cmd = (type(item) == "table" and item.cmd)
										or (type(item) == "string" and item)
										or initial_name
									vim.ui.input({ prompt = "Edit Command: ", default = default_cmd }, function(new_cmd)
										if not new_cmd or new_cmd == "" then
											return
										end

										pdata.custom_tasks = pdata.custom_tasks or {}
										local updated = false
										for idx, ct in ipairs(pdata.custom_tasks) do
											if ct == item or ct.name == initial_name then
												pdata.custom_tasks[idx] = { name = new_name, cmd = new_cmd }
												updated = true
												break
											end
										end
										if not updated then
											table.insert(pdata.custom_tasks, { name = new_name, cmd = new_cmd })
										end

										if is_default_entry(value, pdata.default_task) then
											pdata.default_task = { name = new_name, cmd = new_cmd }
										end

										M.save_project_data(root, pdata)
										notify("✏️ Task updated: " .. new_name)
										M.open_task_menu()
									end)
								end
							end)
						end)
					end

					local action_chain = function()
						actions.close(prompt_bufnr)
						vim.schedule(function()
							vim.ui.input({ prompt = "Chain Name (e.g. Build & Test): " }, function(chain_name)
								if not chain_name or chain_name == "" then
									return
								end
								vim.ui.input({ prompt = "Chained steps (separated by '&&' or ','): " }, function(raw_steps)
									if not raw_steps or raw_steps == "" then
										return
									end

									local steps = {}
									for step in raw_steps:gmatch("[^&,]+") do
										local clean = vim.trim(step)
										if clean ~= "" then
											table.insert(steps, clean)
										end
									end

									if #steps > 0 then
										pdata.custom_tasks = pdata.custom_tasks or {}
										table.insert(pdata.custom_tasks, { name = chain_name, chain = steps })
										M.save_project_data(root, pdata)
										notify("🔗 Task chain saved: " .. chain_name .. " (" .. #steps .. " steps)")
									end
									M.open_task_menu()
								end)
							end)
						end)
					end

					local action_delete = function()
						local value = selected()
						if not value then
							return
						end

						if pdata.default_task == value.item then
							pdata.default_task = nil
						end
						if pdata.custom_tasks then
							local kept = {}
							for _, ct in ipairs(pdata.custom_tasks) do
								if ct ~= value.item and ct.name ~= value.name then
									table.insert(kept, ct)
								end
							end
							pdata.custom_tasks = kept
						end
						save_and_reopen()
					end

					map_action("d", "<C-d>", action_default)
					map_action("a", "<C-a>", action_add)
					map_action("e", "<C-e>", action_edit)
					map("n", "r", action_edit)
					map_action("c", "<C-c>", action_chain)
					map_action("x", "<C-x>", action_delete)

					return true
				end,
			}),
			{}
		)
		:find()
end

-- ============================================================================
-- SETUP -- user commands and keymaps
-- ============================================================================

--- Registers `:TaskRunner`, `:TaskMenu`, `:TaskRestart`, `:TaskKill`,
--- `:TaskRunDefault` and every keymap from `M.settings.keys`.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local commands = {
		TaskRunner = { M.open_task_menu, "Open KRS Project Task Runner" },
		TaskMenu = { M.open_task_menu, "Open KRS Project Task Runner" },
		TaskRestart = {
			function()
				M.restart_task()
			end,
			"Kill and restart active project task",
		},
		TaskKill = {
			function()
				M.stop_task()
			end,
			"Kill active project task",
		},
		TaskRunDefault = { M.run_default_or_menu, "Run default project task" },
	}
	for name, spec in pairs(commands) do
		vim.api.nvim_create_user_command(name, spec[1], { desc = spec[2] })
	end

	--- Leaves terminal mode first, so the mapping works from inside a task output.
	local function from_any_mode(fn)
		return function()
			local mode = vim.fn.mode()
			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			fn()
		end
	end

	for _, key in ipairs(M.settings.keys.menu) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.open_task_menu), {
			noremap = true,
			silent = true,
			desc = "Open Project Task Menu",
		})
	end

	local run_def_keys = type(M.settings.keys.run_default) == "table" and M.settings.keys.run_default
		or { M.settings.keys.run_default }
	for _, key in ipairs(run_def_keys) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.run_default_or_menu), {
			noremap = true,
			silent = true,
			desc = "Run Default Project Task / Profile",
		})
	end
	vim.keymap.set("n", M.settings.keys.menu_fkey, M.open_task_menu, {
		noremap = true,
		silent = true,
		desc = "Open Project Task Menu",
	})

	for i = 1, M.settings.max_slots do
		vim.keymap.set(
			{ "n", "i", "t" },
			M.settings.keys.slot_prefix .. i .. ">",
			from_any_mode(function()
				M.toggle_slot_window(i)
			end),
			{ noremap = true, silent = true, desc = "Toggle Task Slot #" .. i }
		)
	end

	-- These collide with <Esc> in terminal buffers, so they are dropped globally
	-- and re-bound per task buffer instead (see bind_task_buffer_keys).
	for _, mode in ipairs({ "n", "i", "v", "t" }) do
		for _, key in ipairs(M.settings.keys.unbind) do
			pcall(vim.keymap.del, mode, key)
		end
	end

	for _, key in ipairs(M.settings.keys.toggle_last) do
		vim.keymap.set({ "n", "i", "v", "t" }, key, from_any_mode(M.toggle_last_slot_window), {
			noremap = true,
			silent = true,
			desc = "Toggle Last Task Slot Window",
		})
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.ProjectTasks = M

-- ============================================================================
-- LAZY.NVIM SPEC -- `__index` exposes the module through `require`
-- ============================================================================

return setmetatable({
	name = "krs_tasks",
	dir = require("krs.core.lazyspec").for_module(),
	cmd = { "TaskMenu", "TaskRunner", "TaskRestart", "TaskKill", "TaskRunDefault" },
	keys = {
		{ "<C-S-t>", mode = { "n", "i", "v", "t" }, desc = "Project Task Menu" },
		{ "<C-S-a>", mode = { "n", "i", "v", "t" }, desc = "Run Default Project Task" },
		{ "<C-S-A>", mode = { "n", "i", "v", "t" }, desc = "Run Default Project Task" },
		{ "<C-A>", mode = { "n", "i", "v", "t" }, desc = "Run Default Project Task" },
		{ "<C-S-e>", mode = { "n", "i", "v", "t" }, desc = "Restart Active Task" },
		{ "<leader>tm", mode = { "n", "i" }, desc = "Project Task Menu (Leader)" },
	},
	dependencies = { "nvim-telescope/telescope.nvim" },
	config = function()
		M.setup()
	end,
}, { __index = M })
