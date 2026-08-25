--- @module "krsnvim.async"
--- Concurrency, Async/Await, and Multi-Threading Parallelism suite for `krsnvimscript`.
--- Provides a modern, rich API for running tasks concurrently, offloading work to background OS threads,
--- non-blocking timers/sleep, channels, waterfall pipelines, and JavaScript/Go-style async primitives.
---
--- @example
--- local async = import("async")
---
--- -- 1. Concurrent task execution:
--- async.parallel({
---   function() async.sleep(100); return "task 1" end,
---   function() async.sleep(50); return "task 2" end
--- }, function(err, results)
---   print(results[1], results[2])
--- end)
---
--- -- 2. True OS Worker Thread Parallelism:
--- async.thread(function(n)
---   local sum = 0
---   for i = 1, n do sum = sum + i end
---   return sum
--- end, { 1000000 }, function(err, total)
---   print("Parallel Sum:", total)
--- end)

local M = {}

local uv = vim.uv or vim.loop

--- @class Task
--- Representation of an asynchronous operation (Promise-like).
--- @field status string "pending" | "fulfilled" | "rejected"
--- @field value any Result or error value
--- @field callbacks table List of registered handlers
local Task = {}
Task.__index = Task

--- Constructs a new `Task` / Promise.
--- @param executor function(resolve, reject)
--- @return Task
function Task.new(executor)
	local self = setmetatable({
		status = "pending",
		value = nil,
		callbacks = {},
	}, Task)

	local function resolve(val)
		if self.status ~= "pending" then
			return
		end
		self.status = "fulfilled"
		self.value = val
		for _, cb in ipairs(self.callbacks) do
			if cb.on_fulfilled then
				vim.schedule(function()
					local ok, res = pcall(cb.on_fulfilled, val)
					if ok then
						if cb.resolve then
							cb.resolve(res)
						end
					else
						if cb.reject then
							cb.reject(res)
						end
					end
				end)
			elseif cb.resolve then
				cb.resolve(val)
			end
		end
		self.callbacks = {}
	end

	local function reject(err)
		if self.status ~= "pending" then
			return
		end
		self.status = "rejected"
		self.value = err
		for _, cb in ipairs(self.callbacks) do
			if cb.on_rejected then
				vim.schedule(function()
					local ok, res = pcall(cb.on_rejected, err)
					if ok then
						if cb.resolve then
							cb.resolve(res)
						end
					else
						if cb.reject then
							cb.reject(res)
						end
					end
				end)
			elseif cb.reject then
				cb.reject(err)
			end
		end
		self.callbacks = {}
	end

	if type(executor) == "function" then
		local ok, err = pcall(executor, resolve, reject)
		if not ok then
			reject(err)
		end
	end

	return self
end

--- Attaches callbacks for the resolution or rejection of the Task.
--- @param on_fulfilled function|nil Called when task completes successfully
--- @param on_rejected function|nil Called when task fails with error
--- @return Task
Task["then"] = function(self, on_fulfilled, on_rejected)
	return Task.new(function(resolve, reject)
		if self.status == "fulfilled" then
			if on_fulfilled then
				local ok, res = pcall(on_fulfilled, self.value)
				if ok then
					resolve(res)
				else
					reject(res)
				end
			else
				resolve(self.value)
			end
		elseif self.status == "rejected" then
			if on_rejected then
				local ok, res = pcall(on_rejected, self.value)
				if ok then
					resolve(res)
				else
					reject(res)
				end
			else
				reject(self.value)
			end
		else
			table.insert(self.callbacks, {
				on_fulfilled = on_fulfilled,
				on_rejected = on_rejected,
				resolve = resolve,
				reject = reject,
			})
		end
	end)
end
Task.next = Task["then"]

--- Attaches a rejection callback to the Task.
--- @param on_rejected function
--- @return Task
function Task:catch(on_rejected)
	return self["then"](self, nil, on_rejected)
end

