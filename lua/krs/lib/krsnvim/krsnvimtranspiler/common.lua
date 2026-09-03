-- ============================================================================
-- KRSNVIMSCRIPT TRANSPILER -- Shared Parsing & Formatting Helpers
-- ============================================================================

local fs = require("krs.lib.krsnvim.fs")

local M = {}

--- Reserved Lua keywords and boolean constants to prevent invalid variable prefixing.
M.LUA_KEYWORDS = {
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
function M.mask_strings(text)
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
function M.unmask_strings(text, strings)
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
function M.split_args(args)
	if not args or args == "" then
		return {}
	end
	local masked, strings = M.mask_strings(args)
	local parts, depth, current = {}, 0, ""
	for i = 1, #masked do
		local c = masked:sub(i, i)
		if c == "{" or c == "(" then
			depth = depth + 1
		elseif c == "}" or c == ")" then
			depth = depth - 1
		end
		if c == "," and depth == 0 then
			table.insert(parts, (M.unmask_strings(current, strings)):match("^%s*(.-)%s*$"))
			current = ""
		else
			current = current .. c
		end
	end
	if current:match("%S") then
		table.insert(parts, (M.unmask_strings(current, strings)):match("^%s*(.-)%s*$"))
	end
	return parts
end

--- Joins source lines whose parens haven't balanced yet.
--- @param code string
--- @return string
function M.join_multiline_calls(code)
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

--- Converts a Lua expression into PowerShell syntax.
--- @param expr string
--- @return string
function M.to_ps1_expr(expr)
	if not expr or expr == "" then
		return ""
	end
	local masked, strings = M.mask_strings(expr)

	masked = masked:gsub("([%w_]+):([%w_]+)%(", "%1.%2(")
	masked = masked:gsub("%s*%.%.%s*", " + ")

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
		if M.LUA_KEYWORDS[word] then
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

	masked = masked:gsub("%s+", " ")

	return (M.unmask_strings(masked, strings))
end

--- Formats a single argument/value for PowerShell.
--- @param val string
--- @return string
function M.format_ps1_val(val)
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

	if val:find("%.%.") then
		local parts = {}
		local masked, strings = M.mask_strings(val)
		for part in masked:gmatch("[^%.]+") do
			part = part:match("^%s*(.-)%s*$")
			if part ~= "" then
				if part:match("^___STR_%d+___$") then
					table.insert(parts, (M.unmask_strings(part, strings)))
				elseif tonumber(part) then
					table.insert(parts, part)
				elseif M.LUA_KEYWORDS[part] then
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

	return M.to_ps1_expr(val)
end

--- Helper to convert Lua table literal to PowerShell Hashtable syntax (@{...}) or Array (@(...)).
--- @param lua_tbl_str string
--- @return string
function M.lua_tbl_to_ps1(lua_tbl_str)
	if not lua_tbl_str then
		return "@()"
	end
	local s = lua_tbl_str:match("^%s*{?(.-)}?%s*$")
	if not s or s == "" then
		return "@()"
	end

	local args = M.split_args(s)
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
				table.insert(items, '"' .. k .. '"=' .. M.format_ps1_val(v))
			else
				table.insert(items, kv)
			end
		end
		return "@{" .. table.concat(items, "; ") .. "}"
	else
		local items = {}
		for _, v in ipairs(args) do
			table.insert(items, M.format_ps1_val(v))
		end
		return "@(" .. table.concat(items, ", ") .. ")"
	end
end

--- Formats a single argument/value for Bash.
--- @param val string
--- @return string
function M.format_sh_val(val)
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

	if val:find("%.%.") then
		local parts = {}
		local masked, strings = M.mask_strings(val)
		for part in masked:gmatch("[^%.]+") do
			part = part:match("^%s*(.-)%s*$")
			if part ~= "" then
				if part:match("^___STR_%d+___$") then
					local unmasked = M.unmask_strings(part, strings)
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

	if val:match("[+%*%/%-]") and not val:find('"') and not val:find("'") then
		if val:match("%.") then
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
function M.lua_tbl_to_json(lua_tbl_str)
	if not lua_tbl_str then
		return "'{}'"
	end
	local s = lua_tbl_str:match("^%s*{?(.-)}?%s*$")
	if not s or s == "" then
		return "'{}'"
	end
	local args = M.split_args(s)
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
function M.format_sh_cond(cond)
	cond = cond:match("^%s*(.-)%s*$")
	if cond:match("^not%s+fs%.exists%((.*)%)%s*$") then
		local p = cond:match("^not%s+fs%.exists%((.*)%)%s*$")
		return "test", "! -e " .. M.format_sh_val(p)
	elseif cond:match("^fs%.exists%((.*)%)%s*$") then
		local p = cond:match("^fs%.exists%((.*)%)%s*$")
		return "test", "-e " .. M.format_sh_val(p)
	end

	local is_not = false
	if cond:match("^not%s+(.*)$") then
		is_not = true
		cond = cond:match("^not%s+(.*)$")
	end

	if cond:match("[+%*%/%-]") and not cond:find('"') and not cond:find("'") and not cond:find("%(") then
		local arith_expr = cond:gsub("~=", "!=")
		if is_not then
			return "arithmetic", "! ( " .. arith_expr .. " )"
		end
		return "arithmetic", arith_expr
	end

	local masked, strings = M.mask_strings(cond)

	masked = masked:gsub("[%a_][%w_]*", function(w)
		if M.LUA_KEYWORDS[w] then
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

	masked = masked:gsub("%(", " ( ")
	masked = masked:gsub("%)", " ) ")
	masked = masked:gsub("%s+", " ")

	local res = (M.unmask_strings(masked, strings))
	if is_not then
		return "test", "! " .. res
	end
	return "test", res
end

return M
