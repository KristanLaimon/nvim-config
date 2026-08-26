--- @module "krsnvim.krsnvimtranspiler"
--- Comprehensive Transpiler suite for `krsnvimscript` (*.krsnvim).
--- Programmatically converts `.krsnvim` scripts into 100% equivalent `.sh` (Bash) and `.ps1` (PowerShell) scripts
--- using native OS CLI tools (`python3`, `mkdir`, `curl`, `Invoke-RestMethod`, `New-Item`, `Get-Content`, etc.).
--- Supports functions, parameters, advanced loops, CLI arguments/menus, YAML/TOML, and error assertions.
---
--- @example
--- local transpiler = import("krsnvimtranspiler")
--- transpiler.export_both("test.krsnvim") -- generates test.sh and test.ps1
local M = {}

local fs = require("krs.lib.krsnvim.fs")

--- Reserved Lua keywords and boolean constants to prevent invalid variable prefixing.
local LUA_KEYWORDS = {
	["true"] = true,
	["false"] = true,
	["nil"] = true,
	["and"] = true,
	["or"] = true,
	["not"] = true,
}

--- Masks string literals ("...", '...') inside a code string with temporary tokens
--- so pattern matchers don't inadvertently modify text inside string constants.
--- @param text string
--- @return string masked, string[] strings
local function mask_strings(text)
	if not text then
		return "", {}
	end
	local strings = {}
	local masked = text
		:gsub('"[^"]*"', function(s)
			table.insert(strings, s)
			return "___STR_" .. #strings .. "___"
		end)
		:gsub("'[^']*'", function(s)
			table.insert(strings, s)
			return "___STR_" .. #strings .. "___"
		end)
	return masked, strings
end

--- Restores string literals from temporary tokens created by mask_strings.
--- @param text string
--- @param strings string[]
--- @return string
local function unmask_strings(text, strings)
	if not text then
		return ""
	end
	local res = text:gsub("___STR_(%d+)___", function(idx)
		return strings[tonumber(idx)] or ""
	end)
	return res
end

--- Splits a comma-separated argument list on top-level commas only, ignoring
--- commas nested inside `{}` or `()` or string literals.
--- @param args string
--- @return string[]
local function split_args(args)
	if not args or args == "" then
		return {}
	end
	local masked, strings = mask_strings(args)
	local parts, depth, current = {}, 0, ""
	for i = 1, #masked do
		local c = masked:sub(i, i)
		if c == "{" or c == "(" then
			depth = depth + 1
		elseif c == "}" or c == ")" then
			depth = depth - 1
		end
		if c == "," and depth == 0 then
			table.insert(parts, (unmask_strings(current, strings)):match("^%s*(.-)%s*$"))
			current = ""
		else
			current = current .. c
		end
	end
	if current:match("%S") then
		table.insert(parts, (unmask_strings(current, strings)):match("^%s*(.-)%s*$"))
	end
	return parts
end

--- Joins source lines whose parens haven't balanced yet (e.g. a function call
--- whose table-literal argument spans multiple lines) into one logical line.
--- Ignores parentheses inside string literals and comments.
--- @param code string
--- @return string
local function join_multiline_calls(code)
	local out_lines = {}
	local pending, depth = nil, 0
	for line in code:gmatch("[^\r\n]+") do
		local cleaned = line:gsub("%-%-.*$", "")
		cleaned = cleaned:gsub('"[^"]*"', ""):gsub("'[^']*'", "")

		if cleaned:match("function%s*%(") then
			if pending then
				table.insert(out_lines, pending)
				pending, depth = nil, 0
			end
			table.insert(out_lines, line)
		else
			local _, opens = cleaned:gsub("%(", "")
			local _, closes = cleaned:gsub("%)", "")
			if pending then
				pending = pending .. " " .. line:match("^%s*(.-)%s*$")
			else
				pending = line
			end
			depth = depth + opens - closes
			if depth <= 0 then
				table.insert(out_lines, pending)
				pending, depth = nil, 0
			end
		end
	end
	if pending then
		table.insert(out_lines, pending)
	end
	return table.concat(out_lines, "\n")
end

