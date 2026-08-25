local M = {}

function M.run()
	local async = require("krsnvim.async")
	local krsnvim = require("krsnvim")

	print("  ⚡ Running krsnvim.async deep testing suite...")

	-- 1. Real Async Task (Promise-like) with delayed resolution
	local promise_resolved = false
	local promise_val = nil
	local async_task = async.task(function(resolve, reject)
		async.sleep(20, function()
			resolve("real_promise_data_42")
		end)
	end)

	async_task:next(function(val)
		promise_resolved = true
		promise_val = val
	end)

	-- 2. Real Async/Await in managed coroutine
	local await_done = false
	local await_result = nil
	async.run(function()
		local t = async.task(function(resolve)
			async.sleep(30, function()
				resolve("awaited_coroutine_value")
			end)
		end)
		await_result = async.await(t)
		await_done = true
	end)

	-- 3. Heavy CPU Task offloaded to OS worker thread
	local heavy_thread_done = false
	local heavy_result = nil
	async.thread(function(iterations)
		local sum = 0
		for i = 1, iterations do
			sum = sum + (i % 7)
		end
		return sum
	end, { 5000000 }, function(err, res)
		assert(err == nil, "Heavy worker thread failed: " .. tostring(err))
		heavy_result = res
		heavy_thread_done = true
	end)

	-- 4. Multitasks: Running multiple async timers, worker threads, and promises concurrently
	local multitasks_done = false
	local multitask_results = nil
	async.parallel({
		-- Task 1: Async delay task
		function()
			async.sleep(40)
			return "timer_task_A"
		end,
		-- Task 2: Shorter async delay task
		function()
			async.sleep(15)
			return "timer_task_B"
		end,
		-- Task 3: OS Worker Thread execution
		{
			thread = true,
			fn = function(n)
				local total = 0
				for i = 1, n do
					total = total + i
				end
				return total
			end,
			args = { 100000 },
		},
		-- Task 4: Real Task Promise
		async.task(function(resolve)
			async.sleep(25, function()
				resolve("promise_task_C")
			end)
		end),
	}, function(err, results)
		assert(err == nil, "Multitasks execution failed: " .. tostring(err))
		multitask_results = results
		multitasks_done = true
	end)

	-- 5. Multi-producer / Multi-consumer Async Channel with Delayed Messages
	local chan = async.channel()
	local chan_received = {}
	async.run(function()
		async.sleep(10)
		chan:send("msg_alpha")
		async.sleep(10)
		chan:send("msg_beta")
	end)

	async.run(function()
		table.insert(chan_received, async.await(chan:receive()))
		table.insert(chan_received, async.await(chan:receive()))
	end)

	-- 6. JS-style Timers: setTimeout, clearTimeout, setInterval, clearInterval
	local timeout_fired = false
	local timeout_arg = nil
	local timeout_id = setTimeout(function(arg)
		timeout_fired = true
		timeout_arg = arg
	end, 15, "test_arg")

	local cleared_timeout_fired = false
	local cleared_id = setTimeout(function()
		cleared_timeout_fired = true
	end, 20)
	clearTimeout(cleared_id)

	local interval_ticks = 0
	local interval_id = setInterval(function()
		interval_ticks = interval_ticks + 1
		if interval_ticks >= 3 then
			clearInterval(interval_id)
		end
	end, 10)

	-- Wait for all async promises, heavy threads, multitasks, and JS timers to complete
	local ok = vim.wait(3000, function()
		return promise_resolved
			and await_done
			and heavy_thread_done
			and multitasks_done
			and #chan_received == 2
			and timeout_fired
			and interval_ticks >= 3
	end, 10)

	assert(ok, "Async operations timed out after 3000ms")

	-- Assertions on asynchronous results
	assert(promise_resolved == true, "Real promise task resolved")
	assert(promise_val == "real_promise_data_42", "Promise task value matches")

	assert(await_done == true, "Async/await coroutine finished")
	assert(await_result == "awaited_coroutine_value", "Async/await result matches")

	assert(heavy_thread_done == true, "Heavy OS worker thread finished")
	assert(type(heavy_result) == "number" and heavy_result > 0, "Heavy CPU worker thread result valid")

	assert(multitasks_done == true, "Multitasks completed concurrently")
	assert(multitask_results[1] == "timer_task_A", "Multitask index 1 matches")
	assert(multitask_results[2] == "timer_task_B", "Multitask index 2 matches")
	assert(multitask_results[3] == 5000050000, "Multitask OS thread sum matches")
	assert(multitask_results[4] == "promise_task_C", "Multitask promise matches")

	assert(#chan_received == 2, "Channel received both async messages")
	assert(chan_received[1] == "msg_alpha" and chan_received[2] == "msg_beta", "Channel message order matches")

	assert(timeout_fired == true, "setTimeout fired successfully")
	assert(timeout_arg == "test_arg", "setTimeout passed extra arguments correctly")
	assert(cleared_timeout_fired == false, "clearTimeout cancelled timer successfully")
	assert(interval_ticks >= 3, "setInterval fired multiple times")

	print("  ✅ async_spec (real tasks, heavy threads, multitasks, setTimeout/setInterval) passed")
end

return M