--- Waits synchronously inside an `async.run()` coroutine for the Task to settle.
--- @return any Result of the Task
function Task:await()
	if self.status == "fulfilled" then
		return self.value
	elseif self.status == "rejected" then
		error(self.value)
	end

	local co, is_main = coroutine.running()
	if not co or is_main then
		error("Task:await() must be called inside an async.run() coroutine or use :next() / ['then']")
	end

	local err_out, res_out
	local done = false

	self["then"](self, function(res)
		res_out = res
		done = true
		if coroutine.status(co) == "suspended" then
			vim.schedule(function()
				local ok, err = coroutine.resume(co, nil, res)
				if not ok then
					error(err)
				end
			end)
		end
	end, function(err)
		err_out = err
		done = true
		if coroutine.status(co) == "suspended" then
			vim.schedule(function()
				local ok, resume_err = coroutine.resume(co, err, nil)
				if not ok then
					error(resume_err)
				end
			end)
		end
	end)

	if not done then
		local err, res = coroutine.yield()
		if err then
			error(err)
		end
		return res
	else
		if err_out then
			error(err_out)
		end
		return res_out
	end
end

M.Task = Task

--- Creates a new `Task` object wrapper around an executor function.
--- @param fn function(resolve, reject)
--- @return Task
function M.task(fn)
	return Task.new(fn)
end

--- Pauses execution for `ms` milliseconds without blocking Neovim's main loop.
--- If called inside `async.run()`, yields the coroutine non-blockingly.
--- If a callback function is passed, calls callback(nil) after `ms` milliseconds.
--- @param ms number Duration in milliseconds
--- @param cb function|nil Optional completion callback
--- @return Task|nil
function M.sleep(ms, cb)
	ms = tonumber(ms) or 0
	if cb and type(cb) == "function" then
		local timer = uv.new_timer()
		timer:start(ms, 0, function()
			timer:stop()
			timer:close()
			vim.schedule(function()
				cb(nil)
			end)
		end)
		return
	end

	local co, is_main = coroutine.running()
	if co and not is_main then
		local timer = uv.new_timer()
		timer:start(ms, 0, function()
			timer:stop()
			timer:close()
			vim.schedule(function()
				if coroutine.status(co) == "suspended" then
					local ok, err = coroutine.resume(co)
					if not ok then
						error(err)
					end
				end
			end)
		end)
		coroutine.yield()
	else
		return Task.new(function(resolve)
			local timer = uv.new_timer()
			timer:start(ms, 0, function()
				timer:stop()
				timer:close()
				vim.schedule(resolve)
			end)
		end)
	end
end
M.delay = M.sleep

--- Runs a function inside a managed coroutine allowing non-blocking await calls.
--- @param fn function Function to execute asynchronously
--- @return Task
function M.run(fn, ...)
	local args = { ... }
	return Task.new(function(resolve, reject)
		local co = coroutine.create(function()
			local ok, res = pcall(fn, unpack(args))
			if ok then
				resolve(res)
			else
				reject(res)
			end
		end)
		local ok, err = coroutine.resume(co)
		if not ok then
			reject(err)
		end
	end)
end
M.spawn = M.run

--- Awaits a Task, promise, or async function inside an `async.run()` coroutine.
--- @param task_or_fn Task|function
--- @return any
function M.await(task_or_fn)
	if type(task_or_fn) == "function" then
		task_or_fn = M.run(task_or_fn)
	end
	if type(task_or_fn) == "table" and type(task_or_fn.await) == "function" then
		return task_or_fn:await()
	end
	return task_or_fn
end

--- Executes multiple tasks concurrently and collects their results in an array.
--- Order of elements in the returned array matches the input order of tasks.
---
--- @param tasks table[] List of functions, Tasks, or worker thread definitions `{ fn = func, args = {...}, thread = true }`
--- @param callback function|nil Callback `function(err, results)`
--- @return Task
function M.parallel(tasks, callback)
	if type(tasks) ~= "table" then
		error("async.parallel: tasks must be an array table")
	end

	local task_obj = Task.new(function(resolve, reject)
		local total = #tasks
		if total == 0 then
			resolve({})
			return
		end

		local results = {}
		local completed = 0
		local has_errored = false

		for i, task_def in ipairs(tasks) do
			local function on_complete(err, res)
				if has_errored then
					return
				end
				if err then
					has_errored = true
					reject(err)
					return
				end
				results[i] = res
				completed = completed + 1
				if completed == total then
					resolve(results)
				end
			end

			if has_errored then
				break
			end
			if type(task_def) == "function" then
				local co = coroutine.create(function()
					local ok, res = pcall(task_def)
					if ok then
						on_complete(nil, res)
					else
						on_complete(res or "Task execution error", nil)
					end
				end)
				local ok, err = coroutine.resume(co)
				if not ok then
					on_complete(err, nil)
				end
			elseif type(task_def) == "table" and task_def.thread then
				M.thread(task_def.fn, task_def.args or {}, on_complete)
			elseif type(task_def) == "table" and type(task_def["then"]) == "function" then
				task_def["then"](task_def, function(res)
					on_complete(nil, res)
				end, function(err)
					on_complete(err, nil)
				end)
			else
				on_complete(nil, task_def)
			end
		end
	end)

	if callback and type(callback) == "function" then
		task_obj["then"](task_obj, function(res)
			callback(nil, res)
		end, function(err)
			callback(err, nil)
		end)
	end

	local co, is_main = coroutine.running()
	if co and not is_main and not callback then
		return task_obj:await()
	end

	return task_obj
