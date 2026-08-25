local M = {}

function M.run()
	local transpiler = require("krsnvim.krsnvimtranspiler")

	-- Test 1: Function transpilation & parameters
	local fn_code = 'function deploy(target, verbose)\nprint("Deploying:", target)\nend'
	local sh_fn = transpiler.to_sh(fn_code)
	local ps1_fn = transpiler.to_ps1(fn_code)
	assert(sh_fn:find("deploy() {", 1, true), "Bash function declaration missing")
	assert(sh_fn:find('local target="$1"', 1, true), "Bash param $1 missing")
	assert(ps1_fn:find("function deploy($target, $verbose) {", 1, true), "PS1 function declaration missing")

	-- Test 2: Advanced loops (while, for i, ipairs)
	local loop_code = "for i = 1, 5 do\nprint(i)\nend\nfor _, item in ipairs(items) do\nprint(item)\nend"
	local sh_loop = transpiler.to_sh(loop_code)
	local ps1_loop = transpiler.to_ps1(loop_code)
	assert(sh_loop:find("for ((i=1; i<=5; i+=1)); do", 1, true), "Bash numeric for loop missing")
	assert(sh_loop:find('for item in "${items[@]}"; do', 1, true), "Bash ipairs loop missing")
	assert(ps1_loop:find("for ($i = 1; $i -le 5; $i += 1) {", 1, true), "PS1 numeric for loop missing")
	assert(ps1_loop:find("foreach ($item in $items) {", 1, true), "PS1 foreach loop missing")

	-- Test 3: Assertions & Errors
	local err_code = 'assert(fs.exists("config.json"), "Config missing")\nerror("Fatal stop")'
	local sh_err = transpiler.to_sh(err_code)
	local ps1_err = transpiler.to_ps1(err_code)
	assert(
		sh_err:find('[[ -e "config.json" ]] || { echo "Config missing" >&2; exit 1; }', 1, true),
		"Bash assert missing"
	)
	assert(sh_err:find('echo "Fatal stop" >&2', 1, true), "Bash error missing")
	assert(
		ps1_err:find('if (-not ($fs.exists("config.json"))) { throw "Config missing" }', 1, true),
		"PS1 assert missing"
	)
	assert(ps1_err:find('throw "Fatal stop"', 1, true), "PS1 throw missing")

	-- Test 4: User prompt test case with test.afterAll, describe, test, expect, and test.run()
	local user_prompt_code = [[
local test = require("krsnvim.test")

test.afterAll(function()
  console.log("After all functions!")
end)

describe("hola", function()
  test("This is my test!", function()
    expect(234).toBe(234)
  end)
end)

test.run()
]]
	local sh_user = transpiler.to_sh(user_prompt_code)
	local ps1_user = transpiler.to_ps1(user_prompt_code)
	assert(sh_user:find('echo "After all functions!"', 1, true), "User test: Bash console.log in afterAll missing")
	assert(
		not sh_user:find("\nfi\n") and not sh_user:find("\nfi$"),
		"User test: Bash should NOT contain stray standalone fi"
	)
	assert(
		not sh_user:find("\ntest%.run%(") and not sh_user:find("^test%.run%("),
		"User test: Bash should NOT contain un-transpiled test.run()"
	)
	assert(sh_user:find("# [krsnvim] test.run()", 1, true), "User test: Bash test.run comment missing")

	assert(ps1_user:find('Write-Host "After all functions!"', 1, true), "User test: PS1 console.log in afterAll missing")
	assert(
		not ps1_user:find("\ntest%.run%(") and not ps1_user:find("^test%.run%("),
		"User test: PS1 should NOT contain un-transpiled test.run()"
	)
	assert(ps1_user:find("# [krsnvim] test.run()", 1, true), "User test: PS1 test.run comment missing")

	-- Test 5: Lifecycle hooks (beforeAll, afterAll, beforeEach, afterEach) on t/test/global
	local hook_code = [[
test.beforeAll(function()
  print("before all")
end)
t.beforeEach(function()
  print("before each")
end)
afterEach(function()
  print("after each")
end)
]]
	local sh_hooks = transpiler.to_sh(hook_code)
	local ps1_hooks = transpiler.to_ps1(hook_code)
	assert(sh_hooks:find('echo "before all"', 1, true), "Hooks: Bash beforeAll body missing")
	assert(sh_hooks:find('echo "before each"', 1, true), "Hooks: Bash beforeEach body missing")
	assert(sh_hooks:find('echo "after each"', 1, true), "Hooks: Bash afterEach body missing")
	assert(not sh_hooks:find("\nfi\n") and not sh_hooks:find("\nfi$"), "Hooks: Bash stray fi detected")

	assert(ps1_hooks:find('Write-Host "before all"', 1, true), "Hooks: PS1 beforeAll body missing")
	assert(ps1_hooks:find('Write-Host "before each"', 1, true), "Hooks: PS1 beforeEach body missing")
	assert(ps1_hooks:find('Write-Host "after each"', 1, true), "Hooks: PS1 afterEach body missing")

	-- Test 6: Inverted Matchers (.isNot.toBe, .not.toEqual, ["not"].toBe, .not_.toBe)
	local inv_code = [[
expect(10).isNot.toBe(20)
expect("hello")["not"].toBe("world")
expect(val).not_.toEqual(other)
]]
	local sh_inv = transpiler.to_sh(inv_code)
	local ps1_inv = transpiler.to_ps1(inv_code)
	assert(sh_inv:find("== 20", 1, true), "Inverted matcher: Bash equality check missing")
	assert(ps1_inv:find("-eq 20", 1, true), "Inverted matcher: PS1 -eq check missing")

	-- Test 7: Matchers (.toBeTruthy, .toBeFalsy, .toBeNil, .toBeDefined)
	local match_code = [[
expect(val).toBeTruthy()
expect(val).toBeFalsy()
expect(val).toBeNil()
expect(val).toBeDefined()
]]
	local sh_match = transpiler.to_sh(match_code)
	local ps1_match = transpiler.to_ps1(match_code)
	assert(sh_match:find("Expect failed", 1, true), "Matchers: Bash assertion failure output missing")
	assert(ps1_match:find("Write-Error", 1, true), "Matchers: PS1 Write-Error missing")

	-- Test 8: Matchers (.toContain, .toHaveLength, .toBeGreaterThan, .toBeLessThan)
	local match2_code = [[
expect("krsnvimscript").toContain("nvim")
expect(items).toHaveLength(5)
expect(count).toBeGreaterThan(0)
expect(count).toBeLessThan(100)
]]
	local sh_match2 = transpiler.to_sh(match2_code)
	local ps1_match2 = transpiler.to_ps1(match2_code)
	assert(sh_match2:find("*nvim*", 1, true), "toContains: Bash wildcard pattern missing")
	assert(sh_match2:find("${#items}", 1, true), "toHaveLength: Bash string length syntax missing")
	assert(ps1_match2:find("-notlike", 1, true), "toContains: PS1 -notlike missing")
	assert(ps1_match2:find(".Count", 1, true), "toHaveLength: PS1 .Count missing")

	-- Test 9: Standalone Method Calls with dots (logger.info, user:getName)
	local method_code = [[
logger.info("system ready")
user:updateScore(100)
]]
	local sh_method = transpiler.to_sh(method_code)
	local ps1_method = transpiler.to_ps1(method_code)
	assert(sh_method:find("logger_info", 1, true), "Method call: Bash sanitized function name missing")
	assert(sh_method:find("user_updateScore", 1, true), "Method call: Bash sanitized colon method name missing")
	assert(ps1_method:find("$logger.info", 1, true), "Method call: PS1 object method call missing")
	assert(ps1_method:find("$user.updateScore", 1, true), "Method call: PS1 colon method call missing")

	-- Test 10: Table / Array Literals in assignments
	local tbl_code = [[
local list = { "apple", "banana" }
local config = { port = 8080, debug = true }
]]
	local sh_tbl = transpiler.to_sh(tbl_code)
	local ps1_tbl = transpiler.to_ps1(tbl_code)
	assert(sh_tbl:find('list=("apple" "banana")', 1, true), "Table: Bash array assignment missing")
	assert(ps1_tbl:find('list = @("apple", "banana")', 1, true), "Table: PS1 array assignment missing")
	assert(ps1_tbl:find('@{"port"=8080; "debug"=$true}', 1, true), "Table: PS1 hashtable assignment missing")

	-- Test 11: File System Builtins (fs.mkdir, fs.write, fs.read, fs.remove, fs.exists)
	local fs_code = [[
fs.mkdir("build")
fs.write("build/out.txt", "hello")
local content = fs.read("build/out.txt")
fs.remove("build")
if fs.exists("config.json") then
  print("config found")
end
]]
	local sh_fs = transpiler.to_sh(fs_code)
	local ps1_fs = transpiler.to_ps1(fs_code)
	assert(sh_fs:find("mkdir -p", 1, true), "FS: Bash mkdir missing")
	assert(sh_fs:find("rm -rf", 1, true), "FS: Bash rm -rf missing")
	assert(ps1_fs:find("New-Item -ItemType Directory", 1, true), "FS: PS1 New-Item missing")
	assert(ps1_fs:find("Test-Path", 1, true), "FS: PS1 Test-Path missing")

	-- Test 12: JSON & Fetch Builtins
	local net_code = [[
local payload = json.encode({ status = "ok" })
local res = fetch.json("https://api.example.com/status")
]]
	local sh_net = transpiler.to_sh(net_code)
	local ps1_net = transpiler.to_ps1(net_code)
	assert(sh_net:find("curl -sSL", 1, true), "Fetch: Bash curl missing")
	assert(ps1_net:find("Invoke-RestMethod", 1, true), "Fetch: PS1 Invoke-RestMethod missing")

	-- Test 13: Sleep & Async
	local sleep_code = "async.sleep(500)\nsleep(1000)"
	local sh_sleep = transpiler.to_sh(sleep_code)
	local ps1_sleep = transpiler.to_ps1(sleep_code)
	assert(sh_sleep:find("time.sleep(500/1000)", 1, true), "Sleep: Bash python sleep missing")
	assert(ps1_sleep:find("Start-Sleep -Milliseconds 500", 1, true), "Sleep: PS1 Start-Sleep missing")

	-- Test 14: Nested Control Flow (if / elseif / else / end)
	local flow_code = [[
if x == 1 then
  print("one")
elseif x == 2 then
  print("two")
else
  print("other")
end
]]
	local sh_flow = transpiler.to_sh(flow_code)
	local ps1_flow = transpiler.to_ps1(flow_code)
	assert(sh_flow:find("if [[ ${x} == 1 ]]; then", 1, true), "Flow: Bash if statement missing")
	assert(sh_flow:find("elif [[ ${x} == 2 ]]; then", 1, true), "Flow: Bash elseif statement missing")
	assert(sh_flow:find("fi", 1, true), "Flow: Bash closing fi missing")
	assert(ps1_flow:find("if ($x -eq 1)", 1, true), "Flow: PS1 if statement missing")
	assert(ps1_flow:find("} elseif ($x -eq 2)", 1, true), "Flow: PS1 elseif statement missing")

	-- Test 15: require / import commenting out
	local req_code = 'local test = require("krsnvim.test")\nlocal fs = import("krsnvim.fs")'
	local sh_req = transpiler.to_sh(req_code)
	local ps1_req = transpiler.to_ps1(req_code)
	assert(sh_req:find("# [krsnvim] local test = require", 1, true), "Require: Bash require comment missing")
	assert(ps1_req:find("# [krsnvim] local fs = import", 1, true), "Require: PS1 import comment missing")

	print("  ✓ krsnvim.krsnvimtranspiler spec passed (15+ intensive tests)")
end

return M