--- Converts a Lua expression into PowerShell:
--- `a .. b` -> `$a + $b`
--- `not cond` -> `-not cond`
--- `==` -> `-eq`, `~=` -> `-ne`, `<` -> `-lt`, `>` -> `-gt`, `<=` -> `-le`, `>=` -> `-ge`
--- `and` -> `-and`, `or` -> `-or`
--- @param expr string
--- @return string
local function to_ps1_expr(expr)
	if not expr or expr == "" then
		return ""
	end
	local masked, strings = mask_strings(expr)

	-- Method calls: obj:method( -> obj.method(
	masked = masked:gsub("([%w_]+):([%w_]+)%(", "%1.%2(")

	-- String concatenation: .. -> +
	masked = masked:gsub("%s*%.%.%s*", " + ")

	-- Replace identifiers with $identifier FIRST (skipping Lua reserved keywords, function calls, and masked strings)
	masked = masked:gsub("()([%a_][%w_]*)()", function(s_pos, word, e_pos)
		if word == "true" then
			return "$true"
		end
		if word == "false" then
			return "$false"
		end
		if word == "nil" then
			return "$null"
		end
		if LUA_KEYWORDS[word] then
			return word
		end
		if word:match("^___STR_%d+___$") then
			return word
		end
		if word:sub(1, 1) == "$" then
			return word
		end
		local is_fn = masked:sub(e_pos):match("^%s*%(") ~= nil
		if is_fn then
			return word
		end
		return "$" .. word
	end)

	-- Binary / logical operators (applied after identifiers to avoid altering -lt, -eq, etc.)
	masked = masked:gsub("%f[%w]not%f[%W]", "-not ")
	masked = masked:gsub("%f[%w]and%f[%W]", " -and ")
	masked = masked:gsub("%f[%w]or%f[%W]", " -or ")

	masked = masked:gsub("==", " -eq ")
	masked = masked:gsub("~=", " -ne ")
	masked = masked:gsub("!=", " -ne ")
	masked = masked:gsub("<=", " -le ")
	masked = masked:gsub(">=", " -ge ")
	masked = masked:gsub("<", " -lt ")
	masked = masked:gsub(">", " -gt ")

	-- Clean up double spaces around operators
	masked = masked:gsub("%s+", " ")

	return (unmask_strings(masked, strings))
end

--- Formats a single argument/value for PowerShell.
--- Handles strings, numbers, booleans, string concats, and variable names.
--- @param val string
--- @return string
local function format_ps1_val(val)
	if not val or val == "" then
		return '""'
	end
	val = val:match("^%s*(.-)%s*$")
	if val:match('^"[^"]*"$') or val:match("^'[^']*'$") then
		return val
	end
	if tonumber(val) then
		return val
	end
	if val == "true" then
		return "$true"
	end
	if val == "false" then
		return "$false"
	end
	if val == "nil" then
		return "$null"
	end

	-- Multi-part string concatenation: "a" .. b .. "c"
	if val:find("%.%.") then
		local parts = {}
		local masked, strings = mask_strings(val)
		for part in masked:gmatch("[^%.]+") do
			part = part:match("^%s*(.-)%s*$")
			if part ~= "" then
				if part:match("^___STR_%d+___$") then
					table.insert(parts, (unmask_strings(part, strings)))
				elseif tonumber(part) then
					table.insert(parts, part)
				elseif LUA_KEYWORDS[part] then
					table.insert(parts, part)
				else
					table.insert(parts, "$" .. part)
				end
			end
		end
		return table.concat(parts, " + ")
	end

	if val:match("^[%a_][%w_]*$") then
		return "$" .. val
	end

	return to_ps1_expr(val)
end

--- Helper to convert Lua table literal to PowerShell Hashtable syntax (@{...}) or Array (@(...)).
--- @param lua_tbl_str string
--- @return string
local function lua_tbl_to_ps1(lua_tbl_str)
	if not lua_tbl_str then
		return "@()"
	end
	local s = lua_tbl_str:match("^%s*{?(.-)}?%s*$")
	if not s or s == "" then
		return "@()"
	end

	local args = split_args(s)
	local is_kv = false
	for _, item in ipairs(args) do
		if item:match("^[%w_]+%s*=") then
			is_kv = true
			break
		end
	end

	if is_kv then
		local items = {}
		for _, kv in ipairs(args) do
			local k, v = kv:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
			if k and v then
				table.insert(items, '"' .. k .. '"=' .. format_ps1_val(v))
			else
				table.insert(items, kv)
			end
		end
		return "@{" .. table.concat(items, "; ") .. "}"
	else
		local items = {}
		for _, v in ipairs(args) do
			table.insert(items, format_ps1_val(v))
		end
		return "@(" .. table.concat(items, ", ") .. ")"
	end
end

--- Formats a single argument/value for Bash.
--- @param val string
--- @return string
local function format_sh_val(val)
	if not val or val == "" then
		return '""'
	end
	val = val:match("^%s*(.-)%s*$")
	if val:match('^"[^"]*"$') or val:match("^'[^']*'$") then
		return val
	end
	if tonumber(val) then
		return val
	end
	if val == "true" or val == "false" then
		return '"' .. val .. '"'
	end

	-- Multi-part string concatenation: "a" .. b .. "c"
	if val:find("%.%.") then
		local parts = {}
		local masked, strings = mask_strings(val)
		for part in masked:gmatch("[^%.]+") do
			part = part:match("^%s*(.-)%s*$")
			if part ~= "" then
				if part:match("^___STR_%d+___$") then
					local unmasked = unmask_strings(part, strings)
					table.insert(parts, unmasked:sub(2, -2))
				elseif tonumber(part) then
					table.insert(parts, part)
				else
					table.insert(parts, "${" .. part .. "}")
				end
			end
		end
		return '"' .. table.concat(parts, "") .. '"'
	end

	-- Math expression in assignment / return: x * y
	if val:match("[+%*%/%-]") and not val:find('"') and not val:find("'") then
		if val:match("%.") then
			-- Floating point arithmetic requires python/awk
			return '$(python3 -c "print(' .. val .. ')" 2>/dev/null || python -c "print(' .. val .. ')")'
		end
		return "$(( " .. val .. " ))"
	end

	if val:match("^[%a_][%w_]*$") then
		return '"${' .. val .. '}"'
	end

	return '"' .. val .. '"'
end

--- Helper to convert Lua table literal to valid JSON string literal for Bash.
--- @param lua_tbl_str string
--- @return string
local function lua_tbl_to_json(lua_tbl_str)
	if not lua_tbl_str then
		return "'{}'"
	end
	local s = lua_tbl_str:match("^%s*{?(.-)}?%s*$")
	if not s or s == "" then
		return "'{}'"
	end
	local args = split_args(s)
	local items = {}
	for _, kv in ipairs(args) do
		local k, v = kv:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if k and v then
			local json_v
			if (v:sub(1, 1) == '"' and v:sub(-1) == '"') or (v:sub(1, 1) == "'" and v:sub(-1) == "'") then
				json_v = '"' .. v:sub(2, -2) .. '"'
			elseif v == "true" or v == "false" or tonumber(v) then
				json_v = v
			else
				json_v = '"' .. v .. '"'
			end
			table.insert(items, '"' .. k .. '": ' .. json_v)
		else
			table.insert(items, kv)
		end
	end
	return "'{" .. table.concat(items, ", ") .. "}'"
end

--- Formats a condition for Bash `[[ ... ]]` or `(( ... ))`.
--- @param cond string
--- @return string mode, string expr
local function format_sh_cond(cond)
	cond = cond:match("^%s*(.-)%s*$")
	if cond:match("^not%s+fs%.exists%((.*)%)%s*$") then
		local p = cond:match("^not%s+fs%.exists%((.*)%)%s*$")
		return "test", "! -e " .. format_sh_val(p)
	elseif cond:match("^fs%.exists%((.*)%)%s*$") then
		local p = cond:match("^fs%.exists%((.*)%)%s*$")
		return "test", "-e " .. format_sh_val(p)
	end

	local is_not = false
	if cond:match("^not%s+(.*)$") then
		is_not = true
		cond = cond:match("^not%s+(.*)$")
	end

	-- Check if pure arithmetic condition (numbers/operators without string quotes or parenthesized subclauses)
	if cond:match("[+%*%/%-]") and not cond:find('"') and not cond:find("'") and not cond:find("%(") then
		local arith_expr = cond:gsub("~=", "!=")
		if is_not then
			return "arithmetic", "! ( " .. arith_expr .. " )"
		end
		return "arithmetic", arith_expr
	end

	local masked, strings = mask_strings(cond)

	-- Wrap variables with ${var} skipping Lua keywords
	masked = masked:gsub("[%a_][%w_]*", function(w)
		if LUA_KEYWORDS[w] then
			return w
		end
		if w:match("^___STR_%d+___$") then
			return w
		end
		if w:sub(1, 1) == "$" then
			return w
		end
		return "${" .. w .. "}"
	end)

	-- Convert comparison and logical operators for Bash
	masked = masked:gsub("==", " == ")
	masked = masked:gsub("~=", " != ")
	masked = masked:gsub("!=", " != ")
	masked = masked:gsub("<=", " -le ")
	masked = masked:gsub(">=", " -ge ")
	masked = masked:gsub("<", " -lt ")
	masked = masked:gsub(">", " -gt ")
	masked = masked:gsub("%f[%w]not%f[%W]", " ! ")
	masked = masked:gsub("%f[%w]and%f[%W]", " && ")
	masked = masked:gsub("%f[%w]or%f[%W]", " || ")

	-- Ensure spaces around subclause parens inside [[ ... ]]
	masked = masked:gsub("%(", " ( ")
	masked = masked:gsub("%)", " ) ")
	masked = masked:gsub("%s+", " ")

	local res = (unmask_strings(masked, strings))
	if is_not then
		return "test", "! " .. res
	end
	return "test", res
end

--- Transpiles `.krsnvim` Lua code string into Bash script (`.sh`).
--- @param code string Full Lua code string of a .krsnvim script.
--- @return string bash_script Equivalent Bash script.
function M.to_sh(code)
	local lines = {}
	table.insert(lines, "#!/usr/bin/env bash")
	table.insert(lines, "# ==========================================================================")
	table.insert(lines, "# Transpiled from krsnvimscript (.krsnvim) -> Bash (.sh)")
	table.insert(lines, "# Automatically generated by krsnvimtranspiler")
	table.insert(lines, "# ==========================================================================")
	table.insert(lines, "set -e")
	table.insert(lines, "")

	local block_stack = {}

	for line in join_multiline_calls(code):gmatch("[^\r\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$")
		local indent = line:match("^(%s*)") or ""

		-- Skip or comment out require/import lines
		if
			trimmed:match("^local%s+[%w_]+%s*=%s*require%(")
			or trimmed:match("^local%s+[%w_]+%s*=%s*import%(")
			or trimmed:match("^require%(")
			or trimmed:match("^import%(")
		then
			table.insert(lines, indent .. "# [krsnvim] " .. trimmed .. " (mapped to native CLI tools)")

		-- Comments: -- comment -> # comment
		elseif trimmed:sub(1, 2) == "--" then
			local comment_text = trimmed:sub(3):match("^%s*(.-)%s*$")
			table.insert(lines, indent .. "# " .. comment_text)

		-- Empty lines
		elseif trimmed == "" then
			table.insert(lines, "")

		-- Testing Framework Hooks: test.beforeAll, test.afterAll, test.beforeEach, test.afterEach, etc.
		elseif
			trimmed:match("^[%w_]*%.?beforeAll%s*%(")
			or trimmed:match("^[%w_]*%.?afterAll%s*%(")
			or trimmed:match("^[%w_]*%.?beforeEach%s*%(")
			or trimmed:match("^[%w_]*%.?afterEach%s*%(")
		then
			table.insert(block_stack, "noop")

		-- Testing Framework Suites: describe("suite", function() ...) or test.describe(...)
		elseif trimmed:match("^describe%s*%(") or trimmed:match("^[%w_]+%.describe%s*%(") then
			local suite_name = trimmed:match('describe%s*%("%s*(.-)%s*"')
				or trimmed:match("describe%s*%('%s*(.-)%s*'")
				or "Test Suite"
			table.insert(block_stack, "noop")
			table.insert(lines, indent .. 'echo "📦 Suite: ' .. suite_name .. '"')

		-- Testing Framework Runner: test.run() or t.run() or run()
		elseif trimmed:match("^[%w_]+%.run%s*%(") or trimmed:match("^run%s*%(") then
			table.insert(lines, indent .. "# [krsnvim] " .. trimmed)

		-- Testing Framework Tests: it("test", function() ...) or test("test", function() ...) or test.test(...)
		elseif
			trimmed:match("^it%s*%(")
			or trimmed:match("^test%s*%(")
			or trimmed:match("^[%w_]+%.it%s*%(")
			or trimmed:match("^[%w_]+%.test%s*%(")
		then
			local test_name = trimmed:match('it%s*%("%s*(.-)%s*"')
				or trimmed:match('test%s*%("%s*(.-)%s*"')
				or trimmed:match("it%s*%('%s*(.-)%s*'")
				or trimmed:match("test%s*%('%s*(.-)%s*'")
				or "Test"
			table.insert(block_stack, "noop")
			table.insert(lines, indent .. 'echo "  ✓ ' .. test_name .. '"')

		-- Testing Framework Assertions: expect(val)...
		elseif trimmed:match("^expect%s*%(") then
			local is_inv = trimmed:find("%.isNot%.")
				or trimmed:find('%["not"%]')
				or trimmed:find("%.not%.")
				or trimmed:find("%.not_%.")

			if trimmed:find("%.toBe%s*%(") or trimmed:find("%.toEqual%s*%(") then
				local act, exp = trimmed:match("expect%s*%((.-)%)%..-toBe%s*%((.-)%)")
				if not act then
					act, exp = trimmed:match("expect%s*%((.-)%)%..-toEqual%s*%((.-)%)")
				end
				if act and exp then
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if [ "
								.. format_sh_val(act)
								.. " == "
								.. format_sh_val(exp)
								.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent
								.. "if [ "
								.. format_sh_val(act)
								.. " != "
								.. format_sh_val(exp)
								.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif trimmed:find("%.toBeTruthy%s*%(") then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if [ -n "
								.. format_sh_val(act)
								.. " ] && [ "
								.. format_sh_val(act)
								.. ' != "false" ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent
								.. "if [ -z "
								.. format_sh_val(act)
								.. " ] || [ "
								.. format_sh_val(act)
								.. ' == "false" ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif trimmed:find("%.toBeFalsy%s*%(") then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if [ -z "
								.. format_sh_val(act)
								.. " ] || [ "
								.. format_sh_val(act)
								.. ' == "false" ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent
								.. "if [ -n "
								.. format_sh_val(act)
								.. " ] && [ "
								.. format_sh_val(act)
								.. ' != "false" ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif
				trimmed:find("%.toBeNil%s*%(")
				or trimmed:find("%.toBeNull%s*%(")
				or trimmed:find("%.toBeUndefined%s*%(")
			then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent .. "if [ -z " .. format_sh_val(act) .. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent .. "if [ -n " .. format_sh_val(act) .. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif trimmed:find("%.toBeDefined%s*%(") then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent .. "if [ -n " .. format_sh_val(act) .. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent .. "if [ -z " .. format_sh_val(act) .. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif trimmed:find("%.toContain%s*%(") then
				local act, item = trimmed:match("expect%s*%((.-)%)%..-toContain%s*%((.-)%)")
				if act and item then
					local clean_item = item:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if [[ "
								.. format_sh_val(act)
								.. " == *"
								.. clean_item
								.. '* ]]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent
								.. "if [[ "
								.. format_sh_val(act)
								.. " != *"
								.. clean_item
								.. '* ]]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif trimmed:find("%.toHaveLength%s*%(") then
				local act, len = trimmed:match("expect%s*%((.-)%)%..-toHaveLength%s*%((.-)%)")
				if act and len then
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if [ ${#"
								.. act
								.. "} -eq "
								.. format_sh_val(len)
								.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					else
						table.insert(
							lines,
							indent
								.. "if [ ${#"
								.. act
								.. "} -ne "
								.. format_sh_val(len)
								.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
						)
					end
				end
			elseif trimmed:find("%.toBeGreaterThan%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeGreaterThan%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if [ "
							.. format_sh_val(act)
							.. " -le "
							.. format_sh_val(num)
							.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
					)
				end
			elseif trimmed:find("%.toBeGreaterThanOrEqual%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeGreaterThanOrEqual%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if [ "
							.. format_sh_val(act)
							.. " -lt "
							.. format_sh_val(num)
							.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
					)
				end
			elseif trimmed:find("%.toBeLessThan%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeLessThan%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if [ "
							.. format_sh_val(act)
							.. " -ge "
							.. format_sh_val(num)
							.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
					)
				end
			elseif trimmed:find("%.toBeLessThanOrEqual%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeLessThanOrEqual%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if [ "
							.. format_sh_val(act)
							.. " -gt "
							.. format_sh_val(num)
							.. ' ]; then echo "❌ Expect failed"; exit 1; fi'
					)
				end
			elseif trimmed:find("%.toThrow") then
				local fn = trimmed:match("expect%s*%((.-)%)%..-toThrow")
				if fn then
					table.insert(
						lines,
						indent
							.. "if "
							.. format_sh_val(fn)
							.. ' 2>/dev/null; then echo "❌ Expect failed: expected error"; exit 1; fi'
					)
				end
			end

		-- Function definitions or Coroutine creation: function fn_name(arg1, arg2)
		elseif
			trimmed:match("^function%s+([%w_]+)%s*%((.*)%)")
			or trimmed:match("^local%s+function%s+([%w_]+)%s*%((.*)%)")
			or trimmed:match("coroutine%..-%(%s*function%s*%((.*)%)")
		then
			local fn_name, params_str
			if trimmed:match("coroutine%..-%(%s*function%s*%((.*)%)") then
				fn_name = trimmed:match("^local%s+([%a_][%w_]*)%s*=") or trimmed:match("^([%a_][%w_]*)%s*=") or "co_fn"
				params_str = trimmed:match("coroutine%..-%(%s*function%s*%((.*)%)")
			else
				fn_name, params_str = trimmed:match("function%s+([%w_]+)%s*%((.*)%)")
			end
			table.insert(block_stack, "function")
			table.insert(lines, indent .. fn_name .. "() {")
			local idx = 1
			for param in (params_str or ""):gmatch("[^,]+") do
				param = param:match("^%s*(.-)%s*$")
				if param ~= "" then
					table.insert(lines, indent .. "  local " .. param .. '="$' .. idx .. '"')
					idx = idx + 1
				end
			end

		-- Return statements: return expr
		elseif trimmed:match("^return%s*(.*)$") then
			local ret_expr = trimmed:match("^return%s*(.*)$"):match("^%s*(.-)%s*$")
			if ret_expr ~= "" then
				local fn1, a1, op, fn2, a2 = ret_expr:match("^([%a_][%w_]*)%((.*)%)%s*([+%*%/%-])%s*([%a_][%w_]*)%((.*)%)$")
				if fn1 and a1 and op and fn2 and a2 then
					local arith1 = a1:gsub("([%a_][%w_]*)", function(w)
						return w
					end)
					local arith2 = a2:gsub("([%a_][%w_]*)", function(w)
						return w
					end)
					table.insert(
						lines,
						indent
							.. "echo $(( $("
							.. fn1
							.. " $(( "
							.. arith1
							.. " ))) "
							.. op
							.. " $("
							.. fn2
							.. " $(( "
							.. arith2
							.. " ))) ))"
					)
				else
					table.insert(lines, indent .. "echo " .. format_sh_val(ret_expr))
				end
			end
			table.insert(lines, indent .. "return 0")

		-- coroutine.yield(...) -> echo ...
		elseif trimmed:match("^coroutine%.yield%((.*)%)") then
			local args = trimmed:match("^coroutine%.yield%((.*)%)")
			local echoed = {}
			for _, arg in ipairs(split_args(args)) do
				table.insert(echoed, format_sh_val(arg))
			end
			table.insert(lines, indent .. "echo " .. table.concat(echoed, " "))

		-- Multiple variable assignment: local ok, val = coroutine.resume(co, arg) OR pcall(fn, arg)
		elseif trimmed:match("^local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*(.-)%((.*)%)") then
			local var_ok, var_res, fn_call, fn_args =
				trimmed:match("^local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*(.-)%((.*)%)")
			fn_call = fn_call:match("^%s*(.-)%s*$")
			if fn_call == "coroutine.resume" then
				local args_parts = split_args(fn_args)
				local co_name = args_parts[1] or "co"
				local extra_args = {}
				for i = 2, #args_parts do
					table.insert(extra_args, format_sh_val(args_parts[i]))
				end
				table.insert(lines, indent .. var_res .. "=$(" .. co_name .. " " .. table.concat(extra_args, " ") .. ")")
				table.insert(lines, indent .. var_ok .. '="true"')
			elseif fn_call == "pcall" then
				local args_parts = split_args(fn_args)
				local target_fn = args_parts[1] or "fn"
				local extra_args = {}
				for i = 2, #args_parts do
					table.insert(extra_args, format_sh_val(args_parts[i]))
				end
				table.insert(
					lines,
					indent
						.. "if "
						.. var_res
						.. "=$("
						.. target_fn
						.. " "
						.. table.concat(extra_args, " ")
						.. " 2>/dev/null); then"
				)
				table.insert(lines, indent .. "  " .. var_ok .. '="true"')
				table.insert(lines, indent .. "else")
				table.insert(lines, indent .. "  " .. var_ok .. '="false"')
				table.insert(lines, indent .. "fi")
			end

		-- print(...) -> echo ...
		elseif trimmed:match("^print%((.*)%)") then
			local args = trimmed:match("^print%((.*)%)")
			local echoed = {}
			for _, arg in ipairs(split_args(args)) do
				table.insert(echoed, format_sh_val(arg))
			end
			table.insert(lines, indent .. "echo " .. table.concat(echoed, " "))

		-- console.log(...) / console.info(...) -> echo ...
		elseif trimmed:match("^console%.[%w_]+%((.*)%)%s*$") then
			local args = trimmed:match("^console%.[%w_]+%((.*)%)%s*$")
			local echoed = {}
			for _, raw in ipairs(split_args(args)) do
				if raw:sub(1, 1) == "{" then
					table.insert(echoed, lua_tbl_to_json(raw))
				else
					table.insert(echoed, format_sh_val(raw))
				end
			end
			table.insert(lines, indent .. "echo " .. table.concat(echoed, " "))

		-- error(msg) -> echo "msg" >&2; exit 1
		elseif trimmed:match("^error%((.*)%)") then
			local err_msg = trimmed:match("^error%((.*)%)")
			table.insert(lines, indent .. "echo " .. format_sh_val(err_msg) .. " >&2")
			table.insert(lines, indent .. "exit 1")

		-- assert(cond, msg) -> [[ cond ]] || { echo "msg" >&2; exit 1; }
		elseif trimmed:match("^assert%((.*)%)") then
			local args = split_args(trimmed:match("^assert%((.*)%)"))
			local cond = args[1] or "true"
			local msg = args[2] or '"Assertion failed"'
			local mode, cond_str = format_sh_cond(cond)
			if mode == "arithmetic" then
				table.insert(lines, indent .. "(( " .. cond_str .. " )) || { echo " .. format_sh_val(msg) .. " >&2; exit 1; }")
			else
				table.insert(lines, indent .. "[[ " .. cond_str .. " ]] || { echo " .. format_sh_val(msg) .. " >&2; exit 1; }")
			end

		-- fs.mkdir(path) -> mkdir -p path
		elseif trimmed:match("^fs%.mkdir%((.*)%)") then
			local path_arg = trimmed:match("^fs%.mkdir%((.*)%)")
			table.insert(lines, indent .. "mkdir -p " .. format_sh_val(path_arg))

		-- fs.write(path, content) -> echo content > path
		elseif trimmed:match("^fs%.write%((.*)%)") then
			local args = split_args(trimmed:match("^fs%.write%((.*)%)"))
			local path_arg = args[1]
			local content_arg = args[2] or '""'
			table.insert(lines, indent .. "echo " .. format_sh_val(content_arg) .. " > " .. format_sh_val(path_arg))

		-- fs.remove(path) / fs.delete(path) -> rm -rf path
		elseif trimmed:match("^fs%.remove%((.*)%)") or trimmed:match("^fs%.delete%((.*)%)") then
			local path_arg = trimmed:match("%((.*)%)")
			table.insert(lines, indent .. "rm -rf " .. format_sh_val(path_arg))

		-- $ "cmd" or terminal.exec("cmd") -> cmd
		elseif
			trimmed:match("^%s*%$%s*%((.*)%)")
			or trimmed:match("^%s*terminal%.exec%((.*)%)")
			or trimmed:match("^%s*terminal%.run%((.*)%)")
		then
			local cmd_arg = trimmed:match("%((.*)%)")
			cmd_arg = cmd_arg:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
			table.insert(lines, indent .. cmd_arg)

		-- Variable assignments: local var = val OR var = val
		elseif trimmed:match("^local%s+[%a_][%w_]*%s*=%s*") or trimmed:match("^[%a_][%w_]*%s*=%s*") then
			local is_local, var, val
			if trimmed:match("^local%s+") then
				var, val = trimmed:match("^local%s+([%a_][%w_]*)%s*=%s*(.*)$")
				is_local = true
			else
				var, val = trimmed:match("^([%a_][%w_]*)%s*=%s*(.*)$")
				is_local = false
			end

			-- Table/array literal: local list = { "a", "b" }
			if val:sub(1, 1) == "{" and val:sub(-1) == "}" then
				local tbl_content = val:sub(2, -2)
				local items = {}
				for _, item in ipairs(split_args(tbl_content)) do
					table.insert(items, format_sh_val(item))
				end
				table.insert(lines, indent .. var .. "=(" .. table.concat(items, " ") .. ")")

			-- Builtin: fs.read(path) -> cat path
			elseif val:match("^fs%.read%((.*)%)") then
				local path_arg = val:match("^fs%.read%((.*)%)")
				table.insert(lines, indent .. var .. "=$(cat " .. format_sh_val(path_arg) .. ")")

			-- Builtin: json.encode(obj)
			elseif val:match("^json%.encode%((.*)%)") then
				local obj_arg = val:match("^json%.encode%((.*)%)")
				if obj_arg:sub(1, 1) == "{" then
					table.insert(lines, indent .. var .. "=" .. lua_tbl_to_json(obj_arg))
				else
					table.insert(
						lines,
						indent
							.. var
							.. '=$(python3 -c "import json, sys; print(json.dumps('
							.. format_sh_val(obj_arg)
							.. '))" 2>/dev/null || echo "${'
							.. obj_arg
							.. '}")'
					)
				end

			-- Builtin: json.load(path) -> cat path
			elseif val:match("^json%.load%((.*)%)") then
				local path_arg = val:match("^json%.load%((.*)%)")
				table.insert(lines, indent .. var .. "=$(cat " .. format_sh_val(path_arg) .. ")")

			-- Builtin: fetch.get(url) / fetch.json(url) -> curl -sSL url
			elseif val:match("^fetch%..-%((.*)%)") then
				local url_arg = val:match("^fetch%..-%((.*)%)")
				table.insert(lines, indent .. var .. "=$(curl -sSL " .. format_sh_val(url_arg) .. ")")

			-- Builtin: terminal execution -> $(cmd)
			elseif val:match("^terminal%..-%((.*)%)") or val:match("^%s*%$%s*%((.*)%)") then
				local cmd_arg = val:match("%((.*)%)"):gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
				table.insert(lines, indent .. var .. "=$(" .. cmd_arg .. ")")

			-- Custom function call: var = fn(a, b)
			elseif val:match("^[%a_][%w_]*%s*%((.*)%)") then
				local fn_name, fn_args = val:match("^([%a_][%w_]*)%s*%((.*)%)")
				if
					fn_name == "setTimeout"
					or fn_name == "setInterval"
					or fn_name == "clearTimeout"
					or fn_name == "clearInterval"
				then
					table.insert(lines, indent .. var .. '="timer_id"')
				else
					local sh_args = {}
					for _, arg in ipairs(split_args(fn_args)) do
						table.insert(sh_args, format_sh_val(arg))
					end
					table.insert(lines, indent .. var .. "=$(" .. fn_name .. " " .. table.concat(sh_args, " ") .. ")")
				end

			-- Math / Arithmetic expression: x = x + 1 or x = a + b
			elseif val:match("[+%*%/%-]") and not val:find('"') and not val:find("'") then
				if val:match("%.") then
					local py_expr = val:gsub("([%a_][%w_]*)", function(w)
						if LUA_KEYWORDS[w] or tonumber(w) then
							return w
						end
						return "${" .. w .. "}"
					end)
					table.insert(
						lines,
						indent
							.. var
							.. '=$(python3 -c "print('
							.. py_expr
							.. ')" 2>/dev/null || python -c "print('
							.. py_expr
							.. ')")'
					)
				else
					local arith = val:gsub("([%a_][%w_]*)", function(w)
						return w
					end)
					table.insert(lines, indent .. var .. "=$(( " .. arith .. " ))")
				end

			-- Standard value assignment
			else
				local sh_val = format_sh_val(val)
				table.insert(lines, indent .. var .. "=" .. sh_val)
			end

		-- Builtin: async.sleep(ms) / sleep(ms) -> sleep in seconds via python3 or sleep 1
		elseif trimmed:match("^async%.sleep%s*%((.*)%)") or trimmed:match("^sleep%s*%((.*)%)") then
			local ms_arg = trimmed:match("^async%.sleep%s*%((.*)%)") or trimmed:match("^sleep%s*%((.*)%)")
			local ms_val = format_sh_val(ms_arg)
			table.insert(
				lines,
				indent .. 'python3 -c "import time; time.sleep(' .. ms_val .. '/1000)" 2>/dev/null || sleep 1'
			)

		-- Builtin: JS-style Timers (setTimeout, setInterval, clearTimeout, clearInterval)
		elseif
			trimmed:match("^setTimeout%s*%(")
			or trimmed:match("^setInterval%s*%(")
			or trimmed:match("^clearTimeout%s*%(")
			or trimmed:match("^clearInterval%s*%(")
		then
			table.insert(lines, indent .. "# " .. trimmed)

		-- Builtin: async channel & coroutine / task calls
		elseif trimmed:match("^async%..-%((.*)%)") then
			table.insert(lines, indent .. "# " .. trimmed)

		-- Builtin: dofile(path) / loadfile(path) -> nvim -l path or bash path.sh
		elseif trimmed:match("^dofile%s*%((.*)%)") or trimmed:match("^loadfile%s*%((.*)%)") then
			local file_arg = trimmed:match("^dofile%s*%((.*)%)") or trimmed:match("^loadfile%s*%((.*)%)")
			local clean_arg = file_arg:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
			if clean_arg:match("%.krsnvim$") then
				local sh_target = clean_arg:gsub("%.krsnvim$", ".sh")
				table.insert(lines, indent .. 'bash "' .. sh_target .. '" 2>/dev/null || nvim -l "' .. clean_arg .. '"')
			else
				table.insert(lines, indent .. 'nvim -l "' .. clean_arg .. '" 2>/dev/null || lua "' .. clean_arg .. '"')
			end

		-- Builtin: os.exit(code)
		elseif trimmed:match("^os%.exit%s*%((.*)%)") then
			local code_arg = trimmed:match("^os%.exit%s*%((.*)%)") or "0"
			table.insert(lines, indent .. "exit " .. format_sh_val(code_arg))

		-- Builtin: os.execute(cmd)
		elseif trimmed:match("^os%.execute%s*%((.*)%)") then
			local cmd_arg = trimmed:match("^os%.execute%s*%((.*)%)")
			local clean_cmd = cmd_arg:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
			table.insert(lines, indent .. clean_cmd)

		-- Builtin: os.remove(path)
		elseif trimmed:match("^os%.remove%s*%((.*)%)") then
			local path_arg = trimmed:match("^os%.remove%s*%((.*)%)")
			table.insert(lines, indent .. "rm -f " .. format_sh_val(path_arg))

		-- Custom standalone function calls or method calls: fn(arg1, arg2) or obj.fn(arg1, arg2) or obj:fn(arg1, arg2)
		elseif trimmed:match("^[%a_][%w_%.%:]*%s*%((.*)%)%s*$") then
			local fn_name, fn_args = trimmed:match("^([%a_][%w_%.%:]*)%s*%((.*)%)%s*$")
			if
				fn_name == "setTimeout"
				or fn_name == "setInterval"
				or fn_name == "clearTimeout"
				or fn_name == "clearInterval"
			then
				table.insert(lines, indent .. "# " .. trimmed)
			elseif fn_name:sub(1, 6) == "async." or fn_name:sub(1, 8) == "coroutine" then
				table.insert(lines, indent .. "# " .. trimmed)
			else
				local sh_args = {}
				for _, arg in ipairs(split_args(fn_args)) do
					table.insert(sh_args, format_sh_val(arg))
				end
				local safe_fn = fn_name:gsub("[%.:]", "_")
				table.insert(lines, indent .. safe_fn .. " " .. table.concat(sh_args, " "))
			end

		-- Loops: for i = start, stop do OR for i = start, stop, step do
		elseif
			trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s+do$")
			or trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s+do$")
		then
			local var, start_val, stop_val, step_val
			if trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s+do$") then
				var, start_val, stop_val, step_val =
					trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s+do$")
			else
				var, start_val, stop_val = trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s+do$")
				step_val = "1"
			end
			table.insert(block_stack, "loop")
			table.insert(
				lines,
				indent
					.. "for (("
					.. var
					.. "="
					.. start_val
					.. "; "
					.. var
					.. "<="
					.. stop_val
					.. "; "
					.. var
					.. "+="
					.. step_val
					.. ")); do"
			)

		-- Loops: for _, item in ipairs(list) do
		elseif trimmed:match("^for%s+[%w_]+%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%(([%a_][%w_]*)%)%s+do$") then
			local item_var, list_var = trimmed:match("^for%s+[%w_]+%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%(([%a_][%w_]*)%)%s+do$")
			table.insert(block_stack, "loop")
			table.insert(lines, indent .. "for " .. item_var .. ' in "${' .. list_var .. '[@]}"; do')

		-- Loops: while cond do
		elseif trimmed:match("^while%s+(.-)%s+do$") then
			local cond = trimmed:match("^while%s+(.-)%s+do$")
			table.insert(block_stack, "loop")
			local mode, cond_str = format_sh_cond(cond)
			if mode == "arithmetic" then
				table.insert(lines, indent .. "while (( " .. cond_str .. " )); do")
			else
				table.insert(lines, indent .. "while [[ " .. cond_str .. " ]]; do")
			end

		-- Control Flow: if ... then
		elseif trimmed:match("^if%s+(.-)%s+then$") then
			local cond = trimmed:match("^if%s+(.-)%s+then$")
			table.insert(block_stack, "if")
			local mode, cond_str = format_sh_cond(cond)
			if mode == "arithmetic" then
				table.insert(lines, indent .. "if (( " .. cond_str .. " )); then")
			else
				table.insert(lines, indent .. "if [[ " .. cond_str .. " ]]; then")
			end

		-- Control Flow: elseif ... then
		elseif trimmed:match("^elseif%s+(.-)%s+then$") then
			local cond = trimmed:match("^elseif%s+(.-)%s+then$")
			local mode, cond_str = format_sh_cond(cond)
			if mode == "arithmetic" then
				table.insert(lines, indent .. "elif (( " .. cond_str .. " )); then")
			else
				table.insert(lines, indent .. "elif [[ " .. cond_str .. " ]]; then")
			end
		-- Control Flow: else
		elseif trimmed == "else" then
			table.insert(lines, indent .. "else")

		-- Block End: end or end)
		elseif trimmed == "end" or trimmed:match("^end%)?") or trimmed == "}" then
			local last_block = table.remove(block_stack)
			if last_block == "if" then
				table.insert(lines, indent .. "fi")
			elseif last_block == "function" or last_block == "fn" then
				table.insert(lines, indent .. "}")
			elseif last_block == "loop" then
				table.insert(lines, indent .. "done")
			elseif last_block == "noop" then
				-- noop block: skip emitting closing token
			elseif last_block then
				table.insert(lines, indent .. "}")
			end
		else
			-- Fallback: pass line with -- turned to #
			table.insert(lines, (line:gsub("^%s*%-%-", indent .. "#")))
		end
	end

	return table.concat(lines, "\n")
end

--- Transpiles `.krsnvim` Lua code string into PowerShell script (`.ps1`).
--- @param code string Full Lua code string of a .krsnvim script.
--- @return string ps1_script Equivalent PowerShell script.
function M.to_ps1(code)
	local lines = {}
	local block_stack = {}
	table.insert(lines, "# ==========================================================================")
	table.insert(lines, "# Transpiled from krsnvimscript (.krsnvim) -> PowerShell (.ps1)")
	table.insert(lines, "# Automatically generated by krsnvimtranspiler")
	table.insert(lines, "# ==========================================================================")
	table.insert(lines, "$ErrorActionPreference = 'Stop'")
	table.insert(lines, "")

	for line in join_multiline_calls(code):gmatch("[^\r\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$")
		local indent = line:match("^(%s*)") or ""

		-- Skip or comment out require/import lines
		if
			trimmed:match("^local%s+[%w_]+%s*=%s*require%(")
			or trimmed:match("^local%s+[%w_]+%s*=%s*import%(")
			or trimmed:match("^require%(")
			or trimmed:match("^import%(")
		then
			table.insert(lines, indent .. "# [krsnvim] " .. trimmed .. " (mapped to native PowerShell cmdlets)")

		-- Comments: -- comment -> # comment
		elseif trimmed:sub(1, 2) == "--" then
			local comment_text = trimmed:sub(3):match("^%s*(.-)%s*$")
			table.insert(lines, indent .. "# " .. comment_text)

		-- Empty lines
		elseif trimmed == "" then
			table.insert(lines, "")

		-- Testing Framework Hooks: test.beforeAll, test.afterAll, test.beforeEach, test.afterEach, etc.
		elseif
			trimmed:match("^[%w_]*%.?beforeAll%s*%(")
			or trimmed:match("^[%w_]*%.?afterAll%s*%(")
			or trimmed:match("^[%w_]*%.?beforeEach%s*%(")
			or trimmed:match("^[%w_]*%.?afterEach%s*%(")
		then
			table.insert(block_stack, "noop")

		-- Testing Framework Suites: describe("suite", function() ...) or test.describe(...)
		elseif trimmed:match("^describe%s*%(") or trimmed:match("^[%w_]+%.describe%s*%(") then
			local suite_name = trimmed:match('describe%s*%("%s*(.-)%s*"')
				or trimmed:match("describe%s*%('%s*(.-)%s*'")
				or "Test Suite"
			table.insert(block_stack, "noop")
			table.insert(lines, indent .. 'Write-Host "📦 Suite: ' .. suite_name .. '"')

		-- Testing Framework Runner: test.run() or t.run() or run()
		elseif trimmed:match("^[%w_]+%.run%s*%(") or trimmed:match("^run%s*%(") then
			table.insert(lines, indent .. "# [krsnvim] " .. trimmed)

		-- Testing Framework Tests: it("test", function() ...) or test("test", function() ...) or test.test(...)
		elseif
			trimmed:match("^it%s*%(")
			or trimmed:match("^test%s*%(")
			or trimmed:match("^[%w_]+%.it%s*%(")
			or trimmed:match("^[%w_]+%.test%s*%(")
		then
			local test_name = trimmed:match('it%s*%("%s*(.-)%s*"')
				or trimmed:match('test%s*%("%s*(.-)%s*"')
				or trimmed:match("it%s*%('%s*(.-)%s*'")
				or trimmed:match("test%s*%('%s*(.-)%s*'")
				or "Test"
			table.insert(block_stack, "noop")
			table.insert(lines, indent .. 'Write-Host "  ✓ ' .. test_name .. '"')

		-- Testing Framework Assertions: expect(val)...
		elseif trimmed:match("^expect%s*%(") then
			local is_inv = trimmed:find("%.isNot%.")
				or trimmed:find('%["not"%]')
				or trimmed:find("%.not%.")
				or trimmed:find("%.not_%.")

			if trimmed:find("%.toBe%s*%(") or trimmed:find("%.toEqual%s*%(") then
				local act, exp = trimmed:match("expect%s*%((.-)%)%..-toBe%s*%((.-)%)")
				if not act then
					act, exp = trimmed:match("expect%s*%((.-)%)%..-toEqual%s*%((.-)%)")
				end
				if act and exp then
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if ("
								.. format_ps1_val(act)
								.. " -eq "
								.. format_ps1_val(exp)
								.. ') { Write-Error "Expect failed"; exit 1 }'
						)
					else
						table.insert(
							lines,
							indent
								.. "if ("
								.. format_ps1_val(act)
								.. " -ne "
								.. format_ps1_val(exp)
								.. ') { Write-Error "Expect failed"; exit 1 }'
						)
					end
				end
			elseif trimmed:find("%.toBeTruthy%s*%(") then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(lines, indent .. "if (" .. format_ps1_val(act) .. ') { Write-Error "Expect failed"; exit 1 }')
					else
						table.insert(
							lines,
							indent .. "if (-not (" .. format_ps1_val(act) .. ')) { Write-Error "Expect failed"; exit 1 }'
						)
					end
				end
			elseif trimmed:find("%.toBeFalsy%s*%(") then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent .. "if (-not (" .. format_ps1_val(act) .. ')) { Write-Error "Expect failed"; exit 1 }'
						)
					else
						table.insert(lines, indent .. "if (" .. format_ps1_val(act) .. ') { Write-Error "Expect failed"; exit 1 }')
					end
				end
			elseif
				trimmed:find("%.toBeNil%s*%(")
				or trimmed:find("%.toBeNull%s*%(")
				or trimmed:find("%.toBeUndefined%s*%(")
			then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent .. "if ($null -eq (" .. format_ps1_val(act) .. ')) { Write-Error "Expect failed"; exit 1 }'
						)
					else
						table.insert(
							lines,
							indent .. "if ($null -ne (" .. format_ps1_val(act) .. ')) { Write-Error "Expect failed"; exit 1 }'
						)
					end
				end
			elseif trimmed:find("%.toBeDefined%s*%(") then
				local act = trimmed:match("expect%s*%((.-)%)%.")
				if act then
					if is_inv then
						table.insert(
							lines,
							indent .. "if ($null -ne (" .. format_ps1_val(act) .. ')) { Write-Error "Expect failed"; exit 1 }'
						)
					else
						table.insert(
							lines,
							indent .. "if ($null -eq (" .. format_ps1_val(act) .. ')) { Write-Error "Expect failed"; exit 1 }'
						)
					end
				end
			elseif trimmed:find("%.toContain%s*%(") then
				local act, item = trimmed:match("expect%s*%((.-)%)%..-toContain%s*%((.-)%)")
				if act and item then
					local clean_item = item:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if ("
								.. format_ps1_val(act)
								.. ' -like "*'
								.. clean_item
								.. '*") { Write-Error "Expect failed"; exit 1 }'
						)
					else
						table.insert(
							lines,
							indent
								.. "if ("
								.. format_ps1_val(act)
								.. ' -notlike "*'
								.. clean_item
								.. '*") { Write-Error "Expect failed"; exit 1 }'
						)
					end
				end
			elseif trimmed:find("%.toHaveLength%s*%(") then
				local act, len = trimmed:match("expect%s*%((.-)%)%..-toHaveLength%s*%((.-)%)")
				if act and len then
					if is_inv then
						table.insert(
							lines,
							indent
								.. "if (("
								.. format_ps1_val(act)
								.. ").Count -eq "
								.. format_ps1_val(len)
								.. ') { Write-Error "Expect failed"; exit 1 }'
						)
					else
						table.insert(
							lines,
							indent
								.. "if (("
								.. format_ps1_val(act)
								.. ").Count -ne "
								.. format_ps1_val(len)
								.. ') { Write-Error "Expect failed"; exit 1 }'
						)
					end
				end
			elseif trimmed:find("%.toBeGreaterThan%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeGreaterThan%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if ("
							.. format_ps1_val(act)
							.. " -le "
							.. format_ps1_val(num)
							.. ') { Write-Error "Expect failed"; exit 1 }'
					)
				end
			elseif trimmed:find("%.toBeGreaterThanOrEqual%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeGreaterThanOrEqual%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if ("
							.. format_ps1_val(act)
							.. " -lt "
							.. format_ps1_val(num)
							.. ') { Write-Error "Expect failed"; exit 1 }'
					)
				end
			elseif trimmed:find("%.toBeLessThan%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeLessThan%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if ("
							.. format_ps1_val(act)
							.. " -ge "
							.. format_ps1_val(num)
							.. ') { Write-Error "Expect failed"; exit 1 }'
					)
				end
			elseif trimmed:find("%.toBeLessThanOrEqual%s*%(") then
				local act, num = trimmed:match("expect%s*%((.-)%)%..-toBeLessThanOrEqual%s*%((.-)%)")
				if act and num then
					table.insert(
						lines,
						indent
							.. "if ("
							.. format_ps1_val(act)
							.. " -gt "
							.. format_ps1_val(num)
							.. ') { Write-Error "Expect failed"; exit 1 }'
					)
				end
			elseif trimmed:find("%.toThrow") then
				local fn = trimmed:match("expect%s*%((.-)%)%..-toThrow")
				if fn then
					table.insert(
						lines,
						indent
							.. "try { "
							.. format_ps1_val(fn)
							.. '; Write-Error "Expect failed: expected error"; exit 1 } catch {}'
					)
				end
			end

		-- Function definitions or Coroutine creation: function fn_name(arg1, arg2)
		elseif
			trimmed:match("^function%s+([%w_]+)%s*%((.*)%)")
			or trimmed:match("^local%s+function%s+([%w_]+)%s*%((.*)%)")
			or trimmed:match("coroutine%..-%(%s*function%s*%((.*)%)")
		then
			local fn_name, params_str
			if trimmed:match("coroutine%..-%(%s*function%s*%((.*)%)") then
				fn_name = trimmed:match("^local%s+([%a_][%w_]*)%s*=") or trimmed:match("^([%a_][%w_]*)%s*=") or "co_fn"
				params_str = trimmed:match("coroutine%..-%(%s*function%s*%((.*)%)")
			else
				fn_name, params_str = trimmed:match("function%s+([%w_]+)%s*%((.*)%)")
			end
			local ps_params = {}
			for param in (params_str or ""):gmatch("[^,]+") do
				param = param:match("^%s*(.-)%s*$")
				if param ~= "" then
					table.insert(ps_params, "$" .. param)
				end
			end
			table.insert(lines, indent .. "function " .. fn_name .. "(" .. table.concat(ps_params, ", ") .. ") {")

		-- Return statements: return expr
		elseif trimmed:match("^return%s*(.*)$") then
			local ret_expr = trimmed:match("^return%s*(.*)$"):match("^%s*(.-)%s*$")
			if ret_expr ~= "" then
				local fn1, a1, op, fn2, a2 = ret_expr:match("^([%a_][%w_]*)%((.*)%)%s*([+%*%/%-])%s*([%a_][%w_]*)%((.*)%)$")
				if fn1 and a1 and op and fn2 and a2 then
					table.insert(
						lines,
						indent
							.. "return ("
							.. fn1
							.. " ("
							.. to_ps1_expr(a1)
							.. ")) "
							.. op
							.. " ("
							.. fn2
							.. " ("
							.. to_ps1_expr(a2)
							.. "))"
					)
				else
					table.insert(lines, indent .. "return " .. format_ps1_val(ret_expr))
				end
			else
				table.insert(lines, indent .. "return")
			end

		-- coroutine.yield(...) -> Write-Output ...
		elseif trimmed:match("^coroutine%.yield%((.*)%)") then
			local args = trimmed:match("^coroutine%.yield%((.*)%)")
			local parts = {}
			for _, part in ipairs(split_args(args)) do
				table.insert(parts, format_ps1_val(part))
			end
			table.insert(lines, indent .. "Write-Output " .. table.concat(parts, " "))

		-- Multiple variable assignment: local ok, val = coroutine.resume(co, arg) OR pcall(fn, arg)
		elseif trimmed:match("^local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*(.-)%((.*)%)") then
			local var_ok, var_res, fn_call, fn_args =
				trimmed:match("^local%s+([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*=%s*(.-)%((.*)%)")
			fn_call = fn_call:match("^%s*(.-)%s*$")
			if fn_call == "coroutine.resume" then
				local args_parts = split_args(fn_args)
				local co_name = args_parts[1] or "co"
				local extra_args = {}
				for i = 2, #args_parts do
					table.insert(extra_args, format_ps1_val(args_parts[i]))
				end
				table.insert(
					lines,
					indent .. "$" .. var_res .. " = (" .. co_name .. " " .. table.concat(extra_args, " ") .. ")"
				)
				table.insert(lines, indent .. "$" .. var_ok .. " = $true")
			elseif fn_call == "pcall" then
				local args_parts = split_args(fn_args)
				local target_fn = args_parts[1] or "fn"
				local extra_args = {}
				for i = 2, #args_parts do
					table.insert(extra_args, format_ps1_val(args_parts[i]))
				end
				table.insert(lines, indent .. "try {")
				table.insert(lines, indent .. "  $" .. var_res .. " = " .. target_fn .. " " .. table.concat(extra_args, " "))
				table.insert(lines, indent .. "  $" .. var_ok .. " = $true")
				table.insert(lines, indent .. "} catch {")
				table.insert(lines, indent .. "  $" .. var_ok .. " = $false")
				table.insert(lines, indent .. "}")
			end

		-- print(...) -> Write-Host ...
		elseif trimmed:match("^print%((.*)%)") then
			local args = trimmed:match("^print%((.*)%)")
			local parts = {}
			for _, part in ipairs(split_args(args)) do
				table.insert(parts, format_ps1_val(part))
			end
			table.insert(lines, indent .. "Write-Host " .. table.concat(parts, " "))

		-- console.log(...) / console.info(...) -> Write-Host ...
		elseif trimmed:match("^console%.[%w_]+%((.*)%)%s*$") then
			local args = trimmed:match("^console%.[%w_]+%((.*)%)%s*$")
			local parts = {}
			for _, raw in ipairs(split_args(args)) do
				if raw:sub(1, 1) == "{" then
					table.insert(parts, lua_tbl_to_ps1(raw))
				else
					table.insert(parts, format_ps1_val(raw))
				end
			end
			table.insert(lines, indent .. "Write-Host " .. table.concat(parts, " "))

		-- error(msg) -> throw msg
		elseif trimmed:match("^error%((.*)%)") then
			local err_msg = trimmed:match("^error%((.*)%)")
			table.insert(lines, indent .. "throw " .. format_ps1_val(err_msg))

		-- assert(cond, msg) -> if (-not (cond)) { throw msg }
		elseif trimmed:match("^assert%((.*)%)") then
			local args = split_args(trimmed:match("^assert%((.*)%)"))
			local cond = args[1] or "true"
			local msg = args[2] or '"Assertion failed"'
			table.insert(lines, indent .. "if (-not (" .. to_ps1_expr(cond) .. ")) { throw " .. format_ps1_val(msg) .. " }")

		-- fs.mkdir(path) -> New-Item -ItemType Directory -Force -Path path | Out-Null
		elseif trimmed:match("^fs%.mkdir%((.*)%)") then
			local path_arg = trimmed:match("^fs%.mkdir%((.*)%)")
			table.insert(
				lines,
				indent .. "New-Item -ItemType Directory -Force -Path " .. format_ps1_val(path_arg) .. " | Out-Null"
			)

		-- fs.write(path, content) -> Set-Content -Path path -Value content
		elseif trimmed:match("^fs%.write%((.*)%)") then
			local args = split_args(trimmed:match("^fs%.write%((.*)%)"))
			local path_arg = args[1]
			local content_arg = args[2] or '""'
			table.insert(
				lines,
				indent .. "Set-Content -Path " .. format_ps1_val(path_arg) .. " -Value " .. format_ps1_val(content_arg)
			)

		-- fs.remove(path) / fs.delete(path) -> Remove-Item -Recurse -Force path
		elseif trimmed:match("^fs%.remove%((.*)%)") or trimmed:match("^fs%.delete%((.*)%)") then
			local path_arg = trimmed:match("%((.*)%)")
			table.insert(lines, indent .. "Remove-Item -Recurse -Force -Path " .. format_ps1_val(path_arg))

		-- $ "cmd" or terminal.exec("cmd") -> cmd
		elseif
			trimmed:match("^%s*%$%s*%((.*)%)")
			or trimmed:match("^%s*terminal%.exec%((.*)%)")
			or trimmed:match("^%s*terminal%.run%((.*)%)")
		then
			local cmd_arg = trimmed:match("%((.*)%)")
			cmd_arg = cmd_arg:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
			table.insert(lines, indent .. cmd_arg)

		-- Variable assignments: local var = val OR var = val
		elseif trimmed:match("^local%s+[%a_][%w_]*%s*=%s*") or trimmed:match("^[%a_][%w_]*%s*=%s*") then
			local is_local, var, val
			if trimmed:match("^local%s+") then
				var, val = trimmed:match("^local%s+([%a_][%w_]*)%s*=%s*(.*)$")
				is_local = true
			else
				var, val = trimmed:match("^([%a_][%w_]*)%s*=%s*(.*)$")
				is_local = false
			end

			-- Table/array literal: local list = { "a", "b" }
			if val:sub(1, 1) == "{" and val:sub(-1) == "}" then
				table.insert(lines, indent .. "$" .. var .. " = " .. lua_tbl_to_ps1(val))

			-- Builtin: fs.read(path) -> Get-Content -Raw path
			elseif val:match("^fs%.read%((.*)%)") then
				local path_arg = val:match("^fs%.read%((.*)%)")
				table.insert(lines, indent .. "$" .. var .. " = Get-Content -Raw " .. format_ps1_val(path_arg))

			-- Builtin: json.encode(obj) -> obj | ConvertTo-Json -Compress
			elseif val:match("^json%.encode%((.*)%)") then
				local obj_arg = val:match("^json%.encode%((.*)%)")
				local ps1_obj = obj_arg:sub(1, 1) == "{" and lua_tbl_to_ps1(obj_arg) or format_ps1_val(obj_arg)
				table.insert(lines, indent .. "$" .. var .. " = (" .. ps1_obj .. " | ConvertTo-Json -Compress)")

			-- Builtin: json.load(path) -> Get-Content -Raw path | ConvertFrom-Json
			elseif val:match("^json%.load%((.*)%)") then
				local path_arg = val:match("^json%.load%((.*)%)")
				table.insert(
					lines,
					indent .. "$" .. var .. " = (Get-Content -Raw " .. format_ps1_val(path_arg) .. " | ConvertFrom-Json)"
				)

			-- Builtin: fetch.get(url) -> Invoke-WebRequest
			elseif val:match("^fetch%.get%((.*)%)") then
				local url_arg = val:match("^fetch%.get%((.*)%)")
				table.insert(
					lines,
					indent
						.. "$"
						.. var
						.. " = (Invoke-WebRequest -Uri "
						.. format_ps1_val(url_arg)
						.. " -UseBasicParsing).Content"
				)

			-- Builtin: fetch.json(url) -> Invoke-RestMethod
			elseif val:match("^fetch%.json%((.*)%)") then
				local url_arg = val:match("^fetch%.json%((.*)%)")
				table.insert(lines, indent .. "$" .. var .. " = Invoke-RestMethod -Uri " .. format_ps1_val(url_arg))

			-- Builtin: terminal execution
			elseif val:match("^terminal%..-%((.*)%)") or val:match("^%s*%$%s*%((.*)%)") then
				local cmd_arg = val:match("%((.*)%)"):gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
				table.insert(lines, indent .. "$" .. var .. " = (" .. cmd_arg .. ")")

			-- Custom function call: var = fn(a, b)
			elseif val:match("^[%a_][%w_]*%s*%((.*)%)") then
				local fn_name, fn_args = val:match("^([%a_][%w_]*)%s*%((.*)%)")
				if
					fn_name == "setTimeout"
					or fn_name == "setInterval"
					or fn_name == "clearTimeout"
					or fn_name == "clearInterval"
				then
					table.insert(lines, indent .. "$" .. var .. ' = "timer_id"')
				else
					local ps_args = {}
					for _, arg in ipairs(split_args(fn_args)) do
						table.insert(ps_args, format_ps1_val(arg))
					end
					table.insert(lines, indent .. "$" .. var .. " = (" .. fn_name .. " " .. table.concat(ps_args, " ") .. ")")
				end

			-- Standard value / math assignment
			else
				table.insert(lines, indent .. "$" .. var .. " = " .. format_ps1_val(val))
			end

		-- Builtin: async.sleep(ms) / sleep(ms) -> Start-Sleep -Milliseconds ms
		elseif trimmed:match("^async%.sleep%s*%((.*)%)") or trimmed:match("^sleep%s*%((.*)%)") then
			local ms_arg = trimmed:match("^async%.sleep%s*%((.*)%)") or trimmed:match("^sleep%s*%((.*)%)")
			local ms_val = format_ps1_val(ms_arg)
			table.insert(lines, indent .. "Start-Sleep -Milliseconds " .. ms_val)

		-- Builtin: JS-style Timers (setTimeout, setInterval, clearTimeout, clearInterval)
		elseif
			trimmed:match("^setTimeout%s*%(")
			or trimmed:match("^setInterval%s*%(")
			or trimmed:match("^clearTimeout%s*%(")
			or trimmed:match("^clearInterval%s*%(")
		then
			table.insert(lines, indent .. "# " .. trimmed)

		-- Builtin: async channel & coroutine / task calls
		elseif trimmed:match("^async%..-%((.*)%)") then
			table.insert(lines, indent .. "# " .. trimmed)

		-- Builtin: dofile(path) / loadfile(path) -> nvim -l path or pwsh path.ps1
		elseif trimmed:match("^dofile%s*%((.*)%)") or trimmed:match("^loadfile%s*%((.*)%)") then
			local file_arg = trimmed:match("^dofile%s*%((.*)%)") or trimmed:match("^loadfile%s*%((.*)%)")
			local clean_arg = file_arg:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
			if clean_arg:match("%.krsnvim$") then
				local ps_target = clean_arg:gsub("%.krsnvim$", ".ps1")
				table.insert(
					lines,
					indent
						.. 'if (Test-Path "'
						.. ps_target
						.. '") { pwsh -NoProfile -File "'
						.. ps_target
						.. '" } else { nvim -l "'
						.. clean_arg
						.. '" }'
				)
			else
				table.insert(lines, indent .. 'nvim -l "' .. clean_arg .. '"')
			end

		-- Builtin: os.exit(code)
		elseif trimmed:match("^os%.exit%s*%((.*)%)") then
			local code_arg = trimmed:match("^os%.exit%s*%((.*)%)") or "0"
			table.insert(lines, indent .. "exit " .. format_ps1_val(code_arg))

		-- Builtin: os.execute(cmd)
		elseif trimmed:match("^os%.execute%s*%((.*)%)") then
			local cmd_arg = trimmed:match("^os%.execute%s*%((.*)%)")
			local clean_cmd = cmd_arg:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
			table.insert(lines, indent .. clean_cmd)

		-- Builtin: os.remove(path)
		elseif trimmed:match("^os%.remove%s*%((.*)%)") then
			local path_arg = trimmed:match("^os%.remove%s*%((.*)%)")
			table.insert(lines, indent .. "Remove-Item -Force " .. format_ps1_val(path_arg))

		-- Custom standalone function calls or method calls: fn(arg1, arg2) or obj.fn(arg1, arg2) or obj:fn(arg1, arg2)
		elseif trimmed:match("^[%a_][%w_%.%:]*%s*%((.*)%)%s*$") then
			local fn_name, fn_args = trimmed:match("^([%a_][%w_%.%:]*)%s*%((.*)%)%s*$")
			if
				fn_name == "setTimeout"
				or fn_name == "setInterval"
				or fn_name == "clearTimeout"
				or fn_name == "clearInterval"
			then
				table.insert(lines, indent .. "# " .. trimmed)
			elseif fn_name:sub(1, 6) == "async." or fn_name:sub(1, 8) == "coroutine" then
				table.insert(lines, indent .. "# " .. trimmed)
			else
				local ps_args = {}
				for _, arg in ipairs(split_args(fn_args)) do
					table.insert(ps_args, format_ps1_val(arg))
				end
				if fn_name:find("%.") or fn_name:find(":") then
					local ps_target = "$" .. fn_name:gsub(":", ".")
					table.insert(lines, indent .. ps_target .. "(" .. table.concat(ps_args, ", ") .. ")")
				else
					table.insert(lines, indent .. fn_name .. " " .. table.concat(ps_args, " "))
				end
			end

		-- Loops: for i = start, stop do OR for i = start, stop, step do
		elseif
			trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s+do$")
			or trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s+do$")
		then
			local var, start_val, stop_val, step_val
			if trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s+do$") then
				var, start_val, stop_val, step_val =
					trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s+do$")
			else
				var, start_val, stop_val = trimmed:match("^for%s+([%a_][%w_]*)%s*=%s*(.-)%s*,%s*(.-)%s+do$")
				step_val = "1"
			end
			table.insert(
				lines,
				indent
					.. "for ($"
					.. var
					.. " = "
					.. format_ps1_val(start_val)
					.. "; $"
					.. var
					.. " -le "
					.. format_ps1_val(stop_val)
					.. "; $"
					.. var
					.. " += "
					.. format_ps1_val(step_val)
					.. ") {"
			)

		-- Loops: for _, item in ipairs(list) do
		elseif trimmed:match("^for%s+[%w_]+%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%(([%a_][%w_]*)%)%s+do$") then
			local item_var, list_var = trimmed:match("^for%s+[%w_]+%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%(([%a_][%w_]*)%)%s+do$")
			table.insert(lines, indent .. "foreach ($" .. item_var .. " in $" .. list_var .. ") {")

		-- Loops: while cond do
		elseif trimmed:match("^while%s+(.-)%s+do$") then
			local cond = trimmed:match("^while%s+(.-)%s+do$")
			table.insert(lines, indent .. "while (" .. to_ps1_expr(cond) .. ") {")

		-- Control Flow: if ... then
		elseif trimmed:match("^if%s+(.-)%s+then$") then
			local cond = trimmed:match("^if%s+(.-)%s+then$")
			if cond:match("^not%s+fs%.exists%((.*)%)") then
				local p = cond:match("^not%s+fs%.exists%((.*)%)")
				table.insert(lines, indent .. "if (-not (Test-Path " .. format_ps1_val(p) .. ")) {")
			elseif cond:match("^fs%.exists%((.*)%)") then
				local p = cond:match("^fs%.exists%((.*)%)")
				table.insert(lines, indent .. "if (Test-Path " .. format_ps1_val(p) .. ") {")
			else
				table.insert(lines, indent .. "if (" .. to_ps1_expr(cond) .. ") {")
			end

		-- Control Flow: elseif ... then
		elseif trimmed:match("^elseif%s+(.-)%s+then$") then
			local cond = trimmed:match("^elseif%s+(.-)%s+then$")
			if cond:match("^not%s+fs%.exists%((.*)%)") then
				local p = cond:match("^not%s+fs%.exists%((.*)%)")
				table.insert(lines, indent .. "} elseif (-not (Test-Path " .. format_ps1_val(p) .. ")) {")
			elseif cond:match("^fs%.exists%((.*)%)") then
				local p = cond:match("^fs%.exists%((.*)%)")
				table.insert(lines, indent .. "} elseif (Test-Path " .. format_ps1_val(p) .. ") {")
			else
				table.insert(lines, indent .. "} elseif (" .. to_ps1_expr(cond) .. ") {")
			end

		-- Control Flow: else
		elseif trimmed == "else" then
			table.insert(lines, indent .. "} else {")

		-- Block End: end or end)
		elseif trimmed == "end" or trimmed:match("^end%)?") or trimmed == "}" then
			local last_block = table.remove(block_stack)
			if last_block ~= "noop" then
				table.insert(lines, indent .. "}")
			end
		else
			-- Fallback: convert local variable names to $var and comments to #
			local l = line:gsub("^%s*%-%-", indent .. "#")
			table.insert(lines, l)
		end
	end

	return table.concat(lines, "\n")
end

--- Exports a given .krsnvim script file to .sh (Bash) script.
--- @param filepath string Path to source .krsnvim script file.
--- @param outpath string|nil Target .sh file path. Defaults to replacing .krsnvim with .sh.
--- @return string generated_path Path of generated .sh file.
function M.export_sh(filepath, outpath)
	if not filepath or filepath == "" then
		if vim and vim.api then
			filepath = vim.api.nvim_buf_get_name(0)
		end
	end
	if not filepath or filepath == "" then
		error("krsnvimtranspiler: No source file provided for export")
	end

	local content = fs.read(filepath)
	local sh_code = M.to_sh(content)

	if not outpath or outpath == "" then
		outpath = filepath:gsub("%.krsnvim$", "") .. ".sh"
		if outpath == filepath then
			outpath = filepath .. ".sh"
		end
	end

	fs.write(outpath, sh_code)
	if vim and vim.notify then
		vim.notify(
			"🦊 Exported " .. vim.fn.fnamemodify(filepath, ":t") .. " -> " .. vim.fn.fnamemodify(outpath, ":t"),
			vim.log.levels.INFO
		)
	end
	return outpath
end

--- Exports a given .krsnvim script file to .ps1 (PowerShell) script.
--- @param filepath string Path to source .krsnvim script file.
--- @param outpath string|nil Target .ps1 file path. Defaults to replacing .krsnvim with .ps1.
--- @return string generated_path Path of generated .ps1 file.
function M.export_ps1(filepath, outpath)
	if not filepath or filepath == "" then
		if vim and vim.api then
			filepath = vim.api.nvim_buf_get_name(0)
		end
	end
	if not filepath or filepath == "" then
		error("krsnvimtranspiler: No source file provided for export")
	end

	local content = fs.read(filepath)
	local ps1_code = M.to_ps1(content)

	if not outpath or outpath == "" then
		outpath = filepath:gsub("%.krsnvim$", "") .. ".ps1"
		if outpath == filepath then
			outpath = filepath .. ".ps1"
		end
	end

	fs.write(outpath, ps1_code)
	if vim and vim.notify then
		vim.notify(
			"🦊 Exported " .. vim.fn.fnamemodify(filepath, ":t") .. " -> " .. vim.fn.fnamemodify(outpath, ":t"),
			vim.log.levels.INFO
		)
	end
	return outpath
end

--- Exports a given .krsnvim script file to BOTH .sh and .ps1 scripts simultaneously.
--- @param filepath string|nil Path to source .krsnvim script file. Defaults to current active buffer.
--- @return table paths { sh = string, ps1 = string }
function M.export_both(filepath)
	if not filepath or filepath == "" then
		if vim and vim.api then
			filepath = vim.api.nvim_buf_get_name(0)
		end
	end
	local sh_path = M.export_sh(filepath)
	local ps1_path = M.export_ps1(filepath)
	return { sh = sh_path, ps1 = ps1_path }
end

return M