end
M.all = M.parallel

--- Executes multiple tasks concurrently and resolves with the result of the FIRST task to complete.
--- @param tasks table[] List of functions or Tasks
--- @param callback function|nil Callback `function(err, first_result)`
--- @return Task
function M.race(tasks, callback)
	if type(tasks) ~= "table" then
		error("async.race: tasks must be an array table")
	end

	local task_obj = Task.new(function(resolve, reject)
		local finished = false
		for _, task_def in ipairs(tasks) do
			local function on_complete(err, res)
				if finished then
					return
				end
				finished = true
				if err then
					reject(err)
				else
					resolve(res)
				end
			end

			if finished then
				break
			end
			if type(task_def) == "function" then
				local ok, res = pcall(task_def)
				if ok then
					on_complete(nil, res)
				else
					on_complete(res, nil)
				end
			elseif type(task_def) == "table" and task_def.thread then
				M.thread(task_def.fn, task_def.args or {}, on_complete)
			elseif type(task_def) == "table" and type(task_def["then"]) == "function" then
				task_def["then"](task_def, function(res)
					on_complete(nil, res)
				end, function(err)
					on_complete(err, nil)
				end)
			else
				on_complete(nil, task_def)
			end
		end
	end)

	if callback and type(callback) == "function" then
		task_obj["then"](task_obj, function(res)
			callback(nil, res)
		end, function(err)
			callback(err, nil)
		end)
	end

	local co, is_main = coroutine.running()
	if co and not is_main and not callback then
		return task_obj:await()
	end

	return task_obj
end

--- Executes a function on a background OS worker thread using `vim.uv.new_work`.
--- Enables true OS-level parallelism for CPU-heavy tasks without freezing Neovim's UI thread.
---
--- @param fn function Heavy worker function (must be self-contained)
--- @param args table Arguments to pass to worker function
--- @param callback function|nil Callback `function(err, ...)` called on main thread when worker finishes
--- @return Task
function M.thread(fn, args, callback)
	if type(fn) ~= "function" then
		error("async.thread: fn must be a function")
	end
	args = args or {}
	if type(args) ~= "table" then
		args = { args }
	end

	local task_obj = Task.new(function(resolve, reject)
		local work, err = uv.new_work(fn, function(...)
			local results = { ... }
			vim.schedule(function()
				resolve(unpack(results))
			end)
		end)

		if not work then
			reject("Failed to create worker thread: " .. tostring(err))
			return
		end

		work:queue(unpack(args))
	end)

	if callback and type(callback) == "function" then
		task_obj["then"](task_obj, function(...)
			callback(nil, ...)
		end, function(err)
			callback(err, nil)
		end)
	end

	local co, is_main = coroutine.running()
	if co and not is_main and not callback then
		return task_obj:await()
	end

	return task_obj
end

