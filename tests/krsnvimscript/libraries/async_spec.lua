-- ============================================================================
-- tests/krsnvimscript/libraries/async_spec.lua -- Spec tests for krsnvim.async module
-- ============================================================================
local t = require("krsnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local async = require("krsnvim.async")

describe("krsnvim.async module", function()
	it("exposes concurrency, parallelism, and async primitives", function()
		expect(type(async)).toBe("table")
		expect(type(async.parallel)).toBe("function")
		expect(type(async.race)).toBe("function")
		expect(type(async.thread)).toBe("function")
		expect(type(async.map)).toBe("function")
		expect(type(async.series)).toBe("function")
		expect(type(async.waterfall)).toBe("function")
		expect(type(async.sleep)).toBe("function")
		expect(type(async.run)).toBe("function")
		expect(type(async.channel)).toBe("function")
	end)

	it("executes real asynchronous tasks (Promises) with delayed resolution", function()
		local resolved_val = nil
		local task = async.task(function(resolve)
			async.sleep(20, function()
				resolve("deferred_val_99")
			end)
		end)
		task:next(function(val)
			resolved_val = val
		end)
		vim.wait(100, function()
			return resolved_val ~= nil
		end, 10)
		expect(resolved_val).toBe("deferred_val_99")
	end)

	it("runs heavy CPU computation on OS background worker threads", function()
		local finished = false
		local calculated_sum = nil
		async.thread(function(n)
			local sum = 0
			for i = 1, n do
				sum = sum + i
			end
			return sum
		end, { 2000000 }, function(err, result)
			calculated_sum = result
			finished = true
		end)
		vim.wait(2000, function()
			return finished
		end, 10)
		expect(finished).toBe(true)
		expect(calculated_sum).toBe(2000001000000)
	end)

	it("executes multitasks concurrently (timers, threads, promises in parallel)", function()
		local done = false
		local multi_res = nil
		async.parallel({
			function()
				async.sleep(20)
				return "task_1"
			end,
			{
				thread = true,
				fn = function(a, b)
					return a + b
				end,
				args = { 300, 400 },
			},
			async.task(function(resolve)
				async.sleep(10, function()
					resolve("task_3")
				end)
			end),
		}, function(err, results)
			multi_res = results
			done = true
		end)

		vim.wait(2000, function()
			return done
		end, 10)
		expect(done).toBe(true)
		expect(multi_res[1]).toBe("task_1")
		expect(multi_res[2]).toBe(700)
		expect(multi_res[3]).toBe("task_3")
	end)

	it("supports channel send and receive across async tasks", function()
		local ch = async.channel()
		local msg_received = nil
		async.run(function()
			async.sleep(15)
			ch:send("delayed_channel_message")
		end)
		async.run(function()
			msg_received = async.await(ch:receive())
		end)

		vim.wait(1000, function()
			return msg_received ~= nil
		end, 10)
		expect(msg_received).toBe("delayed_channel_message")
		ch:close()
		expect(ch.closed).toBe(true)
	end)
end)