--- Maps over an array of items concurrently with optional concurrency limit.
--- @param items table Array of items
--- @param worker_fn function(item, index) Worker function returning result
--- @param opts table|function|nil Options table `{ concurrency = number }` or callback
--- @param callback function|nil Callback `function(err, mapped_results)`
--- @return Task
function M.map(items, worker_fn, opts, callback)
	if type(opts) == "function" then
		callback = opts
		opts = {}
	end
	opts = opts or {}
	local concurrency = opts.concurrency or #items
	if concurrency <= 0 then
		concurrency = 1
	end

	local tasks = {}
	for idx, item in ipairs(items) do
		table.insert(tasks, function()
			return worker_fn(item, idx)
		end)
	end

	local task_obj = Task.new(function(resolve, reject)
		local total = #tasks
		if total == 0 then
			resolve({})
			return
		end

		local results = {}
		local index = 1
		local completed = 0
		local has_errored = false

		local function launch_next()
			if has_errored then
				return
			end
			if index > total then
				return
			end

			local cur_idx = index
			local cur_task = tasks[cur_idx]
			index = index + 1

			local co = coroutine.create(function()
				local ok, res = pcall(cur_task)
				if ok then
					results[cur_idx] = res
					completed = completed + 1
					if completed == total then
						resolve(results)
					else
						launch_next()
					end
				else
					has_errored = true
					reject(res or "Error in worker task")
				end
			end)
			coroutine.resume(co)
		end

		local active_count = math.min(concurrency, total)
		for _ = 1, active_count do
			launch_next()
		end
	end)

	if callback and type(callback) == "function" then
		task_obj["then"](task_obj, function(res)
			callback(nil, res)
		end, function(err)
			callback(err, nil)
		end)
	end

	local co, is_main = coroutine.running()
	if co and not is_main and not callback then
		return task_obj:await()
	end

	return task_obj
end
M.parallel_map = M.map

--- Executes tasks sequentially in series.
--- @param tasks table[] List of functions
--- @param callback function|nil Callback `function(err, results)`
--- @return Task
function M.series(tasks, callback)
	local task_obj = Task.new(function(resolve, reject)
		local results = {}
		local index = 1
		local total = #tasks

		local function step()
			if index > total then
				resolve(results)
				return
			end
			local cur_idx = index
			local cur_task = tasks[cur_idx]
			index = index + 1

			local co = coroutine.create(function()
				local ok, res = pcall(cur_task)
				if ok then
					results[cur_idx] = res
					step()
				else
					reject(res or "Error in series task")
				end
			end)
			coroutine.resume(co)
		end

		step()
	end)

	if callback and type(callback) == "function" then
		task_obj["then"](task_obj, function(res)
			callback(nil, res)
		end, function(err)
			callback(err, nil)
		end)
	end

	local co, is_main = coroutine.running()
	if co and not is_main and not callback then
		return task_obj:await()
	end

	return task_obj
end

--- Executes tasks in series, passing the output of each task as arguments to the next task.
--- @param tasks table[] List of functions
--- @param callback function|nil Callback `function(err, final_result)`
--- @return Task
function M.waterfall(tasks, callback)
	local task_obj = Task.new(function(resolve, reject)
		local index = 1
		local total = #tasks

		local function step(...)
			local current_args = { ... }
			if index > total then
				resolve(unpack(current_args))
				return
			end
			local cur_task = tasks[index]
			index = index + 1

			local co = coroutine.create(function()
				local ok, res = pcall(cur_task, unpack(current_args))
				if ok then
					if type(res) == "table" and type(res["then"]) == "function" then
						res["then"](res, function(val)
							step(val)
						end, function(err)
							reject(err)
						end)
					else
						step(res)
					end
				else
					reject(res or "Error in waterfall task")
				end
			end)
			coroutine.resume(co)
		end

		step()
	end)

	if callback and type(callback) == "function" then
		task_obj["then"](task_obj, function(...)
			callback(nil, ...)
		end, function(err)
			callback(err, nil)
		end)
	end

	local co, is_main = coroutine.running()
	if co and not is_main and not callback then
		return task_obj:await()
	end

	return task_obj
end

--- @class Channel
--- Thread-safe / Coroutine-safe Async Channel for producer-consumer messaging.
local Channel = {}
Channel.__index = Channel

--- Creates a new async Channel with optional capacity.
--- @param capacity number|nil Maximum buffered messages (defaults to unbuffered / infinite)
--- @return Channel
function M.channel(capacity)
	return setmetatable({
		queue = {},
		waiters = {},
		capacity = capacity or math.huge,
		closed = false,
	}, Channel)
end

--- Sends a message to the Channel.
--- @param val any Value to send
function Channel:send(val)
	if self.closed then
		error("Cannot send on closed channel")
	end

	if #self.waiters > 0 then
		local waiter = table.remove(self.waiters, 1)
		vim.schedule(function()
			waiter(nil, val)
		end)
	else
		table.insert(self.queue, val)
	end
end

--- Receives a message from the Channel.
--- If called inside `async.run()`, yields until a message is received.
--- If `cb` callback is provided, calls `cb(err, val)`.
--- @param cb function|nil Callback
--- @return any
function Channel:receive(cb)
	if #self.queue > 0 then
		local val = table.remove(self.queue, 1)
		if cb and type(cb) == "function" then
			cb(nil, val)
			return
		end
		return val
	end

	if self.closed then
		if cb and type(cb) == "function" then
			cb("Channel closed", nil)
			return
		end
		return nil, "Channel closed"
	end

	if cb and type(cb) == "function" then
		table.insert(self.waiters, cb)
		return
	end

	local co, is_main = coroutine.running()
	if co and not is_main then
		table.insert(self.waiters, function(err, val)
			if coroutine.status(co) == "suspended" then
				local ok, resume_err = coroutine.resume(co, err, val)
				if not ok then
					error(resume_err)
				end
			end
		end)
		local err, val = coroutine.yield()
		if err then
			error(err)
		end
		return val
	else
		error("Channel:receive() requires callback or must be called inside async.run()")
	end
end

--- Closes the channel.
function Channel:close()
	self.closed = true
	for _, waiter in ipairs(self.waiters) do
		vim.schedule(function()
			waiter("Channel closed", nil)
		end)
	end
	self.waiters = {}
end

-- ---------------------------------------------------------------------------
-- JavaScript-style Global Timers (setTimeout, clearTimeout, setInterval, clearInterval)
-- ---------------------------------------------------------------------------

local next_timer_id = 1
local active_timers = {}

--- Schedules execution of a function after `ms` milliseconds.
--- @param callback function Function to execute
--- @param ms number|nil Delay in milliseconds (defaults to 0)
--- @param ... any Arguments to pass to callback
--- @return number id Timer ID handle
function M.setTimeout(callback, ms, ...)
	if type(callback) ~= "function" then
		error("setTimeout: first argument must be a function")
	end
	ms = tonumber(ms) or 0
	if ms < 0 then
		ms = 0
	end
	local args = { ... }
	local timer = uv.new_timer()
	local id = next_timer_id
	next_timer_id = next_timer_id + 1

	active_timers[id] = timer

	timer:start(
		ms,
		0,
		vim.schedule_wrap(function()
			active_timers[id] = nil
			if timer and not timer:is_closing() then
				timer:stop()
				timer:close()
			end
			callback(unpack(args))
		end)
	)

	return id
end

--- Cancels a timer created by `setTimeout`.
--- @param id number|table|nil Timer ID returned by `setTimeout`
function M.clearTimeout(id)
	if not id then
		return
	end
	local timer = active_timers[id]
	if timer then
		active_timers[id] = nil
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	elseif type(id) == "userdata" or (type(id) == "table" and type(id.stop) == "function") then
		pcall(function()
			if not id:is_closing() then
				id:stop()
				id:close()
			end
		end)
	end
end

--- Repeatedly calls a function with a fixed time delay between each call.
--- @param callback function Function to execute
--- @param ms number|nil Delay in milliseconds (defaults to 1)
--- @param ... any Arguments to pass to callback
--- @return number id Interval ID handle
function M.setInterval(callback, ms, ...)
	if type(callback) ~= "function" then
		error("setInterval: first argument must be a function")
	end
	ms = tonumber(ms) or 1
	if ms < 1 then
		ms = 1
	end
	local args = { ... }
	local timer = uv.new_timer()
	local id = next_timer_id
	next_timer_id = next_timer_id + 1

	active_timers[id] = timer

	timer:start(
		ms,
		ms,
		vim.schedule_wrap(function()
			if active_timers[id] then
				callback(unpack(args))
			end
		end)
	)

	return id
end

--- Cancels a repeating timer created by `setInterval`.
--- @param id number|table|nil Interval ID returned by `setInterval`
function M.clearInterval(id)
	M.clearTimeout(id)
end

-- Export global JS-style timer functions on _G
_G.setTimeout = M.setTimeout
_G.clearTimeout = M.clearTimeout
_G.setInterval = M.setInterval
_G.clearInterval = M.clearInterval

return M
